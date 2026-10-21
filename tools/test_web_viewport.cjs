const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require('node:path').join(__dirname, '../web/flutter_bootstrap.js'), 'utf8')
  .replace(/\{\{flutter_js\}\}|\{\{flutter_build_config\}\}/g, '');

async function check(apple) {
  const listeners = {}, frames = [], children = [];
  const listen = prefix => (name, handler) => { listeners[prefix + name] = handler; };
  const viewport = {width: 375, height: 812, pageLeft: 0, pageTop: 0, addEventListener: listen('viewport:')};
  let initialization;
  const context = {
    URL, console, setInterval: () => {}, requestAnimationFrame: handler => { frames.push(handler); return frames.length; },
    navigator: {userAgent: apple ? 'iPhone' : 'Windows', vendor: apple ? 'Apple' : 'Google', maxTouchPoints: apple ? 5 : 0},
    window: {visualViewport: viewport, innerWidth: 375, innerHeight: 812, scrollX: 0, scrollY: 0, addEventListener: listen('window:')},
    document: {
      currentScript: {src: 'https://example.test/_mbn_web/123456abcdef/flutter_bootstrap.js'},
      documentElement: {classList: {add: () => {}}},
      body: {appendChild: host => children.push(host)}, createElement: () => ({style: {}}),
      getElementById: () => null, addEventListener: listen('document:'),
    },
    _flutter: {loader: {load: async options => {
      await options.onEntrypointLoaded({initializeEngine: async config => {
        initialization = config; return {runApp: async () => {}};
      }});
    }}},
  };
  vm.runInNewContext(source, context);
  await new Promise(resolve => setImmediate(resolve));
  if (!apple) {
    assert.equal(initialization.hostElement, undefined);
    assert.equal(children.length, 0);
    return;
  }
  const host = initialization.hostElement;
  assert.equal(host, children[0]);
  assert.equal(host.style.width, '375px');
  assert.equal(host.style.height, '812px');
  Object.assign(viewport, {width: 312.5, height: 340, pageLeft: 8, pageTop: 167});
  listeners['viewport:resize'](); listeners['viewport:scroll']();
  assert.equal(frames.length, 1, 'viewport changes coalesce into one frame');
  frames.shift()();
  assert.deepEqual([host.style.left, host.style.top, host.style.width, host.style.height], ['8px','167px','312.5px','340px']);
  Object.assign(viewport, {width: 812, height: 375, pageLeft: 0, pageTop: 0});
  listeners['window:orientationchange'](); frames.shift()();
  assert.deepEqual([host.style.left, host.style.top, host.style.width, host.style.height], ['0px','0px','812px','375px']);
  Object.assign(viewport, {width: 375, height: 812});
  listeners['document:focusout'](); frames.shift()();
  assert.equal(host.style.height, '812px');
}
(async () => { await check(false); await check(true); console.log('Safari viewport zoom, keyboard offsets, rotation and desktop isolation passed'); })()
  .catch(error => { console.error(error); process.exitCode = 1; });
