const tabs = [...document.querySelectorAll('[role="tab"]')];
function selectTab(tab, focus = false) {
  tabs.forEach(item => { const selected = item === tab; item.setAttribute('aria-selected', String(selected)); item.tabIndex = selected ? 0 : -1; });
  const source = `/assets/screenshots/${tab.dataset.image}.png`;
  document.querySelector('#view-image').src = source;
  document.querySelector('#view-image').alt = tab.dataset.alt;
  document.querySelector('#view-full').href = source;
  document.querySelector('#view-panel').setAttribute('aria-labelledby', tab.id);
  if (focus) tab.focus();
}
tabs.forEach((tab, index) => {
  tab.addEventListener('click', () => selectTab(tab));
  tab.addEventListener('keydown', event => {
    let next;
    if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
    if (event.key === 'ArrowLeft') next = (index + tabs.length - 1) % tabs.length;
    if (event.key === 'Home') next = 0;
    if (event.key === 'End') next = tabs.length - 1;
    if (next !== undefined) { event.preventDefault(); selectTab(tabs[next], true); }
  });
});

const video = document.querySelector('#promo-video');
const play = document.querySelector('#play-promo');
const videoStatus = document.querySelector('#video-status');
if (video && play && videoStatus) {
  let startTimer;
  let startAttempt = 0;
  const clearStart = () => {
    clearTimeout(startTimer);
    play.disabled = false;
  };
  const showProblem = message => {
    clearStart();
    play.hidden = false;
    videoStatus.textContent = message;
    videoStatus.hidden = false;
  };
  const startPlayback = async (focus = false) => {
    const attempt = ++startAttempt;
    clearStart();
    play.disabled = true;
    video.controls = true;
    // Some native players leave play() pending when a media request fails.
    // Keep retry and the always-visible YouTube alternative reachable.
    startTimer = setTimeout(() => {
      if (attempt === startAttempt && video.readyState < 2) {
        showProblem('Das Video lädt noch. Versuche es erneut oder sieh es auf YouTube an.');
      }
    }, 8000);
    try {
      await video.play();
      if (attempt !== startAttempt) return;
      clearStart();
      play.hidden = true;
      videoStatus.hidden = true;
      if (focus) video.focus();
    } catch {
      if (attempt === startAttempt) showProblem('Das Video konnte nicht gestartet werden. Versuche es erneut oder nutze den YouTube-Link.');
    }
  };
  // Native controls are available without JS. Enhance the poster only after
  // installing the click handler; never preload or autoplay the media.
  play.addEventListener('click', () => startPlayback(true));
  video.addEventListener('playing', () => { clearStart(); play.hidden = true; videoStatus.hidden = true; video.controls = true; });
  video.addEventListener('error', () => showProblem('Das Video ist gerade nicht verfügbar. Du kannst es auf YouTube ansehen.'));
  video.tabIndex = 0;
  video.controls = false;
  play.hidden = false;
  // A single keyboard target works across browser-native control layouts.
  video.addEventListener('keydown', event => {
    if (event.target === video && (event.key === ' ' || event.key === 'k')) {
      event.preventDefault();
      if (video.paused) {
        startPlayback();
      } else video.pause();
    }
  });
}

// Copy buttons stay hidden without JS or clipboard access; the command remains selectable.
for (const button of document.querySelectorAll('[data-copy]')) {
  const source = document.getElementById(button.dataset.copy);
  if (!source || !navigator.clipboard) continue;
  const label = button.textContent;
  let reset;
  button.hidden = false;
  button.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(source.textContent.trim());
      button.textContent = 'Kopiert';
    } catch {
      button.textContent = 'Bitte markieren und kopieren';
    }
    clearTimeout(reset);
    reset = setTimeout(() => { button.textContent = label; }, 2500);
  });
}
