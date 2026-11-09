// Notch Inbox Link: runs in Gmail pages, but does nothing unless the page is one of the
// add-on's hidden frames (where it marks emails you read in the notch read in Gmail). Gmail
// in your tabs is left alone.
//
// Out of sight, the page counts as hidden, and Gmail seems to wait until you're looking
// before it counts an email as read. So inside that hidden frame only, the page is told it's
// in view and focused.
(() => {
  const ADD_ON = 'chrome-extension://hhjiihfliaidbbicblcafpaikelnbdpp';
  const NAME = 'notch-inbox-hidden'; // the name the add-on gives its hidden frames
  const ancestors = location.ancestorOrigins ? Array.from(location.ancestorOrigins) : [];
  if (window.top === window || (window.name !== NAME && !ancestors.includes(ADD_ON))) return;

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
