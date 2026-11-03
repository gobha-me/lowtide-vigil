'use strict';

// No packages or copied game functions: evaluate the actual inline script in a
// fresh VM per case. Only boot() is suppressed; browser services are fixtures.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const htmlPath = process.argv[2] || path.join(__dirname, '../../web/lowtide-vigil.html');
const html = fs.readFileSync(htmlPath, 'utf8');
const scripts = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi)];
assert.equal(scripts.length, 1, 'expected the browser game inline script');
const bootCall = /\nboot\(\);\s*\n\}\)\(\);\s*$/;
assert.match(scripts[0][1], bootCall, 'must find the startup call, outside function bodies');
const source = scripts[0][1].replace(bootCall, `
globalThis.game = {G, PAD, MU, padMenus, pollPad, showPause, resume};
})();
`);

function fixture() {
  const document = {activeElement: null};
  const timers = [];
  class Element {
    constructor(tagName, id = '') {
      this.tagName = tagName.toUpperCase();
      this.id = id;
      this.hidden = false;
      this.listeners = new Map();
      this.children = [];
      this.style = {};
    }
    addEventListener(type, callback) {
      if (!this.listeners.has(type)) this.listeners.set(type, []);
      this.listeners.get(type).push(callback);
    }
    click() {
      for (const callback of this.listeners.get('click') || []) callback({target: this});
    }
    focus() { document.activeElement = this; }
    blur() { document.activeElement = document.body; }
    appendChild(child) { this.children.push(child); }
    querySelector(selector) {
      assert.equal(selector, 'button:not([disabled])');
      assert.equal(this.id, 'pause');
      return elements.get('bResume');
    }
    getContext(kind) {
      assert.equal(kind, '2d');
      return {
        createImageData: (w, h) => ({data: new Uint8ClampedArray(w * h * 4)}),
        putImageData() {},
      };
    }
  }
  const elements = new Map([...html.matchAll(/<([a-z][\w-]*)\b[^>]*\bid="([^"]+)"[^>]*>/gi)]
    .map((match) => [match[2], new Element(match[1], match[2])]));
  document.body = new Element('body');
  document.activeElement = document.body;
  document.getElementById = (id) => {
    assert.ok(elements.has(id), `fixture needs a real page element: ${id}`);
    return elements.get(id);
  };
  document.querySelector = (selector) => {
    assert.ok(selector.startsWith('#'), `unexpected selector: ${selector}`);
    return document.getElementById(selector.slice(1));
  };
  let visibleButtons = ['bResume', 'tSound', 'tShake', 'tScan', 'bQuit']
    .map((id) => document.getElementById(id));
  document.querySelectorAll = (selector) => {
    assert.equal(selector, '.ov:not([hidden]) button:not([disabled])');
    return visibleButtons;
  };
  document.createElement = (tag) => new Element(tag);
  document.addEventListener = () => {};
  const pad = {
    connected: true,
    axes: [0, 0, 0, 0],
    buttons: Array.from({length: 17}, () => ({pressed: false, value: 0})),
  };
  let pads = [pad];
  const navigator = {getGamepads: () => pads};
  const context = vm.createContext({
    document, navigator,
    window: {addEventListener() {}},
    performance: {now: () => 0},
    setTimeout: (callback) => timers.push(callback),
  });
  vm.runInContext(source, context, {filename: htmlPath, timeout: 2000});
  const game = context.game;
  return {
    ...game, document, elements, navigator, pad,
    setPads: (value) => { pads = value; },
    emptyMenu: () => { visibleButtons = []; document.activeElement = null; },
    press: (index, pressed) => Object.assign(pad.buttons[index], {pressed, value: pressed ? 1 : 0}),
    pause() {
      game.G.state = 'play';
      game.showPause(); // Real pause UI and real resume click listener.
      while (timers.length) timers.shift()();
      assert.equal(game.G.state, 'paused');
      assert.equal(document.activeElement, elements.get('bResume'));
    },
  };
}

function assertPlaying(f, message) {
  assert.equal(f.G.state, 'play', message);
  assert.equal(f.elements.get('pause').hidden, true, 'real resume hides the overlay');
  assert.equal(f.MU.vol, 1, 'real resume restores music volume');
}

const cases = {
  'Start resume consumes the edge before same-frame gameplay polling'() {
    const f = fixture();
    f.pause();
    f.press(9, true);
    f.padMenus();
    assertPlaying(f, 'Start must resume');
    assert.equal(f.PAD.startPrev, true, 'resume must latch Start even after state becomes play');
    assert.equal(f.document.activeElement, f.document.body, 'real resume drops focus');
    // frame() calls padMenus() before update() calls pollPad(). Repeat gameplay
    // polls for catch-up steps, then menu/gameplay pairs with the same held pad.
    for (let step = 0; step < 5; step++) {
      f.pollPad();
      assertPlaying(f, 'same-frame held Start must not immediately pause again');
    }
    for (let frame = 0; frame < 3; frame++) {
      f.padMenus();
      f.pollPad();
      assertPlaying(f, 'holding Start over subsequent frames must keep playing');
    }
  },

  'release rearms Start and each next press toggles exactly once'() {
    const f = fixture();
    f.pause();
    f.press(9, true);
    f.padMenus();
    f.pollPad();
    assertPlaying(f);
    f.press(9, false);
    f.padMenus();
    f.pollPad();
    assert.equal(f.PAD.startPrev, false, 'gameplay release rearms Start');
    f.press(9, true);
    f.padMenus(); // The play guard must leave the edge for pollPad().
    assert.equal(f.PAD.startPrev, false);
    f.pollPad();
    assert.equal(f.G.state, 'paused', 'the next press pauses once');
    assert.equal(f.elements.get('pause').hidden, false);
    assert.equal(f.MU.vol, 0.35);
    f.pollPad();
    f.padMenus();
    assert.equal(f.G.state, 'paused', 'held Start must not resume again');
    f.press(9, false);
    f.padMenus();
    assert.equal(f.PAD.startPrev, false, 'menu release rearms Start');
    f.press(9, true);
    f.padMenus();
    f.pollPad();
    assertPlaying(f, 'a new press resumes once');
  },

  'A activating the real Resume button also consumes simultaneous Start'() {
    const f = fixture();
    f.pause();
    f.press(0, true);
    f.press(9, true);
    f.padMenus();
    assertPlaying(f, 'the real registered Resume click handler runs');
    assert.equal(f.PAD.aPrev, true);
    assert.equal(f.PAD.startPrev, true);
    f.pollPad();
    assertPlaying(f, 'simultaneous Start cannot undo a button resume');
  },

  'A resume records a Start release after the state changes to play'() {
    const f = fixture();
    f.pause();
    f.PAD.startPrev = true;
    f.press(0, true);
    f.padMenus();
    assertPlaying(f);
    assert.equal(f.PAD.startPrev, false, 'a release must also cross the resume state change');
    f.press(0, false);
    f.press(9, true);
    f.pollPad();
    assert.equal(f.G.state, 'paused', 'next Start edge must not be lost');
  },

  'Start in other menus is latched without resuming'() {
    for (const state of ['title', 'cards', 'shop', 'end']) {
      const f = fixture();
      f.G.state = state;
      f.press(9, true);
      for (let frame = 0; frame < 2; frame++) {
        f.padMenus();
        assert.equal(f.G.state, state);
        assert.equal(f.PAD.startPrev, true);
      }
      f.press(9, false);
      f.padMenus();
      assert.equal(f.PAD.startPrev, false);
    }
  },

  'absent API, empty slots and disconnected pads are safe'() {
    for (const input of ['no-api', [], [null], [null, {connected: false}]]) {
      const f = fixture();
      f.pause();
      if (input === 'no-api') delete f.navigator.getGamepads;
      else f.setPads(input);
      f.PAD.l = [1, 1];
      f.PAD.r = [1, 1];
      f.PAD.fire = f.PAD.dash = true;
      f.padMenus();
      assert.equal(f.G.state, 'paused');
      f.pollPad();
      assert.equal(f.G.state, 'paused');
      assert.equal(f.PAD.l, null);
      assert.equal(f.PAD.r, null);
      assert.equal(f.PAD.fire, false);
      assert.equal(f.PAD.dash, false);
    }
  },

  'first connected pad after empty and disconnected slots can resume'() {
    const f = fixture();
    f.pause();
    f.setPads([null, {connected: false}, f.pad]);
    f.press(9, true);
    f.padMenus();
    f.pollPad();
    assertPlaying(f);
  },

  'empty menu and missing focus do not block Start resume'() {
    const f = fixture();
    f.pause();
    f.emptyMenu();
    f.pad.axes[0] = 1;
    f.press(0, true);
    f.press(9, true);
    f.padMenus();
    f.pollPad();
    assertPlaying(f);
  },
};

let failures = 0;
for (const [name, run] of Object.entries(cases)) {
  try {
    run();
    console.log(`PASS ${name}`);
  } catch (error) {
    failures++;
    console.error(`FAIL ${name}\n${error.stack}`);
  }
}
if (failures) process.exitCode = 1;
else console.log(`BROWSER PAD: passed (${Object.keys(cases).length} cases)`);
