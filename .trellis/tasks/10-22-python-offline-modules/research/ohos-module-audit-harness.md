# Embedded module/package audit harness

Date: 2026-10-22. Worker ownership is limited to the four audit tool/test files
and this note. No native/runner/module asset, shared core, signing/profile,
normal app entry, staging or commit changes were made by this worker.

## Delivered entry and report

- `tool/prepare_python_module_audit.py` verifies bundle manifest digests and
  generates ignored `build/python_module_audit/main.dart`, `suite.g.dart`, and
  `inputs.json`. `native/tests/python_stdlib_smoke.py` remains the single authored
  Python suite; there is no maintained Dart copy of its source.
- `tool/python_module_ohos_audit.dart` uses `PythonProgramRunner` and
  `PythonPackageService` with actual compiler/transport calls. It checks exact
  packaged asset hashes, portable module behavior, repeat preparation mtimes,
  package check/install/list/show/update/remove, compile-only no-execution,
  invalid update rollback, project separation, unmanaged/edited file conflicts,
  cancellation, local ZIP imports, unsupported modules, and automatic import
  precedence from entry/root/lib/bundle. Removed APIs must fail to import;
  MicroPython can still import an empty surviving directory as a namespace.
- The generated app resolves `AppPaths.storageDirectory()` and writes
  `qfli-python-module-audit.json` there after each stage. The expected Python
  bundle is `com.azurekiln.qfli.pyflow`; the usual pull path is
  `/data/app/el2/100/base/com.azurekiln.qfli.pyflow/files/qfli-python-module-audit.json`.
  The UI and `QFLI_PYTHON_MODULE_AUDIT` log include report hash/path. The report
  distinguishes host and installed OHOS gates and labels native hashes as
  declared build inputs, requiring independent HAP binding.
- Deadlines request Stop and wait for actual native completion. Every pending
  operation remains observed. Unsettled operations retain the complete work
  directory, and late handles are cancelled when they arrive. Failed cleanup
  cannot report a successful acceptance gate.

## Reversible emulator HAP build

The coordinator, during the exclusive Python build window, can run:

```powershell
powershell -ExecutionPolicy Bypass -File tool/build_python_ohos_audit.ps1
```

The script consumes the existing staged x86_64 SO, generates fresh audit input,
temporarily changes only the entry ABI/filter selection, and restores the exact
original entry-profile bytes and `JAVA_TOOL_OPTIONS` in `finally`. It never
writes or prints the root signing profile. A root-profile digest verifies that
it remained unchanged. The default report is
`build/python-ohos-audit-build.json`.

It rejects stale signed HAP timestamps, mismatched source/suite/assets/native
input hashes, wrong native ELF machine/class, mixed ABIs, missing Python/Flutter
libraries, and missing app ELF/debug kernel. It checks packaged assets and SO
against the generated input and current staged bytes. SO binding accepts either
the unchanged bytes or an independently reproduced, byte-exact SDK strip
transform as detailed below. SDK `hap-sign-tool.jar
verify-app` must also succeed; signing extraction/output is not printed and
temporary extracted certificate/profile files are removed. There are no
install/start/stop/reset/device commands in this script.

## Verification actually run by worker

- `flutter test --no-pub test/python_module_audit_test.dart`: **6/6 passed**.
  The Windows DLL test executed all **306 portable assertions** and the full
  package/import acceptance flow. Five additional tests cover unavailable
  runtime, suite hash mismatch, settled cancellation, unsettled retention, and
  late-handle cancellation. No host result claimed OHOS acceptance.
- `dart analyze tool/python_module_ohos_audit.dart
  test/python_module_audit_test.dart build/python_module_audit/main.dart
  build/python_module_audit/suite.g.dart`: **no issues**.
- Dart formatting unchanged on final pass; Python preparation and `py_compile`
  passed. A generated Dart-only round trip proved the suite constant has exactly
  the Python source SHA256, including original line endings and dollar signs.
- PowerShell AST parsing passed. Current entry ABI/filter adaptation and SDK
  signature-verifier autodetection were checked **in memory/read-only**.
- No HAP build, installation, device operation or installed OHOS execution was
  performed by this worker. These remain coordinator gates.

Current generated input identity (not a packaged/device proof):

- Suite SHA256: `e178295cd87e5bc7a316298b2ccc60ec4473e3266384508a1cfc31fb13c2e7c0`
- Bundle: `v1`, **10 modules**, **15 assets**.
- Staged x86_64 SO SHA256:
  `78b31d943fe93a63e9de654d95cbec16bc12507e686d79acf5fba41003671717`

The builder regenerates all input hashes immediately before its build; later
coordinator changes must be verified against that fresh generated identity.

## Follow-up: deterministic Hvigor SO stripping

The coordinator's first scoped build succeeded and restored all state, while
the original exact-unstripped-SO comparison rejected the packaged native file.
The original failure report was preserved by the coordinator.

Read-only inspection of the installed primary Hvigor implementation
`hvigor-ohos-plugin/src/tasks/worker/native-strip.js` established its command:

```text
SDK llvm-strip --keep-section=.permission <original SO> -o<separate output SO>
```

There are no additional strip flags. Both installed OpenHarmony and HMS SDK
tools independently produced **819128 bytes**, SHA256
`624107426183dab4fb815cd6eb56843d6eb88272c3e835ee5f8f6f6fc4f50a47`, exactly
matching the extracted HAP library. The staged **2394848-byte** source retained
SHA256 `78b31d943fe93a63e9de654d95cbec16bc12507e686d79acf5fba41003671717`.

`Resolve-PythonNativeBinding` now first requires the exact staged hash/length
recorded by entry generation. If packaged bytes differ, it executes only the
known SDK transform on a separate ignored build output and requires its exact
hash/length to equal the HAP entry. It records all three hashes/lengths, actual
arguments, tool path/hash/version and transform origin. It rechecks the staged
file and strip tool after execution. It never modifies the staged SO.

The updated inspector was exercised against the existing signed HAP without
building or changing profiles: **2 ELF64 x86_64 libraries** and **15 assets**
passed. Deliberately wrong packaged hashes and changed declared staged-input
hashes were both rejected; the unchanged identity path also passed. Evidence:
`build/reports/python-so-strip-binding.json`. No device actions or HAP build
were performed by this worker during this fix. The coordinator reruns the
scoped builder to produce the final restored-state/signature report.
