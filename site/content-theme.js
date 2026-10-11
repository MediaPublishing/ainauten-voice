// Shares the homepage's preference and .dark interface, without loading React.
const themeSelect = document.querySelector('#content-theme');
const systemTheme = matchMedia('(prefers-color-scheme: dark)');
let preference = 'system';
try {
  const saved = localStorage.getItem('theme');
  if (saved === 'light' || saved === 'dark') preference = saved;
} catch { /* The selector remains usable when storage is unavailable. */ }

function applyTheme() {
  document.documentElement.classList.toggle('dark', preference === 'dark' || (preference === 'system' && systemTheme.matches));
  document.documentElement.dataset.themeReady = 'true';
  if (themeSelect) themeSelect.value = preference;
}
applyTheme();
if (themeSelect) {
  themeSelect.closest('label').hidden = false;
  themeSelect.addEventListener('change', () => {
    preference = themeSelect.value;
    try {
      if (preference === 'system') localStorage.removeItem('theme');
      else localStorage.setItem('theme', preference);
    } catch { /* Persistence is optional, switching is not. */ }
    applyTheme();
  });
}
systemTheme.addEventListener('change', () => {
  if (preference === 'system') applyTheme();
});
window.addEventListener('storage', event => {
  if (event.key === 'theme' || event.key === null) {
    preference = event.newValue === 'light' || event.newValue === 'dark' ? event.newValue : 'system';
    applyTheme();
  }
});
