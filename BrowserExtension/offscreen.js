// Notch Inbox Link: the out-of-sight page. Asked by the add-on, it opens emails in Gmail in a
// hidden frame, one after another, giving Gmail a few seconds on each to mark it read, then
// takes the frame away. It only ever loads mail.google.com.

const GMAIL_PAGE = /^https:\/\/mail\.google\.com\//;

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (!message || message.target !== 'offscreen' || message.type !== 'open-gmail') return false;
  openAll(message.pages || [], message.settle || 4000, message.loadTimeout || 30000).then(sendResponse);
  return true; // answers asynchronously
});

async function openAll(pages, settle, loadTimeout) {
  const frame = document.createElement('iframe');
  frame.style.cssText = 'width: 1280px; height: 800px; border: 0;';
  document.body.appendChild(frame);
  let opened = 0;
  let current = '';
  try {
    for (const page of pages) {
      if (!GMAIL_PAGE.test(page)) continue;
      if (current && sameDocument(current, page)) {
        frame.src = page; // only the part after # changes: Gmail switches emails without reloading
      } else if (!(await load(frame, page, loadTimeout))) {
        break;
      }
      current = page;
      opened += 1;
      await wait(settle);
    }
  } finally {
    frame.remove();
  }
  return { opened };
}

function sameDocument(a, b) {
  return a.split('#')[0] === b.split('#')[0] && b.includes('#');
}

function load(frame, url, timeout) {
  return new Promise((resolve) => {
    const finish = (loaded) => {
      clearTimeout(timer);
      frame.removeEventListener('load', onLoad);
      resolve(loaded);
    };
    const onLoad = () => finish(true);
    const timer = setTimeout(() => finish(false), timeout);
    frame.addEventListener('load', onLoad);
    frame.src = url;
  });
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

if (typeof module !== 'undefined' && module.exports) module.exports = { openAll, sameDocument };
