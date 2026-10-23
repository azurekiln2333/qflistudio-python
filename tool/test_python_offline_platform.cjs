#!/usr/bin/env node
'use strict';

// Execute the real EntryAbility handlers with local platform doubles. This is
// behavioral host evidence, separate from ArkTS checking and installed OHOS.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const propertiesPath = path.join(root, 'ohos/local.properties');
const properties = fs.existsSync(propertiesPath) ? fs.readFileSync(propertiesPath, 'utf8') : '';
const sdkProperty = /^sdk\.dir\s*=\s*(.+)$/m.exec(properties);
const sdk = process.env.DEVECO_SDK_HOME || process.env.OHOS_SDK_HOME
  || (sdkProperty && sdkProperty[1].trim().replace(/\\([\\: ])/g, '$1'));
const suffix = 'openharmony/ets/build-tools/ets-loader/node_modules/typescript';
const candidates = [process.env.QFLI_ARKTS_TYPESCRIPT,
  sdk && path.join(sdk, 'default', suffix), sdk && path.join(sdk, suffix)]
  .filter(Boolean);
const compiler = candidates.find(candidate => fs.existsSync(candidate));
assert.ok(compiler, 'Use installed SDK TypeScript or QFLI_ARKTS_TYPESCRIPT; no downloads');
const ts = require(path.resolve(compiler));
assert.ok(process.argv.length <= 3,
  'Usage: node tool/test_python_offline_platform.cjs [EntryAbility.ets]');
// An explicit source lets review execute exactly the staged edition without
// requiring unrelated working-tree platform changes to be committed.
const sourcePath = process.argv[2] ? path.resolve(process.argv[2])
  : path.join(root, 'ohos/entry/src/main/ets/entryability/EntryAbility.ets');
const source = fs.readFileSync(sourcePath, 'utf8').replace(/^import[\s\S]*?;\r?$/gm, '');
const compiled = ts.transpileModule(source, {
  fileName: 'EntryAbility.ts', reportDiagnostics: true,
  compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
});
assert.deepEqual((compiled.diagnostics || [])
  .filter(diagnostic => diagnostic.category === ts.DiagnosticCategory.Error), []);

const handlers = new Map();
const observed = { external: [], nativeRegistrations: 0, plugins: 0, shares: [], picker: [], progress: [] };
const external = name => { observed.external.push(name); throw new Error(`Unexpected ${name}`); };
const abilityContext = {
  startAbility: () => external('browser'),
  eventHub: { emit: (...values) => observed.progress.push(values) },
};
const context = {
  exports: {},
  FlutterAbility: class {
    context = abilityContext;
    configureFlutterEngine() {}
  },
  MethodChannel: class {
    constructor(_messenger, name) { this.name = name; }
    setMethodCallHandler(handler) { handlers.set(this.name, handler); }
  },
  GeneratedPluginRegistrant: { registerWith: () => observed.plugins++ },
  registerQfliPyNativeChannel: () => observed.nativeRegistrations++,
  authentication: { HuaweiIDProvider: class { constructor() { external('account'); } } },
  router: { pushUrl: () => external('remote agreement') },
  systemShare: {
    SharedData: class { constructor(record) { this.record = record; } },
    ShareController: class {
      constructor(data) { this.data = data; }
      show() { observed.shares.push(this.data.record); return Promise.resolve(); }
    },
  },
  AppStorage: { setOrCreate() {} },
  isPickerMethod: method => method === 'pickFile',
  handlePickerCall: (_ability, call, result) => {
    observed.picker.push(call.method);
    result.success('local-file');
  },
};
vm.runInNewContext(compiled.outputText, context, { filename: sourcePath });
const ability = new context.exports.default();
ability.configureFlutterEngine({ dartExecutor: { getBinaryMessenger: () => ({}) } });
assert.equal(observed.plugins, 1);
assert.equal(observed.nativeRegistrations, 1);
assert.equal(observed.external.length, 0, 'Engine setup must not invoke a remote entry point');

async function invoke(channel, method, args = {}) {
  const results = [];
  let argumentReads = 0;
  handlers.get(channel).onMethodCall({ method, argument: key => {
    argumentReads++;
    return args[key];
  } }, {
    success: value => results.push({ kind: 'success', value }),
    error: (code, message) => results.push({ kind: 'error', code, message }),
    notImplemented: () => results.push({ kind: 'notImplemented' }),
  });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(results.length, 1, `${method} must complete exactly once`);
  return { ...results[0], argumentReads };
}

(async () => {
  const platform = 'qflistudio/platform';
  for (const url of ['https://example.invalid/privacy', 'http://127.0.0.1:8080',
    'file:///data/local/tmp/example.html', 'custom://action', undefined]) {
    for (const method of ['openUrl', 'openAgreement']) {
      const denied = await invoke(platform, method, { url });
      assert.equal(denied.code, 'OFFLINE_ONLY');
      assert.equal(denied.argumentReads, 0, `${method} must reject before reading arguments`);
    }
  }
  const deniedLogin = await invoke('qflistudio/huawei_account', 'login');
  assert.equal(deniedLogin.code, 'OFFLINE_ONLY');
  assert.equal(deniedLogin.argumentReads, 0);
  assert.deepEqual(observed.external, [], 'Rejected requests must never invoke platform providers');
  assert.equal((await invoke(platform, 'startupProgress', { progress: 1.5 })).kind, 'success');
  assert.deepEqual(observed.progress, [['EVENT_STARTUP_PROGRESS', 1]]);
  assert.equal((await invoke(platform, 'startupProgress', { progress: NaN })).code, 'INVALID_PROGRESS');
  assert.equal((await invoke(platform, 'pickFile')).value, 'local-file');
  assert.deepEqual(observed.picker, ['pickFile']);
  assert.equal((await invoke(platform, 'shareText', { title: 'Code', text: 'print(1)' })).kind, 'success');
  assert.equal(observed.shares[0].content, 'print(1)');
  assert.equal((await invoke(platform, 'unknown')).kind, 'notImplemented');
  assert.equal((await invoke('qflistudio/huawei_account', 'unknown')).kind, 'notImplemented');
  console.log('PASS: real EntryAbility offline refusal, engine setup, progress, picker and local share');
})().catch(error => { console.error(error); process.exitCode = 1; });
