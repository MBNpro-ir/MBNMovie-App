const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require('node:path').join(__dirname, '../web/flutter_bootstrap.js'), 'utf8')
  .replace(/\{\{flutter_js\}\}|\{\{flutter_build_config\}\}/g, '');

async function check(apple, visualViewport = true) {
  const listeners = {}, frames = [], children = [];
  const listen = prefix => (name, handler) => {
    const key = prefix + name, previous = listeners[key];
    listeners[key] = previous ? (...args) => {previous(...args); handler(...args);} : handler;
  };
  const viewport = {width:375, height:812, pageLeft:0, pageTop:0, offsetTop:0, scale:1,
    addEventListener:listen('viewport:')};
  const body = {style:{}, appendChild:host => children.push(host)};
  let initialization, scrollResets = 0;
  const context = {
    URL, console, setInterval:() => {},
    requestAnimationFrame:handler => {frames.push(handler); return frames.length;},
    navigator:{userAgent:apple ? 'iPhone' : 'Windows', vendor:apple ? 'Apple' : 'Google', maxTouchPoints:apple ? 5 : 0},
    window:{visualViewport:visualViewport ? viewport : undefined, innerWidth:375, innerHeight:812,
      scrollTo:() => scrollResets++, addEventListener:listen('window:')},
    document:{
      currentScript:{src:'https://example.test/_mbn_web/123456abcdef/flutter_bootstrap.js'},
      documentElement:{clientHeight:812, classList:{add:() => {}}},
      body, activeElement:body, createElement:() => ({style:{}}),
      getElementById:() => null, addEventListener:listen('document:'),
    },
    _flutter:{loader:{load:async options => {
      await options.onEntrypointLoaded({initializeEngine:async config => {
        initialization = config; return {runApp:async () => {}};
      }});
    }}},
  };
  vm.runInNewContext(source, context);
  await new Promise(resolve => setImmediate(resolve));
  if (!apple) {
    assert.equal(initialization.hostElement, undefined);
    assert.equal(children.length, 0);
    assert.deepEqual(body.style, {}, 'desktop embedding is untouched');
    assert.equal(frames.length, 0);
    return;
  }
  const host = initialization.hostElement;
  const flush = () => {while (frames.length) frames.shift()();};
  const emit = event => {listeners[event]?.();};
  const fullFrame = () => {
    assert.match(host.style.cssText, /position:fixed;inset:0;/);
    assert.equal(host.style.top, '0px');
    assert.equal(host.style.height, '', 'CSS owns full viewport height');
    assert.equal(host.style.width, undefined, 'CSS owns width through rotation');
  };
  flush();
  assert.equal(host, children[0]);
  assert.equal(body.style.position, 'fixed');
  assert.equal(body.style.height, 'auto');
  assert.equal(scrollResets, 1, 'discard persisted document scroll on startup');
  fullFrame();
  for (let i = 0; i < 120; i++) {
    Object.assign(viewport, {pageTop:i % 2 ? 34 : 0, pageLeft:8, offsetTop:34, height:i % 2 ? 744 : 778});
    emit('viewport:resize'); emit('viewport:scroll');
    assert.equal(frames.length, 0, 'no per-frame root work from Safari noise without an editor');
  }
  for (const event of ['window:pageshow', 'window:focus', 'document:visibilitychange', 'window:orientationchange']) {
    emit(event); flush(); fullFrame();
  }
  if (!visualViewport) return;
  const input = {tagName:'INPUT', type:'text', blur:() => {context.document.activeElement = body;}};
  context.document.activeElement = input;
  Object.assign(viewport, {height:430, width:360, pageTop:170, offsetTop:70});
  emit('document:focusin'); emit('viewport:resize'); emit('viewport:scroll');
  assert.equal(frames.length, 1, 'keyboard events coalesce'); flush();
  assert.equal(host.style.top, '70px', 'use viewport-relative offset, never document pageTop');
  assert.equal(host.style.height, '430px');
  context.window.mbnPlayerActive = true;
  emit('window:mbn-player-state-change'); flush(); fullFrame();
  assert.equal(context.document.activeElement, body, 'player entry releases stale editing focus');
  emit('viewport:resize');
  assert.equal(frames.length, 0, 'playback has no keyboard-driven resize');
  context.document.activeElement = input;
  emit('document:focusin'); flush();
  assert.equal(host.style.height, '430px', 'a new text field in a player dialog still supports the keyboard');
  Object.assign(viewport, {scale:2});
  emit('viewport:resize'); flush(); fullFrame();
  Object.assign(viewport, {scale:1});
  input.readOnly = true;
  emit('document:focusin'); flush(); fullFrame();
  input.readOnly = false;
  input.type = 'range';
  emit('document:focusin'); flush(); fullFrame();
  context.document.activeElement = {shadowRoot:{activeElement:{tagName:'TEXTAREA'}}};
  emit('document:focusin'); flush();
  assert.equal(host.style.height, '430px', 'shadow-root text editing works');
  context.document.activeElement = body;
  emit('document:focusout'); flush(); fullFrame();
  assert.equal(scrollResets, 4, 'keyboard/player exit clears phantom document scroll');
  context.document.documentElement.clientHeight = 375;
  context.window.innerHeight = 375;
  Object.assign(viewport, {height:375, width:812, offsetTop:0});
  emit('window:orientationchange'); flush(); fullFrame();
  context.document.hidden = true;
  emit('document:visibilitychange');
  assert.equal(frames.length, 0, 'no background layout work');
}
(async () => {
  await check(false); await check(true); await check(true, false);
  console.log('Fixed iPhone viewport, 120 jitter events, keyboard focus/blur, player entry, pinch zoom, rotation and desktop isolation passed');
})().catch(error => {console.error(error); process.exitCode = 1;});
