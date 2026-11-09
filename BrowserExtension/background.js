// Notch Inbox Link
// Every minute (and within seconds when an open Gmail tab shows new or read mail), for each
// Gmail account signed in to this browser, using the browser's own sign-in:
//   1. read the unread-mail feeds: the Primary tab, plus the whole inbox so that Google
//      Classroom and other mail from Google that Gmail files under Updates isn't missed;
//   2. hand them to the Notch Inbox app on this Mac;
//   3. open the emails the app asks for (Gmail's "Show original"), decode them (mime.js)
//      and hand those over too, so the notch can show them in full;
//   4. mark read in Gmail the emails you read in the notch, out of sight (Gmail's read
//      action, or opening them in a hidden Gmail frame for a few seconds).
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

chrome.runtime.onInstalled.addListener(start);
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
  // What the hidden Gmail frame shows, from hidden-frame.js, for the mark-read log.
  if (message && message.type === 'hidden-frame' && sender && sender.id === chrome.runtime.id) {
    trace(`inside the hidden Gmail (${message.after}s): ${String(message.state).slice(0, 200)}`);
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
  if (reply && typeof reply.addon === 'string' && reply.addon !== VERSION
      && Date.now() - (saved.reloadedAt || 0) > RELOAD_GAP_MS) {
    console.info('[Notch Inbox Link] reloading to switch from', VERSION, 'to', reply.addon);
    await chrome.storage.local.set({ reloadedAt: Date.now(), reloadedFor: reply.addon });
    chrome.runtime.reload();
    return status;
  }

  if (reply && Array.isArray(reply.read) && reply.read.length > 0) {
    await markRead(reply.read, feeds, status, reply.tabs === true);
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

// Emails you read in the notch get marked read in Gmail, all out of sight:
//   1. Gmail's own read action, sent quietly in the background. Gmail has had a few forms of
//      it over the years; the add-on checks the unread feed afterwards and moves on to the
//      next form if the email is still unread. If none of them work, it stops sending them
//      (trying again after a week).
//   2. Otherwise it opens the emails in Gmail in a hidden frame on a page Chrome keeps out of
//      sight (offscreen.html), a few seconds each, as if you'd clicked them. No tab opens.
//      Gmail normally refuses to load inside another page; for that hidden frame alone, and
//      only while it's open, its "don't show me in a frame" headers are set aside. (You
//      approved this. Gmail in your tabs is untouched.)
//   3. Only if you turn it on in Notch Inbox (Settings → Gmail link), and the hidden frame
//      didn't work either: a background tab, closed straight after.
// Each email gets two tries each way.
const ACTION_RETRY_MS = 7 * 24 * 60 * 60 * 1000;
const TRIES = 2;
const OPEN_PER_SYNC = 4;
const TAB_LOAD_MS = 30 * 1000;
const TAB_SETTLE_MS = 4000;
const HIDDEN_SETTLE_MS = 9000; // Gmail starts more slowly out of sight
const HIDDEN_RULE = 47823;

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
// includes it.
const LOG_LINES = 80;
let traceLines = null;

function trace(text) {
  const line = `${new Date().toLocaleTimeString()} ${text}`;
  console.info('[Notch Inbox Link]', line);
  if (traceLines) traceLines.push(line);
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

async function saveTrace() {
  if (!traceLines || traceLines.length === 0) return;
  const saved = await chrome.storage.local.get('readLog');
  await chrome.storage.local.set({ readLog: (saved.readLog || []).concat(traceLines).slice(-LOG_LINES) });
}

async function markRead(items, feeds, status, allowTabs) {
  traceLines = [];
  try {
    await markReadSteps(items, feeds, status, allowTabs);
  } catch (error) {
    trace(`stopped: ${error && error.message}`);
  } finally {
    await saveTrace();
    traceLines = null;
  }
}

async function markReadSteps(items, feeds, status, allowTabs) {
  const slots = new Map(feeds.map((feed) => [feed.account, feed.index]));
  const saved = await chrome.storage.local.get(['iks', 'markReadForm', 'readAction', 'hiddenTries', 'tabTries']);
  const iks = saved.iks || {};
  const form = (saved.markReadForm || 0) % MARK_READ_FORMS.length;
  const action = saved.readAction || { state: 'unknown', misses: 0, at: 0 };
  const hiddenTries = saved.hiddenTries || {};
  const tabTries = saved.tabTries || {};

  let left = items.slice(0, 20)
    .filter((item) => item && typeof item.id === 'string' && slots.has(item.account))
    .map((item) => ({ item, index: slots.get(item.account), ids: NotchMime.messageIds(item.id, item.link) }))
    .filter((entry) => entry.ids);
  const asked = left.length;
  let worked = 0;
  const how = [];
  trace(`asked to mark ${items.length} read; ${asked} usable: ${left.map((e) => `u/${e.index} ${idTail(e.item.id)}`).join(', ')}`
    + `; action ${action.state} (form ${form}), tabs ${allowTabs ? 'allowed' : 'off'}`);
  if (asked > 0) {
    const listed = await stillUnread(left);
    trace(`before: Gmail lists ${listed.size} of ${asked} as unread`);
  }

  // Forget emails the app isn't asking about any more.
  const ids = new Set(items.map((item) => item && item.id));
  for (const tries of [hiddenTries, tabTries]) {
    for (const id of Object.keys(tries)) {
      if (!ids.has(id)) delete tries[id];
    }
  }

  // 1. Gmail's read action, unless it's known not to work here.
  if (left.length > 0 && (action.state !== 'off' || Date.now() - action.at > ACTION_RETRY_MS)) {
    const sent = [];
    let refused = 0;
    for (const entry of left) {
      if (await markOneRead(entry, iks, form)) sent.push(entry);
      else refused += 1;
    }
    if (sent.length === 0 && refused > 0) {
      // Gmail turned it down (it answers 404 now): try the next form, and stop after all of them.
      action.misses = (action.misses || 0) + 1;
      await chrome.storage.local.set({ markReadForm: form + 1 });
      if (action.misses >= MARK_READ_FORMS.length) action.state = 'off';
      action.at = Date.now();
      trace(`the action was refused (${action.misses} of ${MARK_READ_FORMS.length} forms)${action.state === 'off' ? '; not sending it again for a week' : ''}`);
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

  // 2. Gmail in a hidden frame, out of sight. (hidden-frame-main.js tells Gmail in that
  // frame that it's in view; hidden-frame.js reports what it shows, for the log.)
  let hidden = 0;
  const forHidden = left.filter((entry) => (hiddenTries[entry.item.id] || 0) < TRIES).slice(0, OPEN_PER_SYNC);
  if (forHidden.length > 0) {
    const pages = forHidden.map((entry) => {
      const tries = hiddenTries[entry.item.id] || 0;
      hiddenTries[entry.item.id] = tries + 1;
      return gmailPageFor(entry, tries);
    });
    hidden = await openOutOfSight(pages);
    if (hidden > 0) {
      await pause(2000);
      const still = await stillUnread(forHidden);
      const took = forHidden.filter((entry) => !still.has(entry.item.id));
      trace(`after the hidden Gmail: ${took.length} of ${forHidden.length} no longer unread`);
      worked += took.length;
      if (took.length > 0) how.push('hidden');
      left = left.filter((entry) => !took.includes(entry));
    }
  }

  // 3. A background tab, only if you've allowed it, once the hidden frame has had its tries.
  let opened = 0;
  if (allowTabs) {
    const forTab = left
      .filter((entry) => (hiddenTries[entry.item.id] || 0) >= TRIES && !forHidden.includes(entry))
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

  console.info('[Notch Inbox Link] mark read: asked', asked, 'worked', worked, 'hidden', hidden, 'tab', opened, 'action', action.state);
  status.markRead = { asked, worked, hidden, opened, how: how.join('+'), action: action.state, at: Date.now() };
  await chrome.storage.local.set({ iks, status, readAction: action, hiddenTries, tabTries });
}

// Opens each page in Gmail in a hidden frame on the out-of-sight page, then closes that page.
// Returns how many opened.
async function openOutOfSight(pages) {
  if (!chrome.offscreen || !chrome.declarativeNetRequest) return 0;
  let opened = 0;
  try {
    // Only frames of mail.google.com that aren't in any tab (tab ID -1: the out-of-sight
    // page), and only until this finishes.
    await chrome.declarativeNetRequest.updateSessionRules({
      removeRuleIds: [HIDDEN_RULE],
      addRules: [{
        id: HIDDEN_RULE,
        priority: 1,
        action: {
          type: 'modifyHeaders',
          responseHeaders: [
            { header: 'x-frame-options', operation: 'remove' },
            { header: 'content-security-policy', operation: 'remove' },
          ],
        },
        condition: { requestDomains: ['mail.google.com'], resourceTypes: ['sub_frame'], tabIds: [-1] },
      }],
    });
    try {
      await chrome.offscreen.createDocument({
        url: 'offscreen.html',
        reasons: ['IFRAME_SCRIPTING'],
        justification: 'Opens emails you read in Notch Inbox in Gmail, out of sight, so Gmail marks them read.',
      });
    } catch (error) {
      // Already open from a sync that was cut short: use it.
    }
    const seen = [];
    const stopWatching = watchHiddenFrame(seen);
    trace(`hidden Gmail: opening ${pages.map(shortURL).join(', ')}`);
    let reply;
    try {
      reply = await chrome.runtime.sendMessage({
        target: 'offscreen', type: 'open-gmail', pages, settle: HIDDEN_SETTLE_MS, loadTimeout: TAB_LOAD_MS,
      });
    } finally {
      stopWatching();
    }
    opened = (reply && reply.opened) || 0;
    trace(`hidden Gmail: ${opened} of ${pages.length} loaded`);
    for (const line of seen.slice(0, 16)) trace(`hidden Gmail: ${line}`);
    if (seen.length === 0) trace('hidden Gmail: no requests seen');
  } catch (error) {
    console.info('[Notch Inbox Link] couldn’t open Gmail out of sight:', error && error.message);
  } finally {
    try {
      await chrome.offscreen.closeDocument();
    } catch (error) {
      // not open
    }
    try {
      await chrome.declarativeNetRequest.updateSessionRules({ removeRuleIds: [HIDDEN_RULE] });
    } catch (error) {
      // nothing to remove
    }
  }
  return opened;
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
    return false;
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
    return response.ok;
  } catch (error) {
    trace(`${what}, failed: ${error && error.message}`);
    return false;
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

// Where to open an email in Gmail: first the link Gmail's own feed gives for it, then (the
// second time) its conversation in All Mail.
function gmailPageFor(entry, tries) {
  const link = String(entry.item.link || '').replace(/^http:\/\//, 'https://');
  if (tries === 0 && /^https:\/\/mail\.google\.com\/mail[/?]/.test(link)) return link;
  return `${GMAIL}${entry.index}/#all/${entry.ids.hex}`;
}

// What happens to the hidden frame's own requests: statuses, redirects (to a sign-in page,
// say) and errors. Just the frame's pages on mail.google.com, not tabs.
function watchHiddenFrame(out) {
  if (!chrome.webRequest) {
    out.push('(can’t watch requests)');
    return () => {};
  }
  const filter = { urls: ['https://mail.google.com/*'], types: ['sub_frame'], tabId: -1 };
  const onHeaders = (details) => {
    const names = (details.responseHeaders || []).map((header) => header.name.toLowerCase());
    const blocks = ['x-frame-options', 'content-security-policy'].filter((name) => names.includes(name));
    out.push(`${shortURL(details.url)} → ${details.statusCode}${blocks.length ? ` (Gmail sent ${blocks.join(' and ')}, set aside)` : ''}`);
  };
  const onRedirect = (details) => out.push(`${shortURL(details.url)} → sent on to ${shortURL(details.redirectUrl)}`);
  const onError = (details) => out.push(`${shortURL(details.url)} → error ${details.error}`);
  chrome.webRequest.onHeadersReceived.addListener(onHeaders, filter, ['responseHeaders']);
  chrome.webRequest.onBeforeRedirect.addListener(onRedirect, filter);
  chrome.webRequest.onErrorOccurred.addListener(onError, filter);
  return () => {
    chrome.webRequest.onHeadersReceived.removeListener(onHeaders);
    chrome.webRequest.onBeforeRedirect.removeListener(onRedirect);
    chrome.webRequest.onErrorOccurred.removeListener(onError);
  };
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
