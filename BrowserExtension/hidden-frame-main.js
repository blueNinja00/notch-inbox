// Notch Inbox Link: runs in Gmail pages, but does nothing unless the page is the add-on's
// invisible frame (named "notch-inbox-hidden"), where it marks emails you read in the notch
// read in Gmail. Gmail in your tabs is left alone.
//
// The frame sits off the edge of a Gmail tab, often one you're not looking at, so the page
// counts as hidden, and Gmail may wait until you're looking before it counts an email as read.
// So inside that frame only, the page is told it's in view and focused. It also stays out of
// your way: it can't take the keyboard from your Gmail tab or put up a dialog, and there are no
// desktop notifications or sounds from it (your own Gmail tab still gives those).
(() => {
  const NAME = 'notch-inbox-hidden'; // the name the add-on gives its frame
  if (window.top === window || window.name !== NAME) return;

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
