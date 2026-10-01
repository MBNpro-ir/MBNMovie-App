(function (root) {
  'use strict';
  function classify(env) {
    var ua = env.ua || '', brands = env.brands || [];
    var other = /Edg\/|OPR\/|Opera|Firefox|FxiOS|CriOS|SamsungBrowser|YaBrowser|DuckDuckGo/i.test(ua) || env.brave;
    var iphone = /\(iPhone[;) ]/i.test(ua) && /AppleWebKit/i.test(ua) && !/iPad|iPod/i.test(ua);
    if (iphone && !other && (env.standalone || /Version\/.*Safari\//.test(ua))) {
      return env.standalone ? 'allowed' : 'install';
    }
    var windows = env.platform === 'Windows' || /Windows NT/i.test(ua);
    var chrome = /Chrome\//.test(ua) && !other && env.vendor === 'Google Inc.';
    if (brands.length) chrome = chrome && brands.some(function (b) { return b.brand === 'Google Chrome'; });
    return windows && chrome ? 'allowed' : 'blocked';
  }
  var api = { classify: classify };
  if (typeof module !== 'undefined' && module.exports) { module.exports = api; return; }
  root.MBNWebAccess = api;
  var assetRoot = new URL('.', document.currentScript.src);
  var nav = root.navigator;
  var decision = classify({ ua: nav.userAgent, vendor: nav.vendor,
    platform: nav.userAgentData && nav.userAgentData.platform,
    brands: nav.userAgentData && nav.userAgentData.brands,
    brave: !!nav.brave,
    standalone: nav.standalone === true || root.matchMedia('(display-mode: standalone)').matches });
  if (decision === 'allowed') {
    var script = document.createElement('script');
    script.src = new URL('flutter_bootstrap.js', assetRoot).href; script.async = true;
    document.body.appendChild(script);
    return;
  }
  document.documentElement.dir = 'rtl';
  var name = document.title.replace(' Web', '');
  document.getElementById('loading').remove();
  var panel = document.createElement('main');
  panel.id = 'web-access';
  panel.innerHTML = '<div class="access-mark">▶</div><h1>' + name + '</h1>' +
    (decision === 'install' ?
      '<h2>ابتدا روی آیفون نصب کن</h2><p>برای استفاده از برنامه، این صفحه را از Safari روی صفحهٔ اصلی آیفون اضافه کن.</p>' +
      '<ol><li>در Safari دکمهٔ <b>اشتراک‌گذاری (Share)</b> را بزن؛ در بعضی چیدمان‌ها ابتدا دکمهٔ <b>بیشتر (…)</b> را باز کن.</li>' +
      '<li>در فهرست پایین برو و <b>Add to Home Screen</b> (افزودن به صفحهٔ اصلی) را انتخاب کن. اگر نیست، پایین فهرست <b>Edit Actions</b> را بزن و آن را اضافه کن.</li>' +
      '<li>اگر گزینهٔ <b>Open as Web App</b> نمایش داده شد، آن را روشن کن؛ سپس <b>Add</b> (افزودن) را بزن.</li>' +
      '<li>Safari را ببند و آیکون <b>' + name + '</b> را از صفحهٔ اصلی باز کن. از آنجا می‌توانی وارد حساب شوی و تماشا کنی.</li></ol>' +
      '<p class="access-note">نصب در Safari دستی است؛ پس از افزودن، برنامه را از آیکون صفحهٔ اصلی باز کن.</p>' :
      '<h2>این مرورگر یا دستگاه پشتیبانی نمی‌شود</h2><p>نسخهٔ وب فقط روی <b>آیفون با Safari و نصب روی صفحهٔ اصلی</b> یا <b>ویندوز با Google Chrome</b> قابل استفاده است.</p>') +
    '<a class="access-link" href="https://app.mbnpro.ir/">دانلود برنامه و نسخه‌های دیگر</a>';
  document.body.appendChild(panel);
})(typeof window !== 'undefined' ? window : globalThis);
