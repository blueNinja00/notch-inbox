// Notch Inbox Link
// Every minute (and within seconds when an open Gmail tab shows new or read mail), for each
// Gmail account signed in to this browser, using the browser's own sign-in:
//   1. read the unread-mail feeds: the Primary tab, plus the whole inbox so that Google
//      Classroom and other mail from Google that Gmail files under Updates isn't missed;
//   2. hand them to the Notch Inbox app on this Mac;
//   3. open the emails the app asks for (Gmail's "Show original"), decode them (mime.js)
//      and hand those over too, so the notch can show them in full.
// It only talks to mail.google.com and 127.0.0.1 (this Mac).

importScripts('mime.js');

const APP = 'http://127.0.0.1:47823';
const GMAIL = 'https://mail.google.com/mail/u/';
const MAX_ACCOUNTS = 6;
const PRIMARY_FEED = 'feed/atom/%5Esq_ig_i_personal';
const INBOX_FEED = 'feed/atom';
const EMAILS_PER_SYNC = 8;
const IK_RETRY_MS = 30 * 60 * 1000;
const TITLE_SYNC_GAP_MS = 15 * 1000;
const APP_RETRY_MS = [5 * 1000, 15 * 1000];
const AWAKE_PING_MS = 20 * 1000;
const VERSION = chrome.runtime.getManifest().version;

chrome.runtime.onInstalled.addListener(start);
chrome.runtime.onStartup.addListener(start);

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === 'sync') sync();
  if (alarm.name === 'app') syncIfAppRestarted();
});

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message && message.type === 'sync-now') {
    sync().then(sendResponse);
    return true; // answers asynchronously
  }
  return false;
});

function start() {
  chrome.alarms.create('sync', { periodInMinutes: 1 });
  // Every 30 seconds, a quick look at the app (nothing goes to Gmail): if it has just
  // started, after an update say, sync now rather than at the next minute.
  chrome.alarms.create('app', { periodInMinutes: 0.5 });
  sync();
}

async function syncIfAppRestarted() {
  const launch = await appLaunch();
  if (!launch) return;
  const saved = await chrome.storage.local.get('appLaunch');
  if (saved.appLaunch !== launch) sync();
}

// Gmail retitles its tab ("Inbox (3) - you@gmail.com - Gmail") the moment mail arrives or
// is read, so an open Gmail tab lets the notch catch up within seconds.
chrome.tabs.onUpdated.addListener((_tabId, changeInfo, tab) => {
  if (!changeInfo.title || !String(tab.url || '').startsWith('https://mail.google.com/')) return;
  if (!/\s-\s\S+@\S+\s-\s/.test(changeInfo.title)) return; // e.g. a chat message flashing in the title
  syncSoon();
});

let soon = null;
let lastSoon = 0;
function syncSoon() {
  if (soon) return;
  const wait = Math.max(2000, lastSoon + TITLE_SYNC_GAP_MS - Date.now());
  soon = setTimeout(() => {
    soon = null;
    lastSoon = Date.now();
    sync();
  }, wait);
}

// When the app is restarting (after an update, say), try again shortly rather than in a minute.
let appRetries = 0;
function retryForApp() {
  if (appRetries >= APP_RETRY_MS.length) return;
  setTimeout(sync, APP_RETRY_MS[appRetries]);
  appRetries += 1;
}

// The app's launch ID when it's running (any non-empty value for older versions), else null.
async function appLaunch() {
  try {
    const response = await fetch(`${APP}/feeds`, { method: 'OPTIONS' });
    if (!response.ok) return null;
    return (response.headers && response.headers.get('X-Notch-Launch')) || 'running';
  } catch (error) {
    return null;
  }
}

// One sync at a time: the alarm, browser start-up and "Sync now" can overlap.
let running = null;
function sync() {
  if (!running) {
    const release = keepAwake();
    running = syncOnce().finally(() => {
      release();
      running = null;
    });
  }
  return running;
}

// The browser pauses an add-on that goes quiet for 30 seconds, even mid-way through a sync
// that's waiting on Gmail. A tiny call every 20 seconds keeps it going until it's done.
function keepAwake() {
  const timer = setInterval(() => {
    chrome.runtime.getPlatformInfo().catch(() => {});
  }, AWAKE_PING_MS);
  return () => clearInterval(timer);
}

async function syncOnce() {
  // Nothing to do while the app isn't running: don't read Gmail for nobody.
  const launch = await appLaunch();
  if (!launch) {
    const status = { ok: false, message: 'Notch Inbox isn’t running on this Mac.', accounts: [], at: Date.now() };
    await chrome.storage.local.set({ status });
    retryForApp();
    return status;
  }
  appRetries = 0;
  await chrome.storage.local.set({ appLaunch: launch });

  const feeds = [];
  const seen = new Set();
  for (let index = 0; index < MAX_ACCOUNTS; index += 1) {
    const feed = await readAccount(index);
    if (!feed) continue; // nobody signed in at this slot
    if (feed.account && seen.has(feed.account)) break; // Gmail wrapped round to an account we already have
    if (feed.account) seen.add(feed.account);
    feeds.push(feed);
  }

  const saved = await chrome.storage.local.get(['fullEmails', 'reloadedFor', 'wholeFetched']);
  const fullEmails = saved.fullEmails || 'unknown';
  let status;
  let reply = null;
  if (feeds.length === 0) {
    status = { ok: false, message: 'No signed-in Gmail accounts found in this browser.' };
  } else {
    try {
      const response = await fetch(`${APP}/feeds`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ feeds, version: VERSION, fullEmails }),
      });
      if (response.ok) {
        status = { ok: true, message: 'Linked to Notch Inbox.' };
        reply = await readJSON(response);
      } else {
        status = { ok: false, message: `Notch Inbox turned the update away (${response.status}).` };
      }
    } catch (error) {
      status = { ok: false, message: 'Notch Inbox isn’t running on this Mac.' };
      retryForApp();
    }
  }
  status.accounts = feeds.map((feed) => feed.account).filter(Boolean);
  status.counts = Object.fromEntries(feeds.filter((feed) => feed.account).map((feed) => [feed.account, {
    primary: feed.primary ? unreadIn(feed.xml) : null,
    inbox: feed.primary ? unreadIn(feed.extra) : unreadIn(feed.xml),
  }]));
  status.at = Date.now();
  console.info('[Notch Inbox Link] sync', new Date().toLocaleTimeString(), status.message,
    JSON.stringify(status.counts), `asked for ${reply && Array.isArray(reply.want) ? reply.want.length : 0} whole emails`);
  status.fullEmails = fullEmails;
  status.wholeFetched = saved.wholeFetched || 0;
  await chrome.storage.local.set({ status });

  // The app was updated and brought a newer copy of this add-on with it: switch to it
  // (once per version, so a copy that didn't arrive can't cause a reload loop).
  if (reply && typeof reply.addon === 'string' && reply.addon !== VERSION && saved.reloadedFor !== reply.addon) {
    await chrome.storage.local.set({ reloadedFor: reply.addon });
    chrome.runtime.reload();
    return status;
  }

  if (reply && Array.isArray(reply.want) && reply.want.length > 0) {
    await readWholeEmails(reply.want, feeds, status);
  }
  return status;
}

async function readJSON(response) {
  try {
    return await response.json();
  } catch (error) {
    return null; // older versions of the app answer with an empty body
  }
}

async function readAccount(index) {
  const primary = await getFeed(index, PRIMARY_FEED);
  const inbox = await getFeed(index, INBOX_FEED);
  const xml = primary || inbox;
  if (!xml) return null;
  const feed = { index, account: accountIn(xml), xml, primary: Boolean(primary) };
  if (primary && inbox) feed.extra = inbox; // the app picks Google's own mail out of it
  return feed;
}

// Gmail's unread count from a feed, for the popup and the console.
function unreadIn(xml) {
  const match = xml && /<fullcount>(\d+)<\/fullcount>/.exec(xml);
  return match ? Number(match[1]) : null;
}

// The feed's own <title> ends with the signed-in address.
function accountIn(xml) {
  const title = xml.match(/<title>([^<]*)<\/title>/);
  const address = title && title[1].match(/[^\s<>]+@[^\s<>]+/);
  return address ? address[0].toLowerCase() : null;
}

async function getFeed(index, path) {
  const xml = await getText(`${GMAIL}${index}/${path}`);
  return xml && xml.includes('<feed') ? xml : null;
}

async function getText(url) {
  try {
    const response = await fetch(url, { credentials: 'include', cache: 'no-store' });
    return response.ok ? await response.text() : null;
  } catch (error) {
    return null;
  }
}

// ---- Whole emails --------------------------------------------------------------------------

// Opens the emails the app asked for and hands them over. In case opening an email this way
// counts as reading it in Gmail, the first unread one is a test: if Gmail then lists it as
// read, from then on only emails you open in the notch are fetched.
async function readWholeEmails(want, feeds, status) {
  const slots = new Map(feeds.map((feed) => [feed.account, feed.index]));
  const saved = await chrome.storage.local.get(['fullEmails', 'iks', 'wholeFetched']);
  let mode = saved.fullEmails || 'unknown';
  const iks = saved.iks || {};
  let fetched = saved.wholeFetched || 0;

  let queue = want.filter((item) => item && typeof item.id === 'string' && slots.has(item.account));
  if (mode === 'on-open') {
    queue = queue.filter((item) => item.opened);
  } else if (mode === 'unknown') {
    const test = queue.find((item) => item.unread);
    queue = queue.filter((item) => !item.unread).concat(test ? [test] : []);
  }

  let failuresInARow = 0;
  for (const item of queue.slice(0, EMAILS_PER_SYNC)) {
    status.trying = true;
    await chrome.storage.local.set({ status });

    const index = slots.get(item.account);
    const email = await readEmail(index, item, iks);
    await sendEmail({ account: item.account, id: item.id, ...email });
    console.info('[Notch Inbox Link] whole email', item.account, email.error || 'ok', `(mode ${mode})`);

    if (email.error) {
      status.emailError = email.error;
      failuresInARow += 1;
    } else {
      delete status.emailError;
      failuresInARow = 0;
      fetched += 1;
      if (mode === 'unknown' && item.unread) {
        const unread = await isStillUnread(index, item.id);
        if (unread === true) mode = 'ok';
        if (unread === false) mode = 'on-open';
      }
    }
    status.trying = false;
    status.fullEmails = mode;
    status.wholeFetched = fetched;
    await chrome.storage.local.set({ fullEmails: mode, iks, wholeFetched: fetched, status });
    if (failuresInARow >= 3) break; // Gmail isn't cooperating; try again next minute
  }
}

async function readEmail(index, item, iks) {
  const ids = NotchMime.messageIds(item.id, item.link);
  if (!ids) return { error: 'Unrecognised message ID.' };
  let raw = await showOriginal(index, ids, iks[item.account]);
  if (!raw) {
    const ik = await findIk(index, item.account);
    if (ik && ik !== iks[item.account]) {
      iks[item.account] = ik;
      raw = await showOriginal(index, ids, ik);
    }
  }
  if (!raw) return { error: 'Gmail didn’t show the whole email.' };
  try {
    return NotchMime.forApp(NotchMime.parse(raw));
  } catch (error) {
    return { error: 'Couldn’t decode the email.' };
  }
}

async function showOriginal(index, ids, ik) {
  const base = `${GMAIL}${index}/`;
  const pages = ik
    ? [`${base}?ik=${ik}&view=om&permmsgid=msg-f:${ids.decimal}`, `${base}?ui=2&ik=${ik}&view=om&th=${ids.hex}`]
    : [`${base}?view=om&permmsgid=msg-f:${ids.decimal}`];
  for (const url of pages) {
    const raw = NotchMime.rawFromShowOriginal(await getText(url));
    if (raw) return raw;
  }
  return null;
}

// Gmail's key for the account, read from the Gmail page. Not looked up more than every
// half hour per account, since the page is large.
async function findIk(index, account) {
  const saved = await chrome.storage.local.get('ikLookups');
  const lookups = saved.ikLookups || {};
  if (Date.now() - (lookups[account] || 0) < IK_RETRY_MS) return null;
  lookups[account] = Date.now();
  await chrome.storage.local.set({ ikLookups: lookups });
  return NotchMime.ikFromGmailPage(await getText(`${GMAIL}${index}/`));
}

// true / false, or null when the feeds can't be read just now.
async function isStillUnread(index, id) {
  const feeds = (await Promise.all([getFeed(index, PRIMARY_FEED), getFeed(index, INBOX_FEED)])).filter(Boolean);
  if (feeds.length === 0) return null;
  return feeds.some((xml) => xml.includes(id));
}

async function sendEmail(email) {
  try {
    await fetch(`${APP}/message`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(email),
    });
  } catch (error) {
    // Notch Inbox quit in the meantime; it asks again next time.
  }
}
