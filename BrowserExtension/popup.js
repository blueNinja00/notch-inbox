function render(status) {
  const state = document.getElementById('state');
  const list = document.getElementById('accounts');
  const when = document.getElementById('when');
  list.textContent = '';

  if (!status) {
    state.textContent = 'Not synced yet.';
    state.className = '';
    when.textContent = '';
    document.getElementById('whole').textContent = '';
    return;
  }

  state.textContent = status.message;
  state.className = status.ok ? 'ok' : 'bad';
  for (const account of status.accounts || []) {
    const item = document.createElement('li');
    item.textContent = account;
    const counts = (status.counts || {})[account];
    if (counts) {
      const detail = document.createElement('div');
      detail.className = 'counts';
      const parts = [];
      if (counts.primary !== null && counts.primary !== undefined) parts.push(`Primary ${counts.primary}`);
      if (counts.inbox !== null && counts.inbox !== undefined) parts.push(`whole inbox ${counts.inbox}`);
      detail.textContent = parts.length ? `Gmail says unread: ${parts.join(' · ')}` : '';
      item.appendChild(detail);
    }
    list.appendChild(item);
  }
  when.textContent = status.at ? `Last checked ${new Date(status.at).toLocaleTimeString()}` : '';
  let whole = status.ok ? wholeEmails(status) : '';
  if (status.ok && status.markRead) {
    const { asked, worked, how } = status.markRead;
    const missed = Math.max(0, (asked || 0) - (worked || 0));
    const way = how === 'hidden' ? ', out of sight' : (how === 'tab' ? ', in a background tab' : '');
    whole += ` · Marked read in Gmail: ${worked || 0}${way}${missed ? ` (${missed} not yet, trying again)` : ''}`;
  }
  document.getElementById('whole').textContent = whole;
}

function wholeEmails(status) {
  if (status.trying) return 'Whole emails: opening one…';
  if (status.emailError) return `Whole emails: the last one didn’t load (${status.emailError})`;
  const count = status.wholeFetched ? ` · ${status.wholeFetched} so far` : '';
  switch (status.fullEmails) {
    case 'ok':
      return `Whole emails: on${count}`;
    case 'on-open':
      return `Whole emails: only ones you open in the notch, since Gmail then counts them as read${count}`;
    default:
      return 'Whole emails: waiting for an unread email to try';
  }
}

// What happened the last few times it marked emails read: for working out what goes wrong.
function renderLog(lines) {
  if (lines && lines.length) {
    document.getElementById('log').textContent = lines.slice(-40).join('\n');
  }
}

document.getElementById('version').textContent = `Version ${chrome.runtime.getManifest().version}`;
chrome.storage.local.get(['status', 'readLog']).then((stored) => {
  render(stored.status);
  renderLog(stored.readLog);
});
// Keep up while the popup is open.
chrome.storage.onChanged.addListener((changes, area) => {
  if (area === 'local' && changes.status) render(changes.status.newValue);
  if (area === 'local' && changes.readLog) renderLog(changes.readLog.newValue);
});

document.getElementById('copyLog').addEventListener('click', async () => {
  const stored = await chrome.storage.local.get('readLog');
  const text = `Notch Inbox Link ${chrome.runtime.getManifest().version}\n${(stored.readLog || []).join('\n')}`;
  await navigator.clipboard.writeText(text);
  document.getElementById('copyLog').textContent = 'Copied';
});

document.getElementById('sync').addEventListener('click', async () => {
  document.getElementById('state').textContent = 'Syncing…';
  render(await chrome.runtime.sendMessage({ type: 'sync-now' }));
});
