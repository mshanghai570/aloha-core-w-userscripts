'use strict';

const IMPLEMENTED_GRANTS = new Set([
  'GM_info',
  'unsafeWindow',
  'GM_addStyle',
  'GM_log',
  'GM.getValue',
  'GM.setValue',
  'GM.deleteValue',
  'GM.listValues',
  'GM_getValue',
  'GM_setValue',
  'GM_deleteValue',
  'GM_listValues',
]);

function metadataOf(script) {
  return script.metadata || script;
}

function makeGlobRegex(glob) {
  const escaped = String(glob).replace(/[.+^${}()|[\]\\]/g, '\\$&');
  return new RegExp(`^${escaped.replace(/\*/g, '.*')}$`, 'i');
}

function patternMatches(pattern, url) {
  if (pattern === '<all_urls>')
    return url.protocol === 'http:' || url.protocol === 'https:';

  const match = /^(\*|https?):\/\/([^/]+)(\/.*)$/i.exec(pattern);
  if (!match)
    return false;

  const scheme = match[1].toLowerCase();
  if (scheme !== '*' && `${scheme}:` !== url.protocol)
    return false;
  if (scheme === '*' && url.protocol !== 'http:' && url.protocol !== 'https:')
    return false;

  const hostPattern = match[2].toLowerCase();
  const hostname = url.hostname.toLowerCase();
  const actualHost = url.host.toLowerCase();
  let hostMatches = false;
  if (hostPattern === '*') {
    hostMatches = true;
  } else if (hostPattern.startsWith('*.')) {
    const suffix = hostPattern.slice(2);
    const suffixWithPort = suffix.includes(':') ? suffix : null;
    const hostToCheck = suffixWithPort ? actualHost : hostname;
    const suffixToCheck = suffixWithPort || suffix;
    hostMatches = hostToCheck === suffixToCheck ||
      hostToCheck.endsWith(`.${suffixToCheck}`);
  } else {
    hostMatches = hostPattern.includes(':') ? actualHost === hostPattern :
      hostname === hostPattern;
  }
  if (!hostMatches)
    return false;

  const pathAndQuery = `${url.pathname}${url.search}`;
  return makeGlobRegex(match[3]).test(pathAndQuery);
}

function globMatches(glob, href) {
  return makeGlobRegex(glob).test(href);
}

function matchesScript(script, href, isMainFrame = true) {
  const metadata = metadataOf(script);
  let url;
  try {
    url = new URL(href);
  } catch (_) {
    return false;
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:')
    return false;
  if (metadata.noframes && !isMainFrame)
    return false;

  const matchPatterns = metadata.matches || [];
  const includePatterns = metadata.includes || [];
  const hasPositivePattern = matchPatterns.length > 0 || includePatterns.length > 0;
  const positivelyMatched = matchPatterns.some((pattern) =>
    patternMatches(pattern, url)) || includePatterns.some((pattern) =>
    globMatches(pattern, url.href));
  if (!hasPositivePattern || !positivelyMatched)
    return false;

  const excluded = (metadata.excludeMatches || metadata.exclude_matches || [])
      .some((pattern) => patternMatches(pattern, url)) ||
    (metadata.excludes || []).some((pattern) => globMatches(pattern, url.href));
  return !excluded;
}

function normalizeRunAt(value) {
  if (value === 'document-start' || value === 'documentStart')
    return 'document-start';
  if (value === 'document-idle' || value === 'documentIdle')
    return 'document-idle';
  return 'document-end';
}

function selectScripts(scripts, href, isMainFrame, runAt) {
  const desiredRunAt = runAt ? normalizeRunAt(runAt) : null;
  return scripts.filter((script) => {
    if (script.enabled === false || !matchesScript(script, href, isMainFrame))
      return false;
    return !desiredRunAt || normalizeRunAt(metadataOf(script).runAt ||
      metadataOf(script).run_at) === desiredRunAt;
  });
}

function unsupportedRuntimeGrants(script) {
  const grants = metadataOf(script).grants || [];
  return [...new Set(grants.filter((grant) =>
    grant !== 'none' && !IMPLEMENTED_GRANTS.has(grant)))];
}

function cloneValue(value) {
  if (value === undefined)
    return undefined;
  return JSON.parse(JSON.stringify(value));
}

function createMessageSender(context, scriptId, token) {
  return (operation, args) => {
    if (typeof context.sendMessage !== 'function')
      return Promise.reject(new Error('Native userscript handler unavailable'));
    try {
      const result = context.sendMessage({
        scriptId,
        token,
        operation,
        arguments: args,
      });
      return Promise.resolve(result);
    } catch (error) {
      return Promise.reject(error);
    }
  };
}

function createScriptAPI(script, context) {
  const metadata = metadataOf(script);
  const grants = new Set(metadata.grants || []);
  const values = Object.assign(Object.create(null), script.values || {});
  const send = createMessageSender(context, script.id, script.nativeToken);
  const win = context.window;
  const doc = context.document;
  const api = Object.create(null);
  let styleSequence = 0;

  const has = (...names) => names.some((name) => grants.has(name));
  const setValue = (key, value) => {
    const normalizedKey = String(key);
    const safeValue = cloneValue(value);
    const hadPrevious = Object.prototype.hasOwnProperty.call(values, normalizedKey);
    const previousValue = values[normalizedKey];
    values[normalizedKey] = safeValue;
    return send('setValue', {key: normalizedKey, value: safeValue}).catch((error) => {
      if (hadPrevious)
        values[normalizedKey] = previousValue;
      else
        delete values[normalizedKey];
      throw error;
    });
  };
  const getValue = (key, defaultValue) => {
    const normalizedKey = String(key);
    return Object.prototype.hasOwnProperty.call(values, normalizedKey) ?
      cloneValue(values[normalizedKey]) : cloneValue(defaultValue);
  };
  const deleteValue = (key) => {
    const normalizedKey = String(key);
    const hadPrevious = Object.prototype.hasOwnProperty.call(values, normalizedKey);
    const previousValue = values[normalizedKey];
    delete values[normalizedKey];
    return send('deleteValue', {key: normalizedKey}).catch((error) => {
      if (hadPrevious)
        values[normalizedKey] = previousValue;
      throw error;
    });
  };
  const listValues = () => Object.keys(values);

  if (has('GM_info')) {
    api.GM_info = {
      script: {
        name: metadata.name || '',
        namespace: metadata.namespace || metadata.name_space || '',
        version: metadata.version || '',
        description: metadata.description || '',
        author: metadata.author || '',
      },
      scriptHandler: 'Aloha Userscripts',
      version: '0.1',
    };
  }
  if (has('unsafeWindow'))
    api.unsafeWindow = win;
  if (has('GM_log'))
    api.GM_log = (...args) => (context.console || console).log(...args);
  if (has('GM_addStyle')) {
    api.GM_addStyle = (css) => {
      if (!doc || typeof doc.createElement !== 'function')
        return null;
      const style = doc.createElement('style');
      style.dataset.userscriptStyle = `${script.id}-${styleSequence++}`;
      style.textContent = String(css);
      const parent = doc.head || doc.documentElement;
      if (parent)
        parent.appendChild(style);
      else if (typeof doc.addEventListener === 'function')
        doc.addEventListener('DOMContentLoaded', () => {
          (doc.head || doc.documentElement)?.appendChild(style);
        }, {once: true});
      return style;
    };
  }

  const gm = Object.create(null);
  if (has('GM.getValue'))
    gm.getValue = (key, fallback) => Promise.resolve(getValue(key, fallback));
  if (has('GM.setValue'))
    gm.setValue = setValue;
  if (has('GM.deleteValue'))
    gm.deleteValue = deleteValue;
  if (has('GM.listValues'))
    gm.listValues = () => Promise.resolve(listValues());
  if (Object.keys(gm).length)
    api.GM = gm;

  if (has('GM_getValue'))
    api.GM_getValue = getValue;
  if (has('GM_setValue'))
    api.GM_setValue = setValue;
  if (has('GM_deleteValue'))
    api.GM_deleteValue = deleteValue;
  if (has('GM_listValues'))
    api.GM_listValues = listValues;

  return api;
}

function runScript(script, context) {
  const api = createScriptAPI(script, context);
  const source = String(script.source || '');
  const offset = Number.isInteger(script.bodyOffset) ? script.bodyOffset :
    (Number.isInteger(script.body_offset) ? script.body_offset : 0);
  const body = source.slice(Math.max(0, Math.min(offset, source.length)));
  const names = [
    'GM', 'GM_info', 'unsafeWindow', 'GM_addStyle', 'GM_log',
    'GM_getValue', 'GM_setValue', 'GM_deleteValue', 'GM_listValues',
  ];
  const args = names.map((name) => api[name]);
  try {
    const FunctionConstructor = context.window.Function || Function;
    const scriptFunction = new FunctionConstructor(...names, body);
    scriptFunction.apply(context.window, args);
    return true;
  } catch (error) {
    const logger = context.console || console;
    if (logger && typeof logger.error === 'function')
      logger.error(`Userscript ${script.id} failed:`, error);
    if (typeof context.report === 'function')
      context.report({scriptId: script.id, type: 'executionError', message: String(error)});
    return false;
  }
}

function scheduleScript(script, context) {
  const runAt = normalizeRunAt(metadataOf(script).runAt ||
    metadataOf(script).run_at);
  const run = () => runScript(script, context);
  if (runAt === 'document-start') {
    run();
    return;
  }
  const doc = context.document;
  const win = context.window;
  if (!doc || !win)
    return;

  const afterLoad = () => {
    if (runAt !== 'document-idle') {
      win.setTimeout(run, 0);
      return;
    }

    const atIdle = () => {
      if (typeof win.requestIdleCallback === 'function')
        win.requestIdleCallback(run);
      else
        win.setTimeout(run, 0);
    };
    if (doc.readyState === 'complete')
      atIdle();
    else
      win.addEventListener('load', atIdle, {once: true});
  };
  if (doc.readyState === 'loading')
    doc.addEventListener('DOMContentLoaded', afterLoad, {once: true});
  else
    afterLoad();
}

function start(config, environment) {
  const win = environment && environment.window ? environment.window :
    (typeof window !== 'undefined' ? window : null);
  if (!win || !win.document || !config || !Array.isArray(config.scripts))
    return {scheduled: [], skipped: []};

  let isMainFrame = true;
  try {
    isMainFrame = win.top === win.self;
  } catch (_) {
    isMainFrame = false;
  }
  const handler = win.webkit && win.webkit.messageHandlers &&
    win.webkit.messageHandlers.alohaUserscripts;
  const nativeSendMessage = handler &&
    typeof handler.postMessage === 'function' ?
      handler.postMessage.bind(handler) : undefined;
  const context = Object.assign({}, environment, {
    window: win,
    document: win.document,
    console: (environment && environment.console) || win.console || console,
    sendMessage: (environment && environment.sendMessage) || nativeSendMessage,
  });
  const scheduled = [];
  const skipped = [];
  const candidates = selectScripts(config.scripts, win.location.href, isMainFrame);
  for (const script of candidates) {
    const metadata = metadataOf(script);
    const unsupported = unsupportedRuntimeGrants(script);
    const dependenciesPending = (metadata.requireUrls || metadata.require_urls || []).length > 0 ||
      (metadata.resources || []).length > 0;
    if (unsupported.length || dependenciesPending) {
      const report = {
        scriptId: script.id,
        type: dependenciesPending ? 'dependenciesUnavailable' : 'unsupportedGrants',
        grants: unsupported,
      };
      skipped.push(report);
      if (typeof context.report === 'function')
        context.report(report);
      else if (context.console && typeof context.console.warn === 'function')
        context.console.warn('Userscript not run because required features are unavailable:', report);
      continue;
    }
    scheduled.push(script.id);
    scheduleScript(script, context);
  }
  return {scheduled, skipped};
}

const runtime = {
  createScriptAPI,
  matchesScript,
  normalizeRunAt,
  patternMatches,
  runScript,
  selectScripts,
  start,
  unsupportedRuntimeGrants,
};

if (typeof module !== 'undefined' && module.exports)
  module.exports = runtime;
else if (typeof window !== 'undefined')
  runtime.start(__ALOHA_USERSCRIPTS_CONFIG__, window);
