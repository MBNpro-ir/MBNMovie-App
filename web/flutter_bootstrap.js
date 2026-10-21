{{flutter_js}}
{{flutter_build_config}}
const mbnAppleMobile = /iPhone|iPad|iPod/.test(navigator.userAgent) || (navigator.vendor.includes('Apple') && navigator.maxTouchPoints > 1);
if (mbnAppleMobile) document.documentElement.classList.add('mbn-apple-mobile');
const mbnAssetRoot = new URL('.', document.currentScript.src).href;
let mbnRefreshViewport = () => {};

// Keep painting and input on one CSS viewport. Safari can report a displaced
// or shorter visualViewport during playback/launch even though the layout
// viewport has not changed. Following it moves the whole app and can create
// a resize/scroll feedback loop. Only a focused software keyboard may shrink
// the host; rotation and real resizes are handled by CSS and ResizeObserver.
function mbnCreateViewportHost() {
  if (!mbnAppleMobile) return undefined;
  Object.assign(document.body.style, {
    position: 'fixed', inset: '0', width: 'auto', height: 'auto',
    overflow: 'hidden', overscrollBehavior: 'none',
  });
  const host = document.createElement('div');
  host.id = 'mbn-viewport-host';
  host.style.cssText = 'position:fixed;inset:0;margin:0;padding:0;overflow:hidden;touch-action:none;';
  document.body.appendChild(host);
  window.scrollTo(0, 0);
  const viewport = window.visualViewport;
  let frame = 0;
  let keyboardVisible = false;
  function editor() {
    let element = document.activeElement;
    while (element?.shadowRoot?.activeElement) element = element.shadowRoot.activeElement;
    return element && !element.readOnly && !element.disabled &&
      (element.tagName === 'TEXTAREA' || element.isContentEditable ||
        (element.tagName === 'INPUT' && /^(text|search|email|password|tel|url|number)$/.test(element.type)))
      ? element : null;
  }
  function sync() {
    frame = 0;
    const layoutHeight = document.documentElement.clientHeight || window.innerHeight;
    const keyboard = editor() && viewport && Math.abs(viewport.scale - 1) < .05 &&
      viewport.height > 0 && layoutHeight - viewport.height > 100;
    const top = keyboard ? Math.max(0, Math.min(viewport.offsetTop, layoutHeight - viewport.height)) : 0;
    const height = keyboard ? viewport.height + 'px' : '';
    if (host.style.top !== top + 'px') host.style.top = top + 'px';
    if (host.style.height !== height) host.style.height = height;
    if (keyboardVisible && !keyboard) window.scrollTo(0, 0);
    keyboardVisible = !!keyboard;
  }
  function schedule() {
    if (!document.hidden && !frame) frame = requestAnimationFrame(sync);
  }
  function onVisualChange() {
    if (keyboardVisible || editor()) schedule();
  }
  mbnRefreshViewport = schedule;
  sync();
  viewport?.addEventListener('resize', onVisualChange, {passive: true});
  viewport?.addEventListener('scroll', onVisualChange, {passive: true});
  window.addEventListener('resize', schedule, {passive: true});
  window.addEventListener('orientationchange', schedule, {passive: true});
  window.addEventListener('pageshow', schedule, {passive: true});
  window.addEventListener('focus', schedule, {passive: true});
  window.addEventListener('mbn-player-state-change', () => {
    // Release focus retained by the previous route. A newly focused text
    // field inside a player dialog can still open the keyboard normally.
    editor()?.blur();
    schedule();
  });
  document.addEventListener('focusin', schedule);
  document.addEventListener('focusout', schedule);
  document.addEventListener('visibilitychange', schedule);
  return host;
}
_flutter.loader.load({
  config: {entryPointBaseUrl: mbnAssetRoot, assetBase: mbnAssetRoot, canvasKitBaseUrl: mbnAssetRoot + 'canvaskit/', ...(mbnAppleMobile ? {canvasKitMaximumSurfaces: 2} : {})},
  onEntrypointLoaded: async function(engineInitializer) {
    // Custom embedding preserves viewport-fit=cover. The app imports Safari's
    // CSS safe-area insets into MediaQuery before scaling its content.
    const hostElement = mbnCreateViewportHost();
    const appRunner = await engineInitializer.initializeEngine({assetBase: mbnAssetRoot, ...(hostElement ? {hostElement} : {})});
    await appRunner.runApp();
    mbnRefreshViewport();
    document.getElementById('loading')?.remove();
    document.documentElement.classList.add('mbn-flutter-ready');
  }
});

// A fresh URL bypasses CDN/browser caches for the small release marker.
// Failed checks leave the running application usable.
const mbnRelease = new URL(mbnAssetRoot).pathname.match(/\/_mbn_web\/([a-f0-9]{12})\//)?.[1];
let mbnUpdateChecking = false;
async function mbnCheckWebUpdate() {
  if (!mbnRelease || document.hidden || mbnUpdateChecking || window.mbnPlayerActive) return;
  mbnUpdateChecking = true;
  try {
    const marker = new URL('mbn-web-version.json', document.baseURI);
    marker.searchParams.set('check', Date.now().toString());
    const response = await fetch(marker, {cache: 'no-store'});
    if (!response.ok) return;
    const next = (await response.json()).version;
    if (/^[a-f0-9]{12}$/.test(next) && next !== mbnRelease && !window.mbnPlayerActive) {
      const url = new URL(location.href);
      url.searchParams.set('_mbn_release', next);
      location.replace(url.href);
    }
  } catch (_) {
    // Retry on the next timer/focus event.
  } finally {
    mbnUpdateChecking = false;
  }
}
setInterval(mbnCheckWebUpdate, 60000);
window.addEventListener('focus', mbnCheckWebUpdate);
document.addEventListener('visibilitychange', mbnCheckWebUpdate);
