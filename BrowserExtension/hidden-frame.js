// Notch Inbox Link: runs in Gmail pages, but does nothing unless the page is the add-on's
// invisible frame (named "notch-inbox-hidden"). The add-on puts that frame in a Gmail tab you
// have open, off the edge of the page, for about a minute, to mark emails you read in the
// notch read in Gmail. In it, this script does what you would:
//   1. in Gmail's list of unread mail, it ticks each email and clicks Gmail's own "Mark as read";
//   2. any it can't find there, it opens, as if you'd clicked it.
// Chrome can hold back the timers of a tab you're not looking at for up to a minute, so it
// moves on as soon as Gmail draws something (it watches the page for changes), and when it has
// to pause, the add-on times the pause. After marking, it waits until Gmail has told Google
// (hidden-frame-main.js notes what Gmail sends), so the frame isn't taken away first.
// It tells the add-on what it did, for the mark-read log: counts and steps, never what an
// email says.
(() => {
  const NAME = 'notch-inbox-hidden'; // the name the add-on gives its frame
  if (window.top === window || window.name !== NAME) return;

  const JOB_MS = 150 * 1000; // for the whole job
  const START_MS = 35 * 1000; // for Gmail to start and show its list
  const TELL_MS = 90 * 1000; // for Gmail to tell Google, after marking
  const GONE_MS = 4 * 60 * 1000; // after this the frame takes itself away, if the add-on hasn't
  const started = Date.now();
  const timeLeft = () => Math.max(0, started + JOB_MS - Date.now());
  const seconds = () => Math.round((Date.now() - started) / 1000);
  const slot = (/^\/mail\/u\/(\d+)\//.exec(location.pathname) || [])[1];
  const index = slot === undefined ? null : Number(slot);

  // A message to the add-on (it fails if the add-on was reloaded meanwhile).
  const send = (message) => {
    try {
      return Promise.resolve(chrome.runtime.sendMessage(message));
    } catch (error) {
      return Promise.reject(error);
    }
  };
  // What's happening, for the log. `done`: the last word, so the add-on can stop waiting.
  let finished = false;
  const say = (state, done = false) => {
    if (finished) return;
    if (done) finished = true;
    send({ type: 'hidden-frame', index, state: String(state).slice(0, 200), after: seconds(), done }).catch(() => {});
  };
  const timer = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  // A pause timed by the add-on, which Chrome doesn't hold back (in steps of up to 25 seconds).
  const sleep = async (ms) => {
    let left = Math.max(0, Math.min(ms, timeLeft()));
    while (left > 0) {
      const part = Math.min(left, 25000);
      const reply = await send({ type: 'hidden-wait', ms: part }).catch(() => null);
      if (reply !== 'waited') await timer(part);
      left -= part;
    }
  };

  // What Gmail has sent Google from this frame (from hidden-frame-main.js): where each request
  // went, how it ended, and whether it named an email being marked read.
  const sentToGoogle = [];
  let heardFromGmail = null;
  document.addEventListener('notch-inbox-net', (event) => {
    let entry = null;
    try {
      entry = JSON.parse(event.detail);
    } catch (error) {
      return;
    }
    if (!entry || entry.phase !== 'done') return;
    sentToGoogle.push(entry);
    if (heardFromGmail) heardFromGmail();
  });
  // The IDs Gmail may use for an email: the message's (hex, and as a number) and its conversation's.
  const idsFor = (hex, row) => {
    const ids = [hex];
    try {
      ids.push(BigInt(`0x${hex}`).toString());
    } catch (error) {
      // not a number after all
    }
    const thread = row && row.querySelector('[data-thread-id]');
    const number = thread && (/(\d{6,25})/.exec(thread.getAttribute('data-thread-id') || '') || [])[1];
    if (number) ids.push(number);
    const legacy = row && row.querySelector('[data-legacy-thread-id]');
    if (legacy && legacy.getAttribute('data-legacy-thread-id')) ids.push(legacy.getAttribute('data-legacy-thread-id'));
    return Array.from(new Set(ids));
  };
  const watch = (ids) => {
    document.dispatchEvent(new CustomEvent('notch-inbox-watch', { detail: JSON.stringify(ids) }));
  };
  // Waits until Gmail has sent Google a request naming the emails, since `since`. Returns what
  // happened, for the log.
  const toldGoogle = (since, ms) => new Promise((resolve) => {
    let finished = false;
    const told = () => sentToGoogle.find((entry) => entry.at >= since - 50 && entry.mentions === true);
    const finish = () => {
      if (finished) return;
      finished = true;
      heardFromGmail = null;
      const found = told();
      if (found) {
        resolve(`Gmail told Google: ${found.method} ${found.path} → ${found.status}, ${((found.at - since) / 1000).toFixed(1)}s after`);
        return;
      }
      const counts = new Map();
      for (const entry of sentToGoogle.filter((e) => e.at >= since - 50 && e.method !== 'GET')) {
        const key = `${entry.method} ${entry.path} → ${entry.status}`;
        counts.set(key, (counts.get(key) || 0) + 1);
      }
      const others = Array.from(counts).slice(0, 3).map(([key, count]) => (count > 1 ? `${key} ×${count}` : key)).join(', ');
      resolve(`Gmail hadn't told Google after ${Math.round((Date.now() - since) / 1000)}s; since then it sent ${others || 'nothing'}`);
    };
    heardFromGmail = () => {
      if (told()) finish();
    };
    heardFromGmail();
    sleep(ms).then(finish);
  });

  // Whether Gmail is showing an element: it keeps views it showed before in the page, out of view.
  const shown = (element) => Boolean(element) && element.isConnected && element.getClientRects().length > 0
    && getComputedStyle(element).visibility !== 'hidden';

  // Resolves with what `check` finds as soon as Gmail draws it, or null after `ms`.
  const waitFor = (check, ms) => new Promise((resolve) => {
    let done = false;
    let lastLook = 0;
    let lookSoon = false;
    let observer = null;
    const finish = (value) => {
      if (done) return;
      done = true;
      if (observer) observer.disconnect();
      window.removeEventListener('hashchange', look);
      resolve(value);
    };
    function look() {
      if (done) return;
      // At most every 150 ms: Gmail changes the page a lot while it starts.
      if (Date.now() - lastLook < 150) {
        if (!lookSoon) {
          lookSoon = true;
          sleep(150).then(() => {
            lookSoon = false;
            look();
          });
        }
        return;
      }
      lastLook = Date.now();
      let value = null;
      try {
        value = check();
      } catch (error) {
        value = null;
      }
      if (value) finish(value);
    }
    look();
    if (done) return;
    observer = new MutationObserver(look);
    observer.observe(document, {
      subtree: true, childList: true, attributes: true, attributeFilter: ['class', 'style', 'aria-checked', 'hidden'],
    });
    window.addEventListener('hashchange', look);
    sleep(ms).then(() => {
      lastLook = 0;
      look();
      finish(null);
    });
  });

  // A click the way Gmail listens for one.
  const fire = (element, types) => {
    const box = element.getBoundingClientRect();
    const at = { clientX: box.left + box.width / 2, clientY: box.top + box.height / 2 };
    for (const type of types) {
      element.dispatchEvent(new MouseEvent(type, {
        bubbles: true, cancelable: true, view: window, button: 0, buttons: type === 'mousedown' ? 1 : 0, ...at,
      }));
    }
  };

  // The row Gmail is showing for an email, in whichever list is in view.
  const rowFor = (hex) => {
    for (const marker of document.querySelectorAll(`[data-legacy-thread-id="${hex}"], [data-legacy-last-message-id="${hex}"]`)) {
      const row = marker.closest('tr');
      if (shown(row)) return row;
    }
    return null;
  };
  const isBold = (hex) => {
    const row = rowFor(hex);
    return Boolean(row && row.classList.contains('zE')); // Gmail's class for an unread row
  };
  const listShown = () => Array.from(document.querySelectorAll('tr.zA')).some(shown)
    || shown(document.querySelector('td.TC')); // "No messages matched your search"
  // A button in Gmail's toolbar (not the little ones on each row), if it's showing.
  const toolbarButton = (label) => Array.from(document.querySelectorAll(
    `[role="button"][data-tooltip="${label}"], [role="button"][aria-label="${label}"]`))
    .find((button) => !button.closest('tr') && button.getAttribute('aria-disabled') !== 'true' && shown(button)) || null;

  // Ticks an email's row. Gmail hears a tick as a click on some versions and as a press on others.
  const tick = async (row) => {
    const box = row.querySelector('[role="checkbox"]');
    if (!box) return false;
    const ticked = () => box.getAttribute('aria-checked') === 'true' || row.classList.contains('x7');
    for (const types of [['click'], ['mousedown', 'mouseup'], ['mousedown', 'mouseup', 'click']]) {
      if (ticked()) return true;
      fire(box, types);
      if (await waitFor(() => ticked() || null, 1500)) return true;
    }
    return ticked();
  };

  // 1. The list of unread mail (the frame opens on it): tick the emails, click "Mark as read".
  // Returns the emails Gmail no longer shows as unread.
  const markInList = async (hexes) => {
    if (!(await waitFor(() => listShown() || null, Math.min(START_MS, timeLeft())))) {
      say('Gmail didn’t show its list of unread mail');
      return [];
    }
    // Gmail can draw another list first; give the unread list a few seconds to come in.
    await waitFor(() => (hexes.every(rowFor) ? true : null), 5000);
    const found = hexes.filter(rowFor);
    const bold = found.filter(isBold);
    say(`showing the unread list: found ${found.length} of ${hexes.length}, ${bold.length} shown unread`);
    if (bold.length === 0) return found;
    let ticked = 0;
    const ids = [];
    for (const hex of bold) {
      const row = rowFor(hex);
      ids.push(...idsFor(hex, row));
      if (row && (await tick(row))) ticked += 1;
    }
    if (ticked === 0) {
      say('couldn’t tick them');
      return found.filter((hex) => !isBold(hex));
    }
    const button = await waitFor(() => toolbarButton('Mark as read'), 4000);
    if (!button) {
      say(`ticked ${ticked}; Gmail didn’t offer "Mark as read"`);
      return found.filter((hex) => !isBold(hex));
    }
    watch(ids);
    const clicked = Date.now();
    fire(button, ['mousedown', 'mouseup', 'click']);
    await waitFor(() => (bold.every((hex) => !isBold(hex)) ? true : null), 8000);
    const marked = found.filter((hex) => !isBold(hex));
    const cleared = bold.filter((hex) => !isBold(hex)).length;
    say(`ticked ${ticked} and clicked "Mark as read": ${cleared} of ${bold.length} no longer shown unread`);
    if (cleared > 0) say(await toldGoogle(clicked, Math.min(TELL_MS, timeLeft())));
    return marked;
  };

  // 2. Opens an email, the way a click on it would. Gmail counts an email you open as read.
  const openEmail = async (hex) => {
    const before = new Set(document.querySelectorAll('h2.hP'));
    watch(idsFor(hex, rowFor(hex)));
    const asked = Date.now();
    location.replace(`#all/${hex}`); // replace: no extra step in your tab's Back button
    const opened = await waitFor(() => {
      if (shown(document.querySelector(`[data-legacy-message-id="${hex}"]`))) return 'the email';
      return Array.from(document.querySelectorAll('h2.hP')).some((subject) => !before.has(subject) && shown(subject))
        ? 'its conversation' : null;
    }, Math.min(20000, timeLeft()));
    if (!opened) {
      say('Gmail didn’t open an email');
      return false;
    }
    await sleep(1500); // time for Gmail to count it read
    const markRead = toolbarButton('Mark as read');
    if (markRead) fire(markRead, ['mousedown', 'mouseup', 'click']);
    say(`opened ${opened}${markRead ? ' and clicked "Mark as read"' : ''}`);
    say(await toldGoogle(asked, Math.min(TELL_MS, timeLeft())));
    return true;
  };

  const run = async () => {
    say(`script running (this tab is ${document.visibilityState === 'visible' ? 'in view' : 'in the background'})`);
    if (index === null) {
      say('not an account’s page', true);
      return;
    }
    let reply = null;
    try {
      reply = await send({ type: 'hidden-job', index });
    } catch (error) {
      reply = null;
    }
    if (!reply) {
      say('couldn’t ask the add-on which emails', true);
      return;
    }
    const hexes = (reply.hexes || []).filter((hex) => /^[0-9a-f]{6,20}$/.test(hex));
    if (hexes.length === 0) {
      say('nothing to mark in this account', true);
      return;
    }
    const marked = await markInList(hexes);
    const rest = hexes.filter((hex) => !marked.includes(hex));
    let opened = 0;
    for (const hex of rest) {
      if (timeLeft() < 4000) break;
      if (await openEmail(hex)) opened += 1;
    }
    say(`finished: ${marked.length} marked in the list${rest.length ? `, ${opened} of ${rest.length} opened` : ''}`, true);
  };
  run().catch((error) => say(`stopped: ${error && error.message}`, true));

  // In case the add-on doesn't take the frame away (it was updated meanwhile, say).
  setTimeout(() => {
    try {
      if (window.frameElement) window.frameElement.remove();
    } catch (error) {
      // not ours to remove
    }
  }, GONE_MS);
})();
