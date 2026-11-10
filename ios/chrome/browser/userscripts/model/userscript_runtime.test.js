import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import vm from 'node:vm';

const runtimeSource = await readFile(
    new URL('./userscript_runtime.js', import.meta.url), 'utf8');
const runtimeModule = {exports: {}};
vm.runInNewContext(runtimeSource, {
  module: runtimeModule,
  exports: runtimeModule.exports,
  URL,
  console,
});
const runtime = runtimeModule.exports;

function script(overrides = {}) {
  const base = {
    id: 'script-1',
    enabled: true,
    source: 'unsafeWindow.ran = true;',
    bodyOffset: 0,
    metadata: {
      name: 'Example',
      namespace: 'tests',
      version: '1.0',
      matches: ['https://*.example.com/*'],
      includes: [],
      excludes: [],
      excludeMatches: [],
      grants: ['unsafeWindow'],
      runAt: 'document-start',
      noframes: false,
      requireUrls: [],
      resources: [],
    },
  };
  return {
    ...base,
    ...overrides,
    metadata: {...base.metadata, ...(overrides.metadata || {})},
  };
}

function fakeWindow(href = 'https://shop.example.com/page') {
  const document = {
    readyState: 'complete',
    head: {appendChild(element) { this.lastChild = element; }},
    createElement(tagName) { return {tagName, dataset: {}}; },
    addEventListener() {},
  };
  return {
    document,
    location: {href},
    top: null,
    self: null,
    setTimeout(callback) { callback(); },
    console: {log() {}, warn() {}, error() {}},
  };
}

test('matches match patterns on HTTP(S) and respects wildcard subdomains', () => {
  const value = script();
  assert.equal(runtime.matchesScript(value, 'https://example.com/a'), true);
  assert.equal(runtime.matchesScript(value, 'https://sub.example.com/a'), true);
  assert.equal(runtime.matchesScript(value, 'https://notexample.com/a'), false);
  assert.equal(runtime.matchesScript(value, 'http://sub.example.com/a'), false);
  assert.equal(runtime.matchesScript(value, 'file:///tmp/a'), false);
});

test('includes are positive matches and exclusions win', () => {
  const value = script({metadata: {
    matches: [],
    includes: ['https://*.example.com/*'],
    excludes: ['*private*'],
    excludeMatches: ['https://secure.example.com/admin/*'],
  }});
  assert.equal(runtime.matchesScript(value, 'https://shop.example.com/page'), true);
  assert.equal(runtime.matchesScript(value, 'https://shop.example.com/private'), false);
  assert.equal(runtime.matchesScript(value, 'https://secure.example.com/admin/home'), false);
  assert.equal(runtime.matchesScript(value, 'https://other.test/page'), false);
});

test('@noframes restricts a script to the top frame', () => {
  const value = script({metadata: {
    matches: ['https://*.example.com/*'],
    noframes: true,
  }});
  assert.equal(runtime.matchesScript(value, 'https://shop.example.com/', true), true);
  assert.equal(runtime.matchesScript(value, 'https://shop.example.com/', false), false);
});

test('selectScripts partitions enabled scripts by run-at timing', () => {
  const start = script({id: 'start'});
  const end = script({id: 'end', metadata: {
    matches: ['https://*.example.com/*'], runAt: 'document-end', grants: [],
  }});
  const disabled = script({id: 'disabled', enabled: false});
  assert.deepEqual(
      Array.from(runtime.selectScripts([start, end, disabled],
          'https://shop.example.com/', true, 'document-start'),
          (value) => value.id),
      ['start']);
  assert.deepEqual(
      Array.from(runtime.selectScripts([start, end, disabled],
          'https://shop.example.com/', true, 'document-end'),
          (value) => value.id),
      ['end']);
});

test('modern and legacy storage APIs use isolated snapshots and message writes', async () => {
  const win = fakeWindow();
  const messages = [];
  const context = {
    window: win,
    document: win.document,
    sendMessage(message) { messages.push(message); },
    console: win.console,
  };
  const first = script({nativeToken: 'capability-1', values: {count: 2}, metadata: {
    grants: ['GM.getValue', 'GM.setValue', 'GM.deleteValue', 'GM.listValues',
      'GM_getValue', 'GM_setValue', 'GM_deleteValue', 'GM_listValues'],
  }});
  const second = script({id: 'script-2', values: {}, metadata: {
    grants: ['GM_getValue'],
  }});
  const firstApi = runtime.createScriptAPI(first, context);
  const secondApi = runtime.createScriptAPI(second, context);

  assert.equal(firstApi.GM_getValue('count'), 2);
  assert.equal(secondApi.GM_getValue('count', 7), 7);
  assert.equal(await firstApi.GM.getValue('missing', 'fallback'), 'fallback');
  await firstApi.GM.setValue('count', 3);
  assert.equal(firstApi.GM_getValue('count'), 3);
  await firstApi.GM.deleteValue('count');
  assert.deepEqual(Array.from(await firstApi.GM.listValues()), []);
  assert.deepEqual(messages.map((message) => message.operation),
      ['setValue', 'deleteValue']);
  assert.ok(messages.every((message) => message.scriptId === 'script-1'));
  assert.ok(messages.every((message) => message.token === 'capability-1'));
});

test('uses the captured WebKit native handler for GM storage messages', () => {
  const win = fakeWindow();
  win.top = win;
  win.self = win;
  const messages = [];
  win.webkit = {messageHandlers: {alohaUserscripts: {
    postMessage(message) { messages.push(message); },
  }}};
  const value = script({
    source: "GM_setValue('saved', true);",
    nativeToken: 'native-token',
    metadata: {grants: ['GM_setValue']},
  });

  runtime.start({scripts: [value]}, {window: win});

  assert.equal(messages.length, 1);
  assert.equal(messages[0].operation, 'setValue');
  assert.equal(messages[0].token, 'native-token');
  assert.equal(messages[0].arguments.key, 'saved');
  assert.equal(messages[0].arguments.value, true);
});

test('rejected GM storage writes restore the local value snapshot', async () => {
  const win = fakeWindow();
  const api = runtime.createScriptAPI(script({values: {count: 2}, metadata: {
    grants: ['GM.getValue', 'GM.setValue', 'GM.deleteValue'],
  }}), {
    window: win,
    document: win.document,
    console: win.console,
    sendMessage() { return Promise.reject(new Error('quota exceeded')); },
  });

  await assert.rejects(api.GM.setValue('count', 3), /quota exceeded/);
  assert.equal(await api.GM.getValue('count'), 2);
  await assert.rejects(api.GM.deleteValue('count'), /quota exceeded/);
  assert.equal(await api.GM.getValue('count'), 2);
});

test('GM_info, unsafeWindow, and GM_addStyle are grant-gated', () => {
  const win = fakeWindow();
  const api = runtime.createScriptAPI(script({metadata: {
    grants: ['GM_info', 'unsafeWindow', 'GM_addStyle'],
  }}), {window: win, document: win.document, console: win.console});
  assert.equal(api.unsafeWindow, win);
  assert.equal(api.GM_info.script.name, 'Example');
  const style = api.GM_addStyle('body { color: red; }');
  assert.equal(style.tagName, 'style');
  assert.equal(style.textContent, 'body { color: red; }');

  const ungranted = runtime.createScriptAPI(script({metadata: {grants: []}}), {
    window: win, document: win.document, console: win.console,
  });
  assert.equal(ungranted.GM_info, undefined);
  assert.equal(ungranted.unsafeWindow, undefined);
  assert.equal(ungranted.GM_addStyle, undefined);
});

test('scripts requiring unsupported grants or unresolved dependencies are not run', () => {
  const win = fakeWindow();
  win.top = win;
  win.self = win;
  const reports = [];
  const xhrScript = script({metadata: {
    matches: ['https://*.example.com/*'],
    grants: ['GM_xmlhttpRequest'],
  }});
  const requireScript = script({id: 'require', metadata: {
    matches: ['https://*.example.com/*'],
    grants: [],
    requireUrls: ['https://cdn.example/lib.js'],
  }});
  const menuScript = script({id: 'menu', metadata: {
    matches: ['https://*.example.com/*'],
    grants: ['GM_registerMenuCommand'],
  }});
  const result = runtime.start({scripts: [xhrScript, requireScript, menuScript]}, {
    window: win,
    report(report) { reports.push(report); },
  });
  assert.deepEqual(Array.from(result.scheduled), []);
  assert.deepEqual(Array.from(result.skipped, (item) => item.type),
      ['unsupportedGrants', 'dependenciesUnavailable', 'unsupportedGrants']);
  assert.equal(reports.length, 3);
  assert.equal(win.ran, undefined);
});

test('document-start scripts execute immediately in the injected page world', () => {
  const win = fakeWindow();
  win.top = win;
  win.self = win;
  const result = runtime.start({scripts: [script()]}, {window: win});
  assert.deepEqual(Array.from(result.scheduled), ['script-1']);
  assert.equal(win.ran, true);
});

test('document-idle scripts wait for the page idle callback', () => {
  const win = fakeWindow();
  win.top = win;
  win.self = win;
  let idleCallback;
  win.requestIdleCallback = (callback) => { idleCallback = callback; };
  const value = script({metadata: {runAt: 'document-idle'}});

  const result = runtime.start({scripts: [value]}, {window: win});

  assert.deepEqual(Array.from(result.scheduled), ['script-1']);
  assert.equal(win.ran, undefined);
  assert.equal(typeof idleCallback, 'function');
  idleCallback();
  assert.equal(win.ran, true);
});
