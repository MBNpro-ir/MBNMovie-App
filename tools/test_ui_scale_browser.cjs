// Build tools/ui_scale_probe.dart and serve build/ui-scale-probe before running.
const {webkit, devices} = require(process.env.MBN_PLAYWRIGHT_PATH);
const assert = require('node:assert/strict');
(async () => {
  const browser = await webkit.launch({headless: true,
    ...(process.env.MBN_WEBKIT_EXECUTABLE ? {executablePath: process.env.MBN_WEBKIT_EXECUTABLE} : {})});
  try {
    for (const dpr of [2, 3]) {
      const context = await browser.newContext({...devices['iPhone 11 Pro'], deviceScaleFactor: dpr});
      await context.addInitScript(() => Object.defineProperty(navigator, 'standalone', {get: () => true}));
      const page = await context.newPage(), errors = [];
      page.on('pageerror', e => errors.push(e.message));
      await page.goto(process.env.MBN_PROBE_URL || 'http://127.0.0.1:8769/');
      await page.waitForFunction(() => window.mbnProbeState && JSON.parse(window.mbnProbeState()).boxes.bottom, null, {timeout: 60000});
      assert.equal(await page.locator('#mbn-viewport-host').count(), 1);
      async function tap(name) {
        const before = await page.evaluate(() => JSON.parse(window.mbnProbeState()));
        const root = await page.locator('flutter-view').boundingBox(), box = before.boxes[name];
        assert(box, name);
        await page.touchscreen.tap(root.x + box.x + box.width / 2, root.y + box.y + box.height / 2);
        await page.waitForTimeout(100);
        const after = await page.evaluate(() => JSON.parse(window.mbnProbeState()));
        assert.equal(after.taps.length, before.taps.length + 1, name);
        assert.equal(after.taps.at(-1), name);
      }
      for (const viewport of [{width:375,height:812}, {width:812,height:375}, {width:375,height:480}, {width:375,height:812}]) {
        await page.setViewportSize(viewport);
        for (const scale of [.6, .8, 1, 1.5, .8]) {
          await page.evaluate(s => window.mbnProbeScale(s), scale);
          await page.waitForTimeout(120);
          await tap('top'); await tap('bottom'); await tap('middle'); await tap('modal');
        }
      }
      // Reproduce a keyboard-panned visual viewport without synthesizing taps
      // or editing pointer coordinates. Flutter still receives real touches.
      await page.evaluate(() => {
        for (const [name, value] of Object.entries({pageLeft:5, pageTop:100, width:360, height:430}))
          Object.defineProperty(visualViewport, name, {configurable:true, get:() => value});
        visualViewport.dispatchEvent(new Event('resize'));
        visualViewport.dispatchEvent(new Event('scroll'));
      });
      await page.waitForTimeout(200);
      await tap('top'); await tap('bottom'); await tap('middle'); await tap('modal');
      await page.evaluate(() => {
        for (const name of ['pageLeft','pageTop','width','height']) delete visualViewport[name];
        visualViewport.dispatchEvent(new Event('resize'));
      });
      await page.waitForTimeout(200);
      await tap('bottom');
      assert.deepEqual(errors, []);
      console.log(`WebKit iPhone 11 Pro DPR ${dpr}: 85 exact-centre touches, live zoom 60–150%, rotation, displaced viewport, HTML surface and modal close PASS`);
      await context.close();
    }
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
