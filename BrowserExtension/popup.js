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
    const { sent, failed } = status.markRead;
    whole += ` · Marked read in Gmail: ${sent}${failed ? ` (${failed} couldn’t be)` : ''}`;
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

document.getElementById('version').textContent = `Version ${chrome.runtime.getManifest().version}`;
chrome.storage.local.get('status').then((stored) => render(stored.status));
// Keep up while the popup is open.
chrome.storage.onChanged.addListener((changes, area) => {
  if (area === 'local' && changes.status) render(changes.status.newValue);
});

document.getElementById('sync').addEventListener('click', async () => {
  document.getElementById('state').textContent = 'Syncing…';
  render(await chrome.runtime.sendMessage({ type: 'sync-now' }));
});
