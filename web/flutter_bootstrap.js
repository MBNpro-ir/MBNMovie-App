{{flutter_js}}
{{flutter_build_config}}
const mbnAppleMobile = /iPhone|iPad|iPod/.test(navigator.userAgent) || (navigator.vendor.includes('Apple') && navigator.maxTouchPoints > 1);
if (mbnAppleMobile) document.documentElement.classList.add('mbn-apple-mobile');
const mbnAssetRoot = new URL('.', document.currentScript.src).href;

// Safari's visual viewport can move independently of the layout viewport
// after keyboard use, page zoom or rotation. Let Flutter measure the same
// DOM rectangle used for input coordinates, instead of mixing full-page
// dimensions with a displaced visual viewport. Desktop keeps full-page mode.
function mbnCreateViewportHost() {
  if (!mbnAppleMobile) return undefined;
  const host = document.createElement('div');
  host.id = 'mbn-viewport-host';
  host.style.cssText = 'position:absolute;margin:0;padding:0;overflow:hidden;touch-action:none;';
  document.body.appendChild(host);
  const viewport = window.visualViewport;
  let frame = 0;
  function sync() {
    frame = 0;
    const values = {
      left: viewport ? viewport.pageLeft : window.scrollX,
      top: viewport ? viewport.pageTop : window.scrollY,
      width: viewport && viewport.width > 0 ? viewport.width : window.innerWidth,
      height: viewport && viewport.height > 0 ? viewport.height : window.innerHeight,
    };
    for (const [key, value] of Object.entries(values)) {
      const css = value + 'px';
      if (host.style[key] !== css) host.style[key] = css;
    }
  }
  function schedule() {
    if (!frame) frame = requestAnimationFrame(sync);
  }
  sync();
  viewport?.addEventListener('resize', schedule, {passive: true});
  viewport?.addEventListener('scroll', schedule, {passive: true});
  window.addEventListener('resize', schedule, {passive: true});
  window.addEventListener('orientationchange', schedule, {passive: true});
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
