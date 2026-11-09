// Notch Inbox Link: runs in Gmail pages, but does nothing unless the page is the add-on's
// hidden Gmail frame. There, for 25 seconds, it tells the add-on what Gmail is showing, for
// the mark-read log: a mail list or an email, which part of Gmail (#inbox, #all…), whether
// the page counts as visible, and whether Gmail offers "Mark as unread" (it does once it
// counts the email read). It never sends what an email says.
(() => {
  const ancestors = location.ancestorOrigins ? Array.from(location.ancestorOrigins) : [];
  if (window.top === window || ancestors[0] !== `chrome-extension://${chrome.runtime.id}`) return;

  const started = Date.now();
  let last = '';
  const report = () => {
    const title = document.title || '';
    let shows = 'nothing yet';
    if (document.querySelector('h2.hP')) shows = 'an email';
    else if (/^(Inbox|Primary|All Mail|Search results)\b/i.test(title)) shows = 'a mail list';
    else if (title) shows = 'something else';
    const part = location.hash ? `${location.hash.split('/')[0]}/${location.hash.includes('/') ? '…' : ''}` : 'no #';
    const read = document.querySelector('[data-tooltip="Mark as unread"], [aria-label="Mark as unread"]')
      ? 'Gmail offers "Mark as unread" (counts it read)'
      : 'no "Mark as unread"';
    const state = `showing ${shows}, ${part}, page ${document.visibilityState}, ${read}`;
    if (state !== last) {
      last = state;
      chrome.runtime.sendMessage({ type: 'hidden-frame', state, after: Math.round((Date.now() - started) / 1000) })
        .catch(() => {});
    }
    if (Date.now() - started < 25000) setTimeout(report, 1000);
  };
  setTimeout(report, 300);
})();
