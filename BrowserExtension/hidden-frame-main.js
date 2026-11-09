// Notch Inbox Link: runs in Gmail pages, but does nothing unless the page is the add-on's
// invisible frame (named "notch-inbox-hidden"), where it marks emails you read in the notch
// read in Gmail. Gmail in your tabs is left alone.
//
// The frame sits off the edge of a Gmail tab, often one you're not looking at. So inside that
// frame only:
//   - the page is told it's in view and focused, since Gmail may wait until you're looking;
//   - Gmail's timers are kept from being held back for minutes (see "Timers" below), so a
//     change it means to send Google goes when it should;
//   - it stays out of your way: it can't take the keyboard from your Gmail tab or put up a
//     dialog, and there are no desktop notifications or sounds from it;
//   - what Gmail sends Google is noted for the add-on's log: where each request went, how it
//     ended, and whether it names an email being marked read. Never what's in it.
(() => {
  const NAME = 'notch-inbox-hidden'; // the name the add-on gives its frame
  if (window.top === window || window.name !== NAME) return;

  // Whether the page really is out of view (before it's told otherwise below).
  const visibility = Object.getOwnPropertyDescriptor(Document.prototype, 'visibilityState');
  const reallyHidden = () => {
    try {
      return visibility.get.call(document) !== 'visible';
    } catch (error) {
      return false;
    }
  };

  const define = (name, value) => {
    try {
      Object.defineProperty(Document.prototype, name, { configurable: true, get: () => value });
    } catch (error) {
      // leave it
    }
  };
  define('visibilityState', 'visible');
  define('webkitVisibilityState', 'visible');
  define('hidden', false);
  define('webkitHidden', false);
  try {
    Document.prototype.hasFocus = () => true;
  } catch (error) {
    // leave it
  }

  const nothing = () => {};
  for (const [owner, name, value] of [
    [HTMLElement.prototype, 'focus', nothing],
    [SVGElement.prototype, 'focus', nothing],
    [window, 'focus', nothing],
    [window, 'alert', nothing],
    [window, 'confirm', () => false],
    [window, 'prompt', () => null],
  ]) {
    try {
      owner[name] = value;
    } catch (error) {
      // leave it
    }
  }

  try {
    const Quiet = function Notification() {
      return { close() {}, addEventListener() {}, removeEventListener() {} };
    };
    Quiet.permission = 'denied';
    Quiet.requestPermission = () => Promise.resolve('denied');
    Object.defineProperty(window, 'Notification', { configurable: true, writable: true, value: Quiet });
  } catch (error) {
    // leave it
  }
  try {
    HTMLMediaElement.prototype.play = () => Promise.resolve();
  } catch (error) {
    // leave it
  }

  // Timers. Chrome holds back the timers of a page you're not looking at: to the second at
  // first, and once each timer has set the next a few times over, to the minute. Gmail chains
  // its timers, so in a background tab a change it means to send Google can wait minutes.
  // Here each timer's callback runs from a message rather than from the timer itself, which
  // keeps chains from building up, so Chrome only rounds them to the second. (Once a timer
  // has gone off its callback still runs, as it would have anyway.)
  const realSetTimeout = window.setTimeout;
  const realClearTimeout = window.clearTimeout;
  try {
    const channel = new MessageChannel();
    const due = new Map(); // timer → its callback, once Chrome has set it off
    channel.port1.onmessage = (event) => {
      const run = due.get(event.data);
      if (run) {
        due.delete(event.data);
        run();
      }
    };
    window.setTimeout = function setTimeout(handler, ms, ...args) {
      if (typeof handler !== 'function') return realSetTimeout.apply(window, arguments);
      const timer = realSetTimeout.call(window, () => {
        due.set(timer, () => handler.apply(window, args));
        channel.port2.postMessage(timer);
      }, ms);
      return timer;
    };
  } catch (error) {
    // leave them
  }
  // A page out of view gets no animation frames at all; Gmail's still come, a little later.
  try {
    const realRequest = window.requestAnimationFrame;
    const realCancel = window.cancelAnimationFrame;
    const backups = new Map();
    if (typeof realRequest !== 'function' || typeof realCancel !== 'function') throw new Error('no animation frames');
    window.requestAnimationFrame = function requestAnimationFrame(callback) {
      let ran = false;
      let frame = 0;
      const run = (time) => {
        if (ran) return;
        ran = true;
        const backup = backups.get(frame);
        if (backup !== undefined) realClearTimeout.call(window, backup);
        backups.delete(frame);
        callback(time);
      };
      frame = realRequest.call(window, run);
      if (reallyHidden()) backups.set(frame, window.setTimeout(() => run(performance.now()), 100));
      return frame;
    };
    window.cancelAnimationFrame = function cancelAnimationFrame(frame) {
      const backup = backups.get(frame);
      if (backup !== undefined) realClearTimeout.call(window, backup);
      backups.delete(frame);
      return realCancel.call(window, frame);
    };
  } catch (error) {
    // leave them
  }

  // What Gmail sends Google, for hidden-frame.js to report. It says which emails to look out
  // for (their IDs); each request is checked for them, but only the yes or no is kept.
  let watched = [];
  document.addEventListener('notch-inbox-watch', (event) => {
    try {
      watched = JSON.parse(event.detail).filter((id) => typeof id === 'string' && /^[0-9a-f]{6,25}$/.test(id));
    } catch (error) {
      watched = [];
    }
  });
  const where = (url) => {
    try {
      const parsed = new URL(String(url), location.href);
      return parsed.host === location.host ? parsed.pathname : parsed.host;
    } catch (error) {
      return '?';
    }
  };
  // true or false; null when it can't be told (nothing watched, or a body that can't be read).
  const names = (body) => {
    if (watched.length === 0 || body === undefined || body === null) return null;
    let text = null;
    try {
      if (typeof body === 'string') text = body;
      else if (body instanceof URLSearchParams) text = body.toString();
      else if (body instanceof ArrayBuffer || ArrayBuffer.isView(body)) text = new TextDecoder('latin1').decode(body);
      else if (body instanceof FormData) text = Array.from(body.values()).filter((value) => typeof value === 'string').join('&');
    } catch (error) {
      text = null;
    }
    return text === null ? null : watched.some((id) => text.includes(id));
  };
  const tell = (entry) => {
    try {
      document.dispatchEvent(new CustomEvent('notch-inbox-net', { detail: JSON.stringify(entry) }));
    } catch (error) {
      // nobody listening
    }
  };
  try {
    const realFetch = window.fetch;
    if (realFetch) {
      window.fetch = function fetch(input, init) {
        const result = realFetch.apply(window, arguments);
        try {
          const url = typeof input === 'string' ? input : (input && input.url) || String(input);
          const method = String((init && init.method) || (input && input.method) || 'GET').toUpperCase();
          const entry = { method, path: where(url), mentions: names(init && init.body), at: Date.now() };
          tell({ ...entry, phase: 'sent' });
          result.then((response) => tell({ ...entry, phase: 'done', status: response.status }),
            () => tell({ ...entry, phase: 'done', status: 0 }));
        } catch (error) {
          // just not noted
        }
        return result;
      };
    }
  } catch (error) {
    // leave it
  }
  try {
    const open = XMLHttpRequest.prototype.open;
    const send = XMLHttpRequest.prototype.send;
    const requests = new WeakMap();
    XMLHttpRequest.prototype.open = function (method, url) {
      try {
        requests.set(this, { method: String(method).toUpperCase(), path: where(url) });
      } catch (error) {
        // just not noted
      }
      return open.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function (body) {
      const info = requests.get(this);
      if (info) {
        try {
          const entry = { ...info, mentions: names(body), at: Date.now() };
          tell({ ...entry, phase: 'sent' });
          this.addEventListener('loadend', () => tell({ ...entry, phase: 'done', status: this.status }));
        } catch (error) {
          // just not noted
        }
      }
      return send.apply(this, arguments);
    };
  } catch (error) {
    // leave them
  }
  try {
    const beacon = navigator.sendBeacon;
    if (beacon) {
      navigator.sendBeacon = function sendBeacon(url, data) {
        const queued = beacon.apply(navigator, arguments);
        tell({ method: 'BEACON', path: where(url), mentions: names(data), at: Date.now(), phase: 'done', status: queued ? 202 : 0 });
        return queued;
      };
    }
  } catch (error) {
    // leave it
  }

  // Say so the way a page hears it when you look at it.
  const nudge = () => {
    document.dispatchEvent(new Event('visibilitychange'));
    window.dispatchEvent(new Event('focus'));
  };
  window.addEventListener('load', nudge);
  let count = 0;
  const timer = setInterval(() => {
    nudge();
    count += 1;
    if (count >= 20) clearInterval(timer);
  }, 1000);
})();
