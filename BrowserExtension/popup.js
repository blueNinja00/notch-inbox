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
    list.appendChild(item);
  }
  when.textContent = status.at ? `Last checked ${new Date(status.at).toLocaleTimeString()}` : '';
  document.getElementById('whole').textContent = status.ok ? wholeEmails(status) : '';
}

function wholeEmails(status) {
  if (status.emailError) return `Whole emails: the last one didn’t load (${status.emailError})`;
  switch (status.fullEmails) {
    case 'ok':
      return 'Whole emails: on';
    case 'on-open':
      return 'Whole emails: loaded when you open one in the notch, since Gmail then counts it as read';
    default:
      return 'Whole emails: starting up';
  }
}

chrome.storage.local.get('status').then((stored) => render(stored.status));

document.getElementById('sync').addEventListener('click', async () => {
  document.getElementById('state').textContent = 'Syncing…';
  render(await chrome.runtime.sendMessage({ type: 'sync-now' }));
});
