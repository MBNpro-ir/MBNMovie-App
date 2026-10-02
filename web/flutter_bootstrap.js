{{flutter_js}}
{{flutter_build_config}}
const mbnAppleMobile = /iPhone|iPad|iPod/.test(navigator.userAgent) || (navigator.vendor.includes('Apple') && navigator.maxTouchPoints > 1);
const mbnAssetRoot = new URL('.', document.currentScript.src).href;
_flutter.loader.load({
  config: {entrypointBaseUrl: mbnAssetRoot, assetBase: mbnAssetRoot, canvasKitBaseUrl: mbnAssetRoot + 'canvaskit/', ...(mbnAppleMobile ? {canvasKitMaximumSurfaces: 2} : {})},
  onEntrypointLoaded: async function(engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine({assetBase: mbnAssetRoot});
    await appRunner.runApp();
    document.getElementById('loading')?.remove();
  }
});

const mbnRelease = new URL(mbnAssetRoot).pathname.match(/\/_mbn_web\/([a-f0-9]{12})\//)?.[1];
let mbnUpdateChecking = false;
async function mbnCheckWebUpdate() {
  if (!mbnRelease || document.hidden || mbnUpdateChecking) return;
  mbnUpdateChecking = true;
  try {
    const marker = new URL('mbn-web-version.json', document.baseURI);
    marker.searchParams.set('check', Date.now().toString());
    const response = await fetch(marker, {cache: 'no-store'});
    if (!response.ok) return;
    const next = (await response.json()).version;
    if (/^[a-f0-9]{12}$/.test(next) && next !== mbnRelease) {
      const url = new URL(location.href);
      url.searchParams.set('_mbn_release', next);
      location.replace(url.href);
    }
  } catch (_) {
    // A failed update check never blocks the running app.
  } finally {
    mbnUpdateChecking = false;
  }
}
setInterval(mbnCheckWebUpdate, 60000);
window.addEventListener('focus', mbnCheckWebUpdate);
document.addEventListener('visibilitychange', mbnCheckWebUpdate);
