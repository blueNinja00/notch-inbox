// Notch Inbox Link
// Every minute (and within seconds when an open Gmail tab shows new or read mail), for each
// Gmail account signed in to this browser, using the browser's own sign-in:
//   1. read the unread-mail feeds: the Primary tab, plus the whole inbox so that Google
//      Classroom and other mail from Google that Gmail files under Updates isn't missed;
//   2. hand them to the Notch Inbox app on this Mac;
//   3. open the emails the app asks for (Gmail's "Show original"), decode them (mime.js)
//      and hand those over too, so the notch can show them in full;
//   4. mark read in Gmail the emails you read in the notch, out of sight: in an invisible
//      frame it adds to a Gmail tab you have open for about a minute (see "Marking read").
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
const RELOAD_GAP_MS = 10 * 60 * 1000;
const VERSION = chrome.runtime.getManifest().version;

chrome.runtime.onInstalled.addListener((details) => {
  // A new version gets a fresh go at emails still waiting to be marked read.
  if (details && details.reason === 'update') chrome.storage.local.remove(['hiddenTries', 'tabTries', 'inTabTries', 'noTabNoteAt']);
  start();
});
chrome.runtime.onStartup.addListener(start);

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === 'sync') sync();
  if (alarm.name === 'app') syncIfAppRestarted();
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message && message.type === 'sync-now') {
    sync().then(sendResponse);
    return true; // answers asynchronously
  }
  // The rest is hidden-frame.js, in the add-on's frame in your Gmail tab, and nobody else.
  if (!message || !sender || sender.id !== chrome.runtime.id) return false;
  if (message.type === 'hidden-frame') {
    // What it did, for the mark-read log.
    framesHeard = true;
    const where = Number.isInteger(message.index) ? `u/${message.index}` : 'u/?';
    trace(`frame ${where} (${Number(message.after) || 0}s): ${String(message.state).slice(0, 200)}`);
    if (message.done) {
      framesDone.add(where);
      if (framesWaiter) framesWaiter();
    }
  } else if (message.type === 'hidden-job') {
    // Which emails to mark read in its account.
    sendResponse({ hexes: (hiddenJob && hiddenJob[message.index]) || [] });
  } else if (message.type === 'hidden-wait') {
    // A pause: Chrome holds back the timers of a tab you're not looking at, but not the add-on's.
    setTimeout(() => sendResponse('waited'), Math.max(0, Math.min(Number(message.ms) || 0, 30000)));
    return true;
  }
  return false;
});

function start() {
  removeLeftoverFrames();
  chrome.alarms.create('sync', { periodInMinutes: 1 });
  // Every 30 seconds, a quick look at the app (nothing goes to Gmail): if it has just
  // started, after an update say, sync now rather than at the next minute.
  chrome.alarms.create('app', { periodInMinutes: 0.5 });
  sync();
}

async function syncIfAppRestarted() {
  const app = await appState();
  if (!app) return;
  const saved = await chrome.storage.local.get('appLaunch');
  // Just started (after an update, say), or waiting on something such as an email to mark read.
  if (saved.appLaunch !== app.launch || app.wants) sync();
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

// When the app is running: its launch ID (any value for older versions) and whether it's
// waiting on something. Null when it isn't running.
async function appState() {
  try {
    const response = await fetch(`${APP}/feeds`, { method: 'OPTIONS' });
    if (!response.ok) return null;
    const header = (name) => (response.headers && response.headers.get(name)) || null;
    return { launch: header('X-Notch-Launch') || 'running', wants: header('X-Notch-Wants') === '1' };
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
  const app = await appState();
  if (!app) {
    const status = { ok: false, message: 'Notch Inbox isn’t running on this Mac.', accounts: [], at: Date.now() };
    await chrome.storage.local.set({ status });
    retryForApp();
    return status;
  }
  appRetries = 0;
  await chrome.storage.local.set({ appLaunch: app.launch });

  const feeds = [];
  const seen = new Set();
  for (let index = 0; index < MAX_ACCOUNTS; index += 1) {
    const feed = await readAccount(index);
    if (!feed) continue; // nobody signed in at this slot
    if (feed.account && seen.has(feed.account)) break; // Gmail wrapped round to an account we already have
    if (feed.account) seen.add(feed.account);
    feeds.push(feed);
  }

  const saved = await chrome.storage.local.get(['fullEmails', 'reloadedAt', 'wholeFetched', 'readLog']);
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
        body: JSON.stringify({ feeds, version: VERSION, fullEmails, log: (saved.readLog || []).slice(-40) }),
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

  // The app put a different version of this add-on in the folder it's loaded from (an app
  // update brings one): reload to switch to it. At most every 10 minutes, so a reload that
  // somehow doesn't take can't turn into a loop.
  // Not in the middle of marking emails read, which would leave its frame behind.
  if (reply && typeof reply.addon === 'string' && reply.addon !== VERSION && !marking
      && Date.now() - (saved.reloadedAt || 0) > RELOAD_GAP_MS) {
    console.info('[Notch Inbox Link] reloading to switch from', VERSION, 'to', reply.addon);
    await chrome.storage.local.set({ reloadedAt: Date.now(), reloadedFor: reply.addon });
    chrome.runtime.reload();
    return status;
  }

  // Marking read can take a minute or so: it carries on alongside, so new mail keeps coming.
  if (reply && Array.isArray(reply.read) && reply.read.length > 0) {
    startMarkingRead(reply.read, feeds, reply.tabs === true);
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

// ---- Marking read ----------------------------------------------------------------------------

// Emails you read in the notch get marked read in Gmail, out of sight:
//   1. Gmail's own read action, sent quietly in the background. Gmail has had a few forms of
//      it over the years; the add-on checks the unread feed afterwards and moves on to the
//      next form if the email is still unread. Today's Gmail answers 404 (the action is gone),
//      so the add-on stops sending it at once, and tries again after a week.
//   2. If you have Gmail open in a tab (any account; a pinned tab is ideal), the add-on adds an
//      invisible frame to that tab: off the edge of the page, see-through and unclickable, so
//      the tab looks and works as before. Gmail in the frame shows its list of unread mail,
//      and hidden-frame.js ticks the emails and clicks Gmail's own "Mark as read" (any it can't
//      find there, it opens). It waits until Gmail in the frame has told Google; then the
//      add-on checks Gmail's unread list (for up to a minute) and takes the frame away. Three
//      tries per email.
//   3. Only if you turn it on in Notch Inbox (Settings → Gmail link), when there's no Gmail tab
//      or the frame didn't work: a background tab, closed straight after. Two tries per email.
// This runs alongside the syncs, since Gmail takes a while to start in the frame; one run at a time.
const ACTION_RETRY_MS = 7 * 24 * 60 * 60 * 1000;
const TRIES = 2;
const IN_TAB_TRIES = 3;
const IN_TAB_PER_RUN = 10;
const OPEN_PER_SYNC = 4;
const TAB_LOAD_MS = 30 * 1000;
const TAB_SETTLE_MS = 4000;
const FRAME_MS = 170 * 1000; // the frame's script gives itself two and a half minutes
const FRAME_SILENT_MS = 30 * 1000; // stop waiting if it hasn't said a word by then
const READ_CHECKS_MS = [2000, 3000, 5000, 10000, 20000, 20000]; // then Gmail's unread list, until it shows them read
const NO_TAB_NOTE_MS = 10 * 60 * 1000;
const NO_TAB_NOTE = 'no Gmail tab open (or Chrome has put yours to sleep): open Gmail in a tab, any account, '
  + 'and emails you read in the notch get marked read in it, out of sight';
const HIDDEN_NAME = 'notch-inbox-hidden';

// While the frame is in your Gmail tab: which emails (hex IDs) to mark read, by account slot;
// the accounts whose frame has finished; whether any frame has said a word; who's waiting.
let hiddenJob = null;
let framesDone = new Set();
let framesHeard = false;
let framesWaiter = null;
// The run of marking read in progress, if any.
let marking = null;

const MARK_READ_FORMS = [
  (ik, at, hex) => ({ query: `ui=2&ik=${ik}&at=${encodeURIComponent(at)}&view=up&act=rd&rt=j`, body: `t=${hex}` }),
  (ik, at, hex) => ({ query: `ui=2&ik=${ik}&at=${encodeURIComponent(at)}&act=rd&t=${hex}`, body: `at=${encodeURIComponent(at)}` }),
  (ik, at, hex) => ({ query: `ui=2&ik=${ik}&at=${encodeURIComponent(at)}&view=up&act=rd&rt=j&t=${hex}`, body: `t=${hex}&at=${encodeURIComponent(at)}` }),
];

function pause(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// A step-by-step log of marking read, for working out what Gmail does with each attempt. It
// holds times, account slots, the end of each email's ID, HTTP statuses and the start of
// Gmail's replies: never what an email says. The popup shows it; the app's Copy Debug Info
// includes it. Each line is saved as it happens, so the popup can follow along.
const LOG_LINES = 80;
let traceSaved = Promise.resolve();

function trace(text) {
  const line = `${new Date().toLocaleTimeString()} ${text}`;
  console.info('[Notch Inbox Link]', line);
  traceSaved = traceSaved.then(async () => {
    const saved = await chrome.storage.local.get('readLog');
    await chrome.storage.local.set({ readLog: (saved.readLog || []).concat([line]).slice(-LOG_LINES) });
  }).catch(() => {});
}

function idTail(id) {
  return `…${String(id).slice(-6)}`;
}

// The start of a reply, on one line.
function snippet(text, length = 120) {
  return JSON.stringify(String(text || '').slice(0, length));
}

// A URL with what's in its query left out: "mail.google.com/mail?account_id&message_id".
function shortURL(url) {
  try {
    const parsed = new URL(url);
    const keys = [...parsed.searchParams.keys()];
    return parsed.host + parsed.pathname + (keys.length ? `?${keys.join('&')}` : '');
  } catch (error) {
    return '(unreadable URL)';
  }
}

// Starts marking these emails read, unless a run is already going.
function startMarkingRead(items, feeds, allowTabs) {
  if (!marking) {
    const release = keepAwake();
    marking = markRead(items, feeds, allowTabs).finally(() => {
      release();
      marking = null;
    });
  }
  return marking;
}

async function markRead(items, feeds, allowTabs) {
  try {
    await markReadSteps(items, feeds, allowTabs);
  } catch (error) {
    trace(`stopped: ${error && error.message}`);
  } finally {
    await traceSaved;
  }
}

async function markReadSteps(items, feeds, allowTabs) {
  const slots = new Map(feeds.map((feed) => [feed.account, feed.index]));
  const saved = await chrome.storage.local.get(['iks', 'markReadForm', 'readAction', 'tabTries', 'inTabTries', 'noTabNoteAt']);
  const iks = saved.iks || {};
  const form = (saved.markReadForm || 0) % MARK_READ_FORMS.length;
  const action = saved.readAction || { state: 'unknown', misses: 0, at: 0 };
  const tabTries = saved.tabTries || {};
  const inTabTries = saved.inTabTries || {};

  let left = items.slice(0, 20)
    .filter((item) => item && typeof item.id === 'string' && slots.has(item.account))
    .map((item) => ({ item, index: slots.get(item.account), ids: NotchMime.messageIds(item.id, item.link) }))
    .filter((entry) => entry.ids);
  const asked = left.length;
  let worked = 0;
  let inTab = 0;
  let opened = 0;
  const how = [];

  // Forget emails the app isn't asking about any more.
  const wantedIDs = new Set(items.map((item) => item && item.id));
  for (const tries of [tabTries, inTabTries]) {
    for (const id of Object.keys(tries)) {
      if (!wantedIDs.has(id)) delete tries[id];
    }
  }
  const yourTab = await gmailTab();
  const noTabNote = async () => {
    if (yourTab || Date.now() - (saved.noTabNoteAt || 0) < NO_TAB_NOTE_MS) return;
    trace(NO_TAB_NOTE);
    await chrome.storage.local.set({ noTabNoteAt: Date.now() });
  };
  const outcome = (extra = {}) => ({
    asked, worked, inTab, opened, how: how.join('+'), action: action.state, noGmailTab: !yourTab, at: Date.now(), ...extra,
  });

  // Every way has had its tries for these emails (or there's no way to try): wait quietly
  // until the app stops asking.
  const actionOn = action.state !== 'off' || Date.now() - action.at > ACTION_RETRY_MS;
  const inTabLeft = Boolean(yourTab) && left.some((entry) => (inTabTries[entry.item.id] || 0) < IN_TAB_TRIES);
  const tabLeft = allowTabs && left.some((entry) => (tabTries[entry.item.id] || 0) < TRIES);
  if (!actionOn && !inTabLeft && !tabLeft) {
    if (asked > 0) await noTabNote();
    await chrome.storage.local.set({ markReadStatus: outcome({ triedEverything: true }), tabTries, inTabTries });
    return;
  }

  const where = yourTab ? `open, ${yourTab.front ? 'in view' : 'in the background'}` : 'none';
  trace(`asked to mark ${items.length} read; ${asked} usable: ${left.map((e) => `u/${e.index} ${idTail(e.item.id)}`).join(', ')}`
    + `; action ${action.state} (form ${form}), Gmail tab ${where}, background tabs ${allowTabs ? 'allowed' : 'off'}`);
  if (asked > 0) {
    const listed = await stillUnread(left);
    trace(`before: Gmail lists ${listed.size} of ${asked} as unread`);
    // Already read in Gmail (you read it there, say): nothing to do.
    worked += left.filter((entry) => !listed.has(entry.item.id)).length;
    left = left.filter((entry) => listed.has(entry.item.id));
  }

  // 1. Gmail's read action, unless it's known not to work here.
  if (left.length > 0 && actionOn) {
    const sent = [];
    let refused = 0;
    let gone = false;
    for (const entry of left) {
      const result = await markOneRead(entry, iks, form);
      if (result.ok) {
        sent.push(entry);
      } else {
        refused += 1;
        if (result.status === 404) gone = true;
      }
    }
    if (sent.length === 0 && refused > 0) {
      // Gmail turned it down: try the next form, and stop after all of them. A 404 means
      // Gmail doesn't have the action any more, so stop straight away.
      action.misses = gone ? MARK_READ_FORMS.length : (action.misses || 0) + 1;
      await chrome.storage.local.set({ markReadForm: form + 1 });
      if (action.misses >= MARK_READ_FORMS.length) action.state = 'off';
      action.at = Date.now();
      trace(gone ? "Gmail doesn't have this action any more (404); not sending it again for a week"
        : `the action was refused (${action.misses} of ${MARK_READ_FORMS.length} forms)${action.state === 'off' ? '; not sending it again for a week' : ''}`);
    }
    if (sent.length > 0) {
      await pause(1500);
      const still = await stillUnread(sent);
      const took = sent.filter((entry) => !still.has(entry.item.id));
      trace(`after the action: ${took.length} of ${sent.length} no longer unread`);
      worked += took.length;
      if (took.length > 0) {
        action.state = 'works';
        action.misses = 0;
        how.push('action');
      } else {
        action.misses = (action.misses || 0) + 1;
        await chrome.storage.local.set({ markReadForm: form + 1 }); // try the next form next time
        if (action.misses >= MARK_READ_FORMS.length) action.state = 'off';
      }
      action.at = Date.now();
      left = left.filter((entry) => !took.includes(entry));
    }
  }

  // 2. The invisible frame in a Gmail tab you have open.
  const forInTab = yourTab ? left.filter((entry) => (inTabTries[entry.item.id] || 0) < IN_TAB_TRIES).slice(0, IN_TAB_PER_RUN) : [];
  if (forInTab.length > 0) {
    const job = {};
    for (const entry of forInTab) {
      inTabTries[entry.item.id] = (inTabTries[entry.item.id] || 0) + 1;
      (job[entry.index] = job[entry.index] || []).push(entry.ids.hex);
    }
    await chrome.storage.local.set({ inTabTries });
    const result = await markInYourGmailTab(yourTab, job, forInTab);
    if (result.ran) {
      trace(`after the frame in your Gmail tab: ${result.took.length} of ${forInTab.length} no longer unread`);
      worked += result.took.length;
      inTab += result.took.length;
      if (result.took.length > 0) how.push('hidden');
      left = left.filter((entry) => !result.took.includes(entry));
    }
  } else if (left.length > 0) {
    await noTabNote();
  }

  // 3. A background tab, only if you've allowed it: when there's no Gmail tab, or the frame
  // in it has had its tries.
  if (allowTabs) {
    const forTab = left
      .filter((entry) => !forInTab.includes(entry) && (!yourTab || (inTabTries[entry.item.id] || 0) >= IN_TAB_TRIES))
      .filter((entry) => (tabTries[entry.item.id] || 0) < TRIES)
      .slice(0, OPEN_PER_SYNC);
    if (forTab.length > 0) {
      const pages = forTab.map((entry) => {
        const tries = tabTries[entry.item.id] || 0;
        tabTries[entry.item.id] = tries + 1;
        return gmailPageFor(entry, tries);
      });
      trace(`background tab: opening ${pages.length}`);
      opened = await openInGmail(pages);
      if (opened > 0) {
        await pause(2000);
        const still = await stillUnread(forTab);
        const took = forTab.filter((entry) => !still.has(entry.item.id)).length;
        trace(`after the tab: ${took} of ${forTab.length} no longer unread`);
        worked += took;
        if (took > 0) how.push('tab');
      }
    }
  }

  console.info('[Notch Inbox Link] mark read: asked', asked, 'worked', worked, 'in your tab', inTab, 'background tab', opened, 'action', action.state);
  // Account keys: whole emails may have found newer ones meanwhile, so theirs win.
  const latest = (await chrome.storage.local.get('iks')).iks || {};
  await chrome.storage.local.set({ iks: { ...iks, ...latest }, readAction: action, tabTries, inTabTries, markReadStatus: outcome() });
}

async function markOneRead(entry, iks, form) {
  const { index, item, ids } = entry;
  let ik = iks[item.account];
  if (!ik) {
    ik = await findIk(index, item.account);
    if (ik) iks[item.account] = ik;
  }
  const token = await gmailActionToken(index);
  const what = `action form ${form} u/${index} ${idTail(item.id)}: account key ${ik ? 'found' : 'missing'}, token ${token.from}`;
  if (!ik || !token.value) {
    trace(`${what}, not sent`);
    return { ok: false, status: 0 };
  }
  const request = MARK_READ_FORMS[form](ik, token.value, ids.hex);
  try {
    const response = await fetch(`${GMAIL}${index}/?${request.query}`, {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded;charset=utf-8' },
      body: request.body,
    });
    let reply = '';
    try {
      reply = await response.text();
    } catch (error) {
      // no body
    }
    const type = (response.headers && response.headers.get && response.headers.get('content-type')) || '?';
    trace(`${what}, HTTP ${response.status} ${type}, ${reply.length} bytes: ${snippet(reply)}`);
    return { ok: response.ok, status: response.status };
  } catch (error) {
    trace(`${what}, failed: ${error && error.message}`);
    return { ok: false, status: 0 };
  }
}

// The emails Gmail still lists as unread, by ID.
async function stillUnread(entries) {
  const still = new Set();
  for (const index of new Set(entries.map((entry) => entry.index))) {
    const listed = (await Promise.all([getFeed(index, PRIMARY_FEED), getFeed(index, INBOX_FEED)])).filter(Boolean);
    for (const entry of entries.filter((e) => e.index === index)) {
      // If the feeds can't be read just now, count it as still unread.
      if (listed.length === 0 || listed.some((xml) => xml.includes(entry.item.id))) still.add(entry.item.id);
    }
  }
  return still;
}

// Checks Gmail's unread list a few times over about a minute, until it no longer lists the
// emails. Returns the ones it no longer lists.
async function waitUntilRead(entries, patient = true) {
  let still = await stillUnread(entries);
  for (const ms of patient ? READ_CHECKS_MS : []) {
    if (still.size === 0) break;
    await pause(ms);
    still = await stillUnread(entries);
  }
  return entries.filter((entry) => !still.has(entry.item.id));
}

// Where to open an email in a background tab: first the link Gmail's own feed gives for it,
// then (the second time) its conversation in All Mail.
function gmailPageFor(entry, tries) {
  const link = String(entry.item.link || '').replace(/^http:\/\//, 'https://');
  if (tries === 0 && /^https:\/\/mail\.google\.com\/mail[/?]/.test(link)) return link;
  return `${GMAIL}${entry.index}/#all/${entry.ids.hex}`;
}

// A Gmail tab you have open (any account) to hold the frame: not one Chrome has put to sleep,
// and, given the choice, the one you're looking at, since Chrome holds back tabs you aren't.
// Returns { tab, front } or null.
async function gmailTab() {
  let tabs = [];
  try {
    tabs = await chrome.tabs.query({ url: 'https://mail.google.com/*' });
  } catch (error) {
    return null;
  }
  const awake = tabs.filter((tab) => !tab.discarded && !tab.frozen && tab.status !== 'unloaded'
    && /^https:\/\/mail\.google\.com\/mail\//.test(tab.url || ''));
  for (const tab of awake.filter((t) => t.active)) {
    try {
      const shownIn = await chrome.windows.get(tab.windowId);
      if (shownIn && shownIn.state !== 'minimized') return { tab, front: true };
    } catch (error) {
      // the window closed
    }
  }
  return awake.length > 0 ? { tab: awake[0], front: false } : null;
}

// Adds an invisible frame of Gmail's unread list (one per account) to your Gmail tab, waits for
// hidden-frame.js in each to mark the emails read, checks Gmail's unread list, then takes the
// frames away. The frames sit off the edge of the page, see-through and unclickable, so the tab
// looks and works as before. Returns whether they ran, and the emails no longer unread.
async function markInYourGmailTab(found, job, entries) {
  if (!chrome.scripting) return { ran: false, took: [] };
  const indexes = Object.keys(job);
  const pages = indexes.map((index) => `${GMAIL}${index}/#search/in%3Ainbox+is%3Aunread`);
  trace(`in your Gmail tab (${found.front ? 'in view' : 'in the background'}), out of sight: Gmail's unread list for ${indexes.map((i) => `u/${i}`).join(', ')}`);
  hiddenJob = job;
  framesDone = new Set();
  framesHeard = false;
  const started = Date.now();
  let ran = false;
  let took = [];
  try {
    await chrome.scripting.executeScript({ target: { tabId: found.tab.id }, func: removeHiddenFrames, args: [HIDDEN_NAME] });
    for (const page of pages) {
      await chrome.scripting.executeScript({ target: { tabId: found.tab.id }, func: addHiddenFrame, args: [page, HIDDEN_NAME] });
    }
    ran = true;
    const ending = await waitForFrames(pages.length);
    const why = {
      done: '',
      silent: ": the add-on's script in the frame didn't say a word (Chrome may not have run it)",
      timeout: ' (stopped waiting)',
    }[ending];
    trace(`in your Gmail tab: ${framesDone.size} of ${pages.length} frames finished after ${Math.round((Date.now() - started) / 1000)}s${why}`);
    // Gmail can take a few seconds to tell Google: check its unread list before the frame goes.
    took = await waitUntilRead(entries, ending !== 'silent');
  } catch (error) {
    trace(`in your Gmail tab: couldn't add the frame: ${error && error.message}`);
  } finally {
    hiddenJob = null;
    framesWaiter = null;
    try {
      await chrome.scripting.executeScript({ target: { tabId: found.tab.id }, func: removeHiddenFrames, args: [HIDDEN_NAME] });
    } catch (error) {
      // the tab closed
    }
  }
  return { ran, took };
}

// Runs in your Gmail tab: the invisible frame.
function addHiddenFrame(src, name) {
  const frame = document.createElement('iframe');
  frame.name = name;
  frame.src = src;
  frame.tabIndex = -1;
  frame.inert = true; // nothing in it can be clicked, tabbed to or take the keyboard
  frame.setAttribute('aria-hidden', 'true');
  frame.style.cssText = 'position: fixed; left: -12000px; top: 0; width: 1280px; height: 800px; '
    + 'opacity: 0; pointer-events: none; border: 0;';
  document.documentElement.appendChild(frame);
}

// Runs in your Gmail tab: takes the invisible frames away.
function removeHiddenFrames(name) {
  document.querySelectorAll(`iframe[name="${name}"]`).forEach((frame) => frame.remove());
}

// Frames a run cut short left behind (the add-on was updated in the middle of one, say).
async function removeLeftoverFrames() {
  if (!chrome.scripting) return;
  try {
    const tabs = await chrome.tabs.query({ url: 'https://mail.google.com/*' });
    for (const tab of tabs.filter((t) => !t.discarded)) {
      chrome.scripting.executeScript({ target: { tabId: tab.id }, func: removeHiddenFrames, args: [HIDDEN_NAME] }).catch(() => {});
    }
  } catch (error) {
    // no tabs to look at
  }
}

// Resolves 'done' once `count` frames have finished, 'silent' if none has said a word after
// 30 seconds, or 'timeout' after 170.
function waitForFrames(count) {
  return new Promise((resolve) => {
    let settled = false;
    const finish = (ending) => {
      if (settled) return;
      settled = true;
      clearTimeout(quiet);
      clearTimeout(limit);
      framesWaiter = null;
      resolve(ending);
    };
    const quiet = setTimeout(() => {
      if (!framesHeard) finish('silent');
    }, FRAME_SILENT_MS);
    const limit = setTimeout(() => finish('timeout'), FRAME_MS);
    framesWaiter = () => {
      if (framesDone.size >= count) finish('done');
    };
    framesWaiter();
  });
}

// Only if you've allowed it: opens each page in one background tab (it doesn't take you away
// from what you're doing), gives Gmail a few seconds, then closes the tab. Returns how many opened.
async function openInGmail(pages) {
  let tab = null;
  let opened = 0;
  try {
    for (const page of pages) {
      if (!tab) {
        const loaded = waitForTab(() => tab && tab.id);
        tab = await chrome.tabs.create({ url: page, active: false });
        if (!(await loaded)) break;
      } else if (sameDocument(tab.pendingUrl || tab.url, page)) {
        await chrome.tabs.update(tab.id, { url: page }); // Gmail switches emails without reloading
      } else {
        const loaded = waitForTab(() => tab.id);
        await chrome.tabs.update(tab.id, { url: page });
        if (!(await loaded)) break;
      }
      tab.url = page;
      opened += 1;
      await pause(TAB_SETTLE_MS);
    }
  } catch (error) {
    console.info('[Notch Inbox Link] couldn’t open Gmail in a tab:', error && error.message);
  } finally {
    if (tab && tab.id !== undefined) {
      try {
        await chrome.tabs.remove(tab.id);
      } catch (error) {
        // already closed
      }
    }
  }
  return opened;
}

function sameDocument(a, b) {
  const base = (url) => String(url || '').split('#')[0];
  return Boolean(a) && base(a) === base(b) && String(b).includes('#');
}

// Resolves true once the tab has finished loading, or false after 30 seconds.
function waitForTab(tabID) {
  return new Promise((resolve) => {
    let finished = false;
    const finish = (loaded) => {
      if (finished) return;
      finished = true;
      chrome.tabs.onUpdated.removeListener(listener);
      clearTimeout(timer);
      resolve(loaded);
    };
    const listener = (id, change) => {
      if (id === tabID() && change.status === 'complete') finish(true);
    };
    chrome.tabs.onUpdated.addListener(listener);
    const timer = setTimeout(() => finish(false), TAB_LOAD_MS);
  });
}

// Gmail's action token for an account: its GMAIL_AT cookie, or failing that, from its page.
// Says where it came from, for the log.
async function gmailActionToken(index) {
  try {
    const cookie = await chrome.cookies.get({ url: `${GMAIL}${index}/`, name: 'GMAIL_AT' });
    if (cookie && cookie.value) return { value: cookie.value, from: 'GMAIL_AT cookie' };
  } catch (error) {
    // cookies not available: fall back to the page
  }
  const page = await getText(`${GMAIL}${index}/`);
  const match = page && (/GM_ACTION_TOKEN\s*=\s*"([^"]+)"/.exec(page) || /[?&;]at=([A-Za-z0-9_-]{10,})/.exec(page));
  return match ? { value: match[1], from: 'Gmail page' } : { value: null, from: 'missing (no GMAIL_AT cookie, none on the page)' };
}
