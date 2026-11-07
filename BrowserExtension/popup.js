function render(status) {
  const state = document.getElementById('state');
  const list = document.getElementById('accounts');
  const when = document.getElementById('when');
  list.textContent = '';

  if (!status) {
    state.textContent = 'Not synced yet.';
    state.className = '';
    when.textContent = '';
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
}

chrome.storage.local.get('status').then((stored) => render(stored.status));

document.getElementById('sync').addEventListener('click', async () => {
  document.getElementById('state').textContent = 'Syncing…';
  render(await chrome.runtime.sendMessage({ type: 'sync-now' }));
});
