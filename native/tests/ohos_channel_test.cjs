#!/usr/bin/env node
'use strict';

// Execute the actual ArkTS channel handler with isolated platform/native doubles.
// No C VM, NAPI worker, ArkTS type checker, or device is exercised by this suite.
// Run: node native/tests/ohos_channel_test.cjs
// Optional compiler override: QFLI_ARKTS_TYPESCRIPT=<typescript package or JS file>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '../..');
const templatePath = path.join(root, 'native/ohos/QfliPyNative.ets');
const packagedPath = path.join(root, 'ohos/entry/src/main/ets/plugins/QfliPyNative.ets');

function loadTypeScript() {
  const explicit = process.env.QFLI_ARKTS_TYPESCRIPT;
  if (explicit) {
    const resolved = path.resolve(explicit);
    if (!fs.existsSync(resolved)) {
      throw new Error(`QFLI_ARKTS_TYPESCRIPT does not exist: ${resolved}`);
    }
    return { ts: require(resolved), location: resolved };
  }
  const suffix = 'openharmony/ets/build-tools/ets-loader/node_modules/typescript';
  const candidates = [];
  for (const sdk of [process.env.DEVECO_SDK_HOME, process.env.OHOS_SDK_HOME]) {
    if (sdk) {
      candidates.push(path.join(sdk, suffix));
      candidates.push(path.join(sdk, 'default', suffix));
    }
  }
  const localProperties = path.join(root, 'ohos/local.properties');
  if (fs.existsSync(localProperties)) {
    const match = /^sdk\.dir\s*=\s*(.+)$/m.exec(fs.readFileSync(localProperties, 'utf8'));
    if (match) {
      const sdk = match[1].trim().replace(/\\([\\: ])/g, '$1');
      candidates.push(path.join(sdk, 'default', suffix));
      candidates.push(path.join(sdk, suffix));
    }
  }
  const installations = [
    process.env.DEVECO_HOME,
    'D:/ProgramFiles/Huawei/DevEco Studio',
    'C:/Program Files/Huawei/DevEco Studio',
    '/Applications/DevEco-Studio.app/Contents',
  ].filter(Boolean);
  for (const installation of installations) {
    candidates.push(path.join(installation, 'sdk/default', suffix));
  }
  for (const candidate of [...new Set(candidates)]) {
    if (fs.existsSync(path.join(candidate, 'package.json'))) {
      return { ts: require(candidate), location: candidate };
    }
  }
  throw new Error('SDK TypeScript was not found. Set QFLI_ARKTS_TYPESCRIPT to an existing '
    + 'TypeScript package directory or compiler JS file; this suite never downloads dependencies.');
}

const { ts, location } = loadTypeScript();
assert.equal(typeof ts.transpileModule, 'function', 'The compiler must export transpileModule');
const source = fs.readFileSync(packagedPath, 'utf8');
const startup = /^  selfCheck\(\);\r?$/gm;
assert.equal([...source.matchAll(startup)].length, 1,
  'Review startup-call isolation if registerQfliPyNativeChannel changes');
const isolated = source.replace(/^import[\s\S]*?;\r?$/gm, '').replace(startup, '');
const transpiled = ts.transpileModule(isolated, {
  fileName: 'QfliPyNative.ts',
  reportDiagnostics: true,
  compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
});
const syntaxErrors = (transpiled.diagnostics || [])
  .filter(item => item.category === ts.DiagnosticCategory.Error);
assert.equal(syntaxErrors.length, 0, syntaxErrors
  .map(item => ts.flattenDiagnosticMessageText(item.messageText, '\n')).join('\n'));

function harness(native) {
  let handler;
  const context = {
    exports: {}, qfliPyNative: native, Error, Promise,
    hilog: { info() {}, error() {} }, fs: {},
    MethodChannel: class { setMethodCallHandler(value) { handler = value; } },
    setTimeout, clearTimeout,
  };
  vm.runInNewContext(transpiled.outputText, context, { filename: packagedPath });
  context.exports.registerQfliPyNativeChannel({
    dartExecutor: { getBinaryMessenger: () => ({}) },
  });
  assert.ok(handler, 'The real module must register a MethodChannel handler');
  return {
    invoke(method, args = {}) {
      const events = [];
      let thrown;
      try {
        handler.onMethodCall({ method, argument: key => args[key] }, {
          success: value => events.push({ kind: 'success', value }),
          error: (code, message) => events.push({ kind: 'error', code, message }),
          notImplemented: () => events.push({ kind: 'notImplemented' }),
        });
      } catch (error) { thrown = error; }
      return { events, get thrown() { return thrown; } };
    },
  };
}

const outcome = { exitCode: 7, output: 'out\n', error: 'err\n', truncated: true };
const tick = () => new Promise(resolve => setImmediate(resolve));
const tests = [];
function test(name, action) { tests.push({ name, action }); }
function controlled(run) {
  const freed = [], cancelled = [];
  let token = 100;
  return {
    native: { run, version: () => 'loaded-native-version', createCancel: () => ++token,
      freeCancel: value => freed.push(value), cancel: value => cancelled.push(value) },
    freed, cancelled,
  };
}
function event(result, kind) {
  assert.equal(result.thrown, undefined, `Uncaught channel exception: ${result.thrown}`);
  assert.equal(result.events.length, 1, 'Each request must complete exactly once');
  assert.equal(result.events[0].kind, kind);
  return result.events[0];
}

test('both ArkTS copies are byte-for-byte identical', () => {
  assert.deepEqual(fs.readFileSync(templatePath), fs.readFileSync(packagedPath));
});
test('missing module reports unavailable and a specific execution error', () => {
  const h = harness(undefined);
  const probe = event(h.invoke('available'), 'success').value;
  assert.equal(probe.available, false);
  assert.equal(probe.runControl, false);
  assert.equal(probe.bytecode, false);
  assert.ok(probe.detail);
  assert.equal(event(h.invoke('run', { source: '' }), 'error').code,
    'QFLI_PY_MODULE_MISSING');
});
test('legacy module advertises only capabilities it has', () => {
  const h = harness({ run: () => outcome, version: () => 'legacy-version' });
  const probe = event(h.invoke('available'), 'success').value;
  assert.equal(probe.available, true);
  assert.equal(probe.version, 'legacy-version');
  assert.equal(probe.runControl, false);
  assert.equal(probe.bytecode, false);
  event(h.invoke('prepareRun'), 'error');
});
test('partial cancellation exports do not advertise controlled execution', () => {
  for (const missing of ['createCancel', 'cancel', 'freeCancel']) {
    const c = controlled(() => Promise.resolve(outcome));
    delete c.native[missing];
    const probe = event(harness(c.native).invoke('available'), 'success').value;
    assert.equal(probe.runControl, false, `Missing ${missing}`);
    assert.equal(probe.bytecode, false, `Missing ${missing}`);
  }
});
test('complete native adapter advertises real version and controlled capabilities', () => {
  const c = controlled(() => Promise.resolve(outcome));
  const probe = event(harness(c.native).invoke('available'), 'success').value;
  assert.equal(probe.available, true);
  assert.equal(probe.version, 'loaded-native-version');
  assert.equal(probe.runControl, true);
  assert.equal(probe.bytecode, true);
});
test('legacy synchronous result completes channel without altering native fields', async () => {
  const h = harness({ run: () => outcome, version: () => 'old' });
  const result = h.invoke('run', { source: 'print(1)' });
  await tick();
  assert.equal(JSON.stringify(event(result, 'success').value), JSON.stringify(outcome));
});
test('synchronous native throw completes error and releases claimed token', async () => {
  const c = controlled(() => { throw new Error('native sync failure'); });
  const h = harness(c.native);
  const id = event(h.invoke('prepareRun'), 'success').value;
  const result = h.invoke('run', { source: '', runId: id });
  await tick();
  assert.equal(event(result, 'error').message, 'native sync failure');
  assert.equal(c.freed.length, 1);
  assert.equal(event(h.invoke('cancel', { runId: id }), 'success').value, false);
});
test('asynchronous native rejection completes error and releases token', async () => {
  const c = controlled(() => Promise.reject('native async failure'));
  const h = harness(c.native);
  const id = event(h.invoke('prepareRun'), 'success').value;
  const result = h.invoke('run', { source: '', runId: id });
  await tick();
  assert.equal(event(result, 'error').message, 'native async failure');
  assert.equal(c.freed.length, 1);
});
test('malformed native outcomes are transport errors and release claimed tokens', async () => {
  for (const malformed of [undefined, null, {}, { exitCode: '0' }]) {
    const c = controlled(() => Promise.resolve(malformed));
    const h = harness(c.native);
    const id = event(h.invoke('prepareRun'), 'success').value;
    const result = h.invoke('run', { source: '', runId: id });
    await tick();
    event(result, 'error');
    assert.equal(c.freed.length, 1);
    assert.equal(event(h.invoke('cancel', { runId: id }), 'success').value, false);
  }
});
test('successful completion retains output/status and late stop is harmless', async () => {
  const c = controlled(() => Promise.resolve(outcome));
  const h = harness(c.native);
  const id = event(h.invoke('prepareRun'), 'success').value;
  const result = h.invoke('run', { source: '', runId: id });
  await tick();
  assert.equal(JSON.stringify(event(result, 'success').value), JSON.stringify(outcome));
  assert.equal(c.freed.length, 1);
  assert.equal(event(h.invoke('cancel', { runId: id }), 'success').value, false);
  assert.equal(c.cancelled.length, 0);
});
test('duplicate submission cannot claim or free the active token twice', async () => {
  let resolve;
  const c = controlled(() => new Promise(done => { resolve = done; }));
  const h = harness(c.native);
  const id = event(h.invoke('prepareRun'), 'success').value;
  const first = h.invoke('run', { source: '', runId: id });
  event(h.invoke('run', { source: '', runId: id }), 'error');
  assert.equal(c.freed.length, 0);
  assert.equal(event(h.invoke('cancel', { runId: id }), 'success').value, true);
  assert.equal(c.cancelled.length, 1);
  resolve(outcome);
  await tick();
  event(first, 'success');
  assert.equal(c.freed.length, 1);
});
test('separate queued sessions preserve cancellation ownership', async () => {
  const resolvers = [], received = [];
  const c = controlled((...args) => {
    received.push(args);
    return new Promise(done => resolvers.push(done));
  });
  const h = harness(c.native);
  const a = event(h.invoke('prepareRun'), 'success').value;
  const b = event(h.invoke('prepareRun'), 'success').value;
  const first = h.invoke('run', { source: 'a', runId: a });
  const second = h.invoke('run', { source: 'b', runId: b });
  event(h.invoke('cancel', { runId: b }), 'success');
  assert.equal(c.cancelled[0], received[1][6]);
  assert.notEqual(c.cancelled[0], received[0][6]);
  resolvers[1]({ ...outcome, exitCode: 130 });
  resolvers[0](outcome);
  await tick();
  assert.equal(event(first, 'success').value.exitCode, 7);
  assert.equal(event(second, 'success').value.exitCode, 130);
  assert.equal(new Set(c.freed).size, 2);
});
test('pre-submission cancellation targets the token later passed to native', async () => {
  const received = [];
  const c = controlled((...args) => { received.push(args); return Promise.resolve(outcome); });
  const h = harness(c.native);
  const id = event(h.invoke('prepareRun'), 'success').value;
  event(h.invoke('cancel', { runId: id }), 'success');
  assert.equal(c.freed.length, 0, 'A token must live until the queued execution completes');
  const result = h.invoke('run', { source: '', runId: id });
  await tick();
  event(result, 'success');
  assert.equal(received[0][6], c.cancelled[0]);
  assert.equal(c.freed.length, 1);
});
test('unknown run handle is rejected without submitting native work', () => {
  let submitted = 0;
  const c = controlled(() => { ++submitted; return Promise.resolve(outcome); });
  event(harness(c.native).invoke('run', { source: '', runId: 'missing' }), 'error');
  assert.equal(submitted, 0);
  assert.equal(c.freed.length, 0);
});
test('failed token allocation returns a channel error', () => {
  const c = controlled(() => Promise.resolve(outcome));
  c.native.createCancel = () => 0;
  event(harness(c.native).invoke('prepareRun'), 'error');
  assert.equal(c.freed.length, 0);
});
test('unsupported method completes as not implemented', () => {
  event(harness(undefined).invoke('unsupported'), 'notImplemented');
});
test('source/input/heap/paths arrive unchanged and syntax checking cannot execute', async () => {
  const received = [];
  const c = controlled((...args) => { received.push(args); return Promise.resolve(outcome); });
  const args = { source: "print('中文😀')", stdin: 'Ada\n第二行\n', heapKb: 8192,
    projectPath: '/data/projects/中文 space', entryFile: '/data/projects/中文 space/src/main.py' };
  const h = harness(c.native);
  const result = h.invoke('checkSyntax', args);
  await tick();
  event(result, 'success');
  assert.deepEqual(received[0].slice(0, 6), [args.source, args.stdin, args.heapKb,
    args.projectPath, args.entryFile, true]);
});
test('compile/bytecode routing retains paths after a real fixture source is removed', async () => {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'qfli-ohos-channel-'));
  try {
    const entry = path.join(fixture, 'main.py');
    const artifact = path.join(fixture, 'main.mpy');
    fs.writeFileSync(entry, "print('artifact')");
    const received = [];
    const c = controlled((...args) => { received.push(args); return Promise.resolve(outcome); });
    const h = harness(c.native);
    const compiled = h.invoke('compile', { source: fs.readFileSync(entry, 'utf8'),
      artifactOutput: artifact, projectPath: fixture, entryFile: entry });
    await tick();
    event(compiled, 'success');
    fs.rmSync(entry);
    assert.equal(fs.existsSync(entry), false);
    const executed = h.invoke('run', { source: '', bytecodeFile: artifact,
      projectPath: fixture, entryFile: artifact });
    await tick();
    event(executed, 'success');
    assert.equal(received[0][5], true);
    assert.equal(received[0][7], artifact);
    assert.equal(received[1][0], '');
    assert.equal(received[1][5], false);
    assert.equal(received[1][8], artifact);
    // The native double does not create or execute bytecode. This tests routing only.
  } finally { fs.rmSync(fixture, { recursive: true, force: true }); }
});
test('native invalid-argument failures always release their claimed sessions', async () => {
  // Validation itself is owned by C++ and is checked by native/device gates.
  // Here the native double rejects malformed values to prove channel error cleanup.
  const malformed = [
    { source: 'one\0two' }, { stdin: 'one\0two' },
    { projectPath: '/project\0hidden' }, { entryFile: '/project/main.py\0hidden' },
    { artifactOutput: '/project/main.mpy\0hidden' },
    { bytecodeFile: '/project/main.mpy\0hidden' },
    { heapKb: -1 }, { heapKb: 0.5 }, { heapKb: NaN },
    { heapKb: Infinity }, { heapKb: 2147483648 }, { source: 42 },
  ];
  const parameterIndex = { source: 0, stdin: 1, heapKb: 2, projectPath: 3,
    entryFile: 4, artifactOutput: 7, bytecodeFile: 8 };
  for (const invalid of malformed) {
    const [field, value] = Object.entries(invalid)[0];
    const c = controlled((...args) => {
      assert.ok(Object.is(args[parameterIndex[field]], value),
        `The channel changed the ${field} argument before native validation`);
      throw new Error('INVALID_ARGUMENT');
    });
    const h = harness(c.native);
    const id = event(h.invoke('prepareRun'), 'success').value;
    const result = h.invoke('run', { source: '', runId: id, ...invalid });
    await tick();
    assert.equal(event(result, 'error').message, 'INVALID_ARGUMENT', JSON.stringify(invalid));
    assert.equal(c.freed.length, 1, JSON.stringify(invalid));
    assert.equal(event(h.invoke('cancel', { runId: id }), 'success').value, false);
  }
});

(async () => {
  process.stdout.write(`SDK TypeScript: ${location}\n`);
  let failed = 0;
  for (const item of tests) {
    try { await item.action(); process.stdout.write(`PASS ${item.name}\n`); }
    catch (error) { ++failed; process.stdout.write(`FAIL ${item.name}: ${error.stack || error}\n`); }
  }
  process.stdout.write(`RESULT ${tests.length - failed}/${tests.length}\n`);
  process.exitCode = failed ? 1 : 0;
})().catch(error => { process.stderr.write(`${error.stack || error}\n`); process.exitCode = 1; });
