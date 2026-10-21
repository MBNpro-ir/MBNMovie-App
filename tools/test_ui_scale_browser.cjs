// Build tools/ui_scale_probe.dart and serve build/ui-scale-probe before running.
const {webkit, chromium, devices} = require(process.env.MBN_PLAYWRIGHT_PATH);
const assert = require('node:assert/strict');
(async () => {
  const engine = process.env.MBN_BROWSER_ENGINE || 'webkit';
  const browser = engine === 'chrome'
    ? await chromium.launch({headless:true, channel:'chrome'})
    : await webkit.launch({headless: true,
        ...(process.env.MBN_WEBKIT_EXECUTABLE ? {executablePath: process.env.MBN_WEBKIT_EXECUTABLE} : {})});
  try {
    for (const dpr of [2, 3]) {
      const context = await browser.newContext({...devices['iPhone 11 Pro'], deviceScaleFactor: dpr});
      await context.addInitScript(() => Object.defineProperty(navigator, 'standalone', {get: () => true}));
      const page = await context.newPage(), errors = [];
      page.on('pageerror', e => errors.push(e.message));
      await page.goto(process.env.MBN_PROBE_URL || 'http://127.0.0.1:8769/');
      // Headless WebKit reports zero env(safe-area-inset-*). Supply the
      // physical iPhone insets through the same CSS probe the app reads.
      // This is a simulation, not a physical-device test.
      await page.addStyleTag({content: `
        #mbn-safe-area {padding:var(--probe-top, 44px) var(--probe-right, 0px)
          var(--probe-bottom, 34px) var(--probe-left, 0px)!important}
      `});
      await page.waitForFunction(() => window.mbnProbeState && JSON.parse(window.mbnProbeState()).boxes.bottom, null, {timeout: 60000});
      assert.equal(await page.locator('#mbn-viewport-host').count(), 1);
      let touches = 0;
      async function assertLayout() {
        const state = await page.evaluate(() => JSON.parse(window.mbnProbeState()));
        const root = await page.locator('flutter-view').boundingBox();
        const full = state.boxes.viewport, content = state.boxes['safe-content'], safe = state.safeArea;
        function near(actual, expected, name) {
          assert(Math.abs(actual - expected) < 1, `${name}: ${actual} != ${expected}`);
        }
        near(full.x, 0, 'canvas x'); near(full.y, 0, 'canvas y');
        near(full.width, root.width, 'full canvas width');
        near(full.height, root.height, 'full canvas height');
        near(content.x, safe.left, 'safe left'); near(content.y, safe.top, 'safe top');
        near(content.x + content.width, root.width - safe.right, 'safe right');
        near(content.y + content.height, root.height - safe.bottom, 'safe bottom');
        for (const name of ['top', 'bottom']) {
          const box = state.boxes[name];
          assert(box.x >= content.x - 1 && box.x + box.width <= content.x + content.width + 1, `${name} outside safe width`);
          assert(box.y >= content.y - 1 && box.y + box.height <= content.y + content.height + 1, `${name} under system UI`);
        }
      }
      async function tap(name) {
        const before = await page.evaluate(() => JSON.parse(window.mbnProbeState()));
        const root = await page.locator('flutter-view').boundingBox(), box = before.boxes[name];
        assert(box, name);
        await page.touchscreen.tap(root.x + box.x + box.width / 2, root.y + box.y + box.height / 2);
        await page.waitForTimeout(100);
        const after = await page.evaluate(() => JSON.parse(window.mbnProbeState()));
        assert.equal(after.taps.length, before.taps.length + 1, name);
        assert.equal(after.taps.at(-1), name);
        touches++;
      }
      for (const viewport of [{width:375,height:812}, {width:812,height:375}, {width:375,height:480}, {width:375,height:812}]) {
        const landscape = viewport.width > viewport.height;
        await page.evaluate(landscape => {
          const style = document.documentElement.style;
          for (const [side, value] of Object.entries(landscape
            ? {top:0, right:44, bottom:21, left:44}
            : {top:44, right:0, bottom:34, left:0})) style.setProperty('--probe-' + side, value + 'px');
        }, landscape);
        await page.setViewportSize(viewport);
        for (const scale of [.6, .8, 1, 1.5, .8]) {
          await page.evaluate(s => window.mbnProbeScale(s), scale);
          await page.waitForTimeout(120);
          await assertLayout();
          await tap('top'); await tap('bottom'); await tap('middle'); await tap('modal');
        }
      }
      await page.screenshot({path: process.env.MBN_PROBE_SCREENSHOT || `build/iphone-safe-area-${engine}-dpr${dpr}.png`});
      // Reproduce a keyboard-panned visual viewport without synthesizing taps
      // or editing pointer coordinates. Flutter still receives real touches.
      await page.evaluate(() => {
        for (const [name, value] of Object.entries({pageLeft:5, pageTop:100, width:360, height:430}))
          Object.defineProperty(visualViewport, name, {configurable:true, get:() => value});
        visualViewport.dispatchEvent(new Event('resize'));
        visualViewport.dispatchEvent(new Event('scroll'));
      });
      await page.waitForTimeout(200);
      await assertLayout();
      await tap('top'); await tap('bottom'); await tap('middle'); await tap('modal');
      await page.evaluate(() => {
        for (const name of ['pageLeft','pageTop','width','height']) delete visualViewport[name];
        visualViewport.dispatchEvent(new Event('resize'));
      });
      await page.waitForTimeout(200);
      await assertLayout();
      await tap('bottom');
      assert.deepEqual(errors, []);
      console.log(`${engine} iPhone 11 Pro DPR ${dpr}: ${touches} exact-centre touches, simulated portrait/landscape safe areas, full canvas, live zoom 60–150%, rotation, displaced viewport, HTML surface and modal close PASS`);
      await context.close();
    }
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
