// Notch Inbox Link: runs in Gmail pages, but does nothing unless the page is one of the
// add-on's hidden Gmail frames (named "notch-inbox-hidden": inside one of your Gmail tabs,
// or on the add-on's out-of-sight page). There it:
//   - tells the add-on what Gmail is showing, for the mark-read log: a mail list or an email,
//     which part of Gmail (#inbox, #all…), whether the page counts as visible, and whether
//     Gmail offers "Mark as unread" (it does once it counts the email read);
//   - marks the add-on's emails read the way you would: in a list, it ticks each one and
//     clicks Gmail's own "Mark as read"; on an open email that Gmail hasn't counted as read,
//     it clicks "Mark as read" if Gmail offers it.
// It never sends what an email says.
(() => {
  const NAME = 'notch-inbox-hidden'; // the name the add-on gives its hidden frames
  const ancestors = location.ancestorOrigins ? Array.from(location.ancestorOrigins) : [];
  if (window.top === window) return;
  if (window.name !== NAME && ancestors[0] !== `chrome-extension://${chrome.runtime.id}`) return;

  // Tell the page holding the frame that this script is running (for the log).
  try {
    window.parent.postMessage({ notchInboxHidden: 'running' }, '*');
  } catch (error) {
    // no parent to tell
  }

  const started = Date.now();
  const seconds = () => Math.round((Date.now() - started) / 1000);
  // `done`: the last word on this frame's job, so the add-on can stop waiting.
  const say = (state, done = false) => {
    chrome.runtime.sendMessage({ type: 'hidden-frame', state, after: seconds(), done }).catch(() => {});
  };
  const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  const button = (label) => document.querySelector(
    `[role="button"][data-tooltip="${label}"], [role="button"][aria-label="${label}"], [data-tooltip="${label}"]`);

  // A click the way Gmail listens for one.
  const press = (element) => {
    for (const type of ['mousedown', 'mouseup', 'click']) {
      element.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, view: window }));
    }
  };

  // What Gmail shows, on one line, whenever it changes.
  let last = '';
  const describe = () => {
    const title = document.title || '';
    let shows = 'nothing yet';
    if (document.querySelector('h2.hP')) shows = 'an email';
    else if (document.querySelector('tr.zA')) shows = 'a mail list';
    else if (/^(Inbox|Primary|All Mail|Search results)\b/i.test(title)) shows = 'a mail list (loading)';
    else if (title) shows = 'something else';
    const part = location.hash ? `${location.hash.split('/')[0]}${location.hash.includes('/') ? '/…' : ''}` : 'no #';
    const read = button('Mark as unread') ? 'Gmail offers "Mark as unread" (counts it read)' : 'no "Mark as unread"';
    const state = `showing ${shows}, ${part}, page ${document.visibilityState}, ${read}`;
    if (state !== last) {
      last = state;
      say(state);
    }
    if (Date.now() - started < 25000) setTimeout(describe, 1000);
  };
  setTimeout(describe, 300);

  const slot = (/\/mail\/u\/(\d+)\//.exec(location.pathname) || [])[1];
  if (slot === undefined) return;

  // Which emails to mark read in this account, from the add-on.
  chrome.runtime.sendMessage({ type: 'hidden-job', index: Number(slot) }).then(async (reply) => {
    const hexes = ((reply && reply.hexes) || []).filter((hex) => /^[0-9a-f]+$/.test(hex));
    if (hexes.length === 0) {
      say('nothing to mark in this account', true);
      return;
    }
    const opening = /^#[^/]+\/[0-9a-zA-Z]+/.test(location.hash);
    if (opening) {
      await onEmail();
    } else {
      await inList(hexes);
    }
  }).catch(() => {});

  // An open email: if Gmail still hasn't counted it read after a few seconds, and offers
  // "Mark as read", click it.
  async function onEmail() {
    for (let second = 0; second < 8; second += 1) {
      await wait(1000);
      if (button('Mark as unread')) {
        say('Gmail counted the open email read', true);
        return;
      }
    }
    const markRead = button('Mark as read');
    if (markRead) {
      press(markRead);
      say('clicked "Mark as read" on the open email', true);
    } else {
      say('the open email had no "Mark as read" to click', true);
    }
  }

  // A mail list: find each email's row, tick it, then click "Mark as read".
  async function inList(hexes) {
    const rowFor = (hex) => {
      const marker = document.querySelector(`[data-legacy-thread-id="${hex}"], [data-legacy-last-message-id="${hex}"]`);
      return marker ? marker.closest('tr') : null;
    };
    let rows = [];
    for (let tries = 0; tries < 24; tries += 1) { // up to 12 seconds for the list
      rows = hexes.map(rowFor).filter(Boolean);
      if (rows.length === hexes.length || (rows.length > 0 && tries > 8)) break;
      if (document.querySelector('tr.zA') && tries > 12) break;
      await wait(500);
    }
    say(`found ${rows.length} of ${hexes.length} in the list`, rows.length === 0);
    if (rows.length === 0) return;
    for (const row of rows) {
      const box = row.querySelector('[role="checkbox"]');
      if (box && box.getAttribute('aria-checked') !== 'true') press(box);
    }
    await wait(800);
    const markRead = button('Mark as read');
    if (!markRead) {
      say('no "Mark as read" button after ticking them', true);
      return;
    }
    press(markRead);
    await wait(1500);
    const stillBold = rows.filter((row) => row.classList.contains('zE')).length;
    say(`clicked "Mark as read"; ${stillBold} still bold in the list`, true);
  }
})();
