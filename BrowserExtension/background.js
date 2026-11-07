// Notch Inbox Link
// Every minute: read the unread-mail feed (Primary tab) of each Gmail account
// signed in to this browser, using the browser's own sign-in, and hand the feeds
// to the Notch Inbox app on this Mac. It only talks to mail.google.com and 127.0.0.1.

const APP_URL = 'http://127.0.0.1:47823/feeds';
const MAX_ACCOUNTS = 6;
const PRIMARY_FEED = 'feed/atom/%5Esq_ig_i_personal';
const INBOX_FEED = 'feed/atom';

chrome.runtime.onInstalled.addListener(start);
chrome.runtime.onStartup.addListener(start);

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === 'sync') sync();
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
  sync();
}

// The feed's own <title> ends with the signed-in address.
function accountIn(xml) {
  const title = xml.match(/<title>([^<]*)<\/title>/);
  const address = title && title[1].match(/[^\s<>]+@[^\s<>]+/);
  return address ? address[0].toLowerCase() : null;
}

async function getFeed(index, path) {
  const response = await fetch(`https://mail.google.com/mail/u/${index}/${path}`, {
    credentials: 'include',
    cache: 'no-store',
  });
  if (!response.ok) return null;
  const xml = await response.text();
  return xml.includes('<feed') ? xml : null;
}

async function readAccount(index) {
  try {
    const xml = (await getFeed(index, PRIMARY_FEED)) || (await getFeed(index, INBOX_FEED));
    return xml ? { index, account: accountIn(xml), xml } : null;
  } catch (error) {
    return null;
  }
}

async function sync() {
  const feeds = [];
  const seen = new Set();
  for (let index = 0; index < MAX_ACCOUNTS; index += 1) {
    const feed = await readAccount(index);
    if (!feed) continue; // nobody signed in at this slot
    if (feed.account && seen.has(feed.account)) break; // Gmail wrapped round to an account we already have
    if (feed.account) seen.add(feed.account);
    feeds.push(feed);
  }

  let status;
  if (feeds.length === 0) {
    status = { ok: false, message: 'No signed-in Gmail accounts found in this browser.' };
  } else {
    try {
      const response = await fetch(APP_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ feeds }),
      });
      status = response.ok
        ? { ok: true, message: 'Linked to Notch Inbox.' }
        : { ok: false, message: `Notch Inbox turned the update away (${response.status}).` };
    } catch (error) {
      status = { ok: false, message: 'Notch Inbox isn’t running on this Mac.' };
    }
  }
  status.accounts = feeds.map((feed) => feed.account).filter(Boolean);
  status.at = Date.now();
  await chrome.storage.local.set({ status });
  return status;
}
