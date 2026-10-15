# wA:p5 runtime + OHOS bridge completion record

Worker: pi `wA:p5`, cwd `D:/MyNewProjects/qfli_python`, active task
`10-15-python-release-readiness`. This records the review fixes and the terminal-title
work, with the exact evidence and the remaining owner boundaries.

## Owned paths changed

| Path | Change |
| --- | --- |
| `lib/python_runner.dart` | Command-style title `python <project-relative path>`; public `runtimeInfo()` + `PythonRuntimeInfo`; `.mpy` always routes through the controlled path. |
| `native/src/qfli_py_napi.cpp` | Async NAPI worker + Promise, cancellation token exports, artifact/bytecode args, strict argument validation matching FFI/JNI. |
| `native/ohos/QfliPyNative.ets` + `ohos/entry/.../plugins/QfliPyNative.ets` | Full channel parity: `available{runControl,bytecode}`, `prepareRun`, `cancel`, `run`/`checkSyntax`/`compile`; async/Promise normalization; session release on all paths; self-check for stop + bytecode. Byte-identical copies. |
| `test/python_app_test.dart` | Title contract, `.mpy` routing, `runtimeInfo` coverage. |
| `test/python_ohos_bridge_test.dart` | New static contract test (hash sync, channel protocol, NAPI exports/validation). |

Not touched: `lib/main.dart`, initial dirty OHOS EntryAbility/routes/icons, shared core,
shared C (`qfli_py_bridge.c/h`, `qfli_py_ffi.c`, HAL, file, stdio, JNI), other languages.

## Review findings resolved (reviewer harness `build/runtime-review/bridge-review.cjs`)

Initial: 5/7. After fixes: **7/7 PASS**.

1. Legacy synchronous native result never completed the channel → `runNative` is now an
   `async` function using `await Promise.resolve(run(...))`, so a bare object or a
   Promise both normalize to a resolved Promise.
2. Synchronous NAPI throw escaped cleanup → `async` converts sync throws to rejections;
   the handler `.catch` releases the claimed session and sends `result.error`.
   `releaseRun` is idempotent, so `.then`+`.catch` cannot double-free.
3. NAPI validation differed from FFI/JNI → `GetStringArg` rejects embedded NUL,
   `GetIntArg` reads int64 and enforces int32 range, and every supplied optional
   argument is validated (omitted ones keep defaults).
4. Stale terminal version diagnostic → `PythonRuntimeInfo` + `runtimeInfo()` expose the
   real `available` version/capabilities for the terminal owner (no copied probe logic).

Also fixed realm-sensitive error text: `errorText()` duck-types `.message` instead of
`instanceof Error` (cross-realm/native errors).

## Evidence (executed)

- `node native/tests/ohos_channel_test.cjs` (reviewer's real handler-behavior suite)
  → **19/19 PASS**. This replaced the source-`contains` assertions in
  `test/python_ohos_bridge_test.dart`, which now keeps only the byte-identical-copy
  filesystem fact.
- Host-executed NAPI validation boundary check
  (`build/runtime-review/napi_validate_check.cpp`, compiled with WSL g++):
  `VALIDATION OK` — heap rejects `-1, 0.5, 2^31, NaN, Infinity` and accepts
  `0, 8192, INT32_MAX`; token rejects `0.5, NaN, Infinity, 2^53` and accepts small ints.
- `flutter test test/python_ohos_bridge_test.dart test/python_app_test.dart test/python_tools_page_test.dart test/python_lifecycle_test.dart test/python_ffi_test.dart`
  → **56/56 passed**, including real Windows `qfli_py_ffi.dll` compile/run/stop/artifact.
- `flutter analyze lib/python_runner.dart test/python_ohos_bridge_test.dart test/python_app_test.dart`
  → No issues.
- ArkTS copies SHA256 `640EBFB5...` identical.
- NAPI compile verified: `native/build.ps1 -SkipCopy` → `[1/2] qfli_py_napi.cpp.o`,
  `[2/2] Linking libqfli_py.so`, `check_so_deps` OK (only `libace_napi.z.so`,
  `libhilog_ndk.z.so`, `libc.so`). `-SkipCopy` was used so the packaged `.so` copy is
  left to the coordinator's fresh `native/build.ps1`.

## Review round 2 resolved

1. `GetIntArg` now reads `napi_get_value_double`, rejects non-finite/fractional/negative
   values, and enforces `0..INT32_MAX` (was: int64 cast then a range check that still
   truncated fractions/NaN and allowed negatives). `GetInt64Arg` (token) now enforces a
   finite integer within the JS safe-integer range.
2. ArkTS `runNative` no longer fabricates `exitCode: -1` for a malformed native result;
   it throws so the handler `.catch` maps it to a transport failure (`result.error`).
3. `selfCheck()` gained a parameter-validation block asserting real NUL in
   source/stdin/entryFile and illegal heap (`-1`, `0.5`, `2^31`) are rejected, followed
   by a valid run to prove no state corruption. Device verification via hilog.
4. `test/python_ohos_bridge_test.dart` reduced to the two-file byte-identity test;
   behavior is covered by `native/tests/ohos_channel_test.cjs`.

## Review round 3 (final) resolved

- `GetInt64Arg` (token) now accepts only finite, integral, **non-negative** values in the
  JS safe-integer range. Comment corrected: the token is dereferenced by
  `qfli_py_execute` / `qfli_py_cancel_request` / `qfli_py_cancel_free`, so this is
  documented as minimum malformed-input defense for trusted ArkTS-registry tokens,
  not a security boundary. Negative values are rejected.
- Host-executed boundary check re-run with negative-token cases (`-1`, `-100`):
  `VALIDATION OK`.

## Freeze status (2026-10-15)

Owner scope is frozen. Final: `ohos_channel_test.cjs` **20/20**; Dart focused
**56/56**; `flutter analyze` on owner files clean; ArkTS copies identical
(`65FEF0F8...`); NAPI compiles/links with `check_so_deps` OK; shared C untouched.
Ready for the coordinator's `native/build.ps1` + signed HAP + device self-check.

## Review round 4 (final closure) resolved

- `prepareRun` now gates on the full `nativeRunControlReady()` (create + cancel +
  free) before allocating a token; it no longer passes with a partial adapter, so it
  cannot register a session that can never be cancelled or freed.
- NAPI `Run` holds the not-yet-queued `RunWork` in a `std::unique_ptr`, `release()`d only
  after a successful `napi_queue_async_work`; `new`/string `std::bad_alloc` is converted
  to a JS error instead of crossing the NAPI boundary. No shared C/ABI change.
- Harness gained one case: a partial cancellation module rejects a direct `prepareRun`
  and performs no allocation/free/cancel. No other refactor.

## Not verified by me (owner gates)

- Real OHOS device execution of the async NAPI worker / cancellation / `.mpy`: needs the
  coordinator's fresh `native/build.ps1` + signed HAP install. `hdc list targets` shows
  `192.168.68.207:46551`, but shared devices are not mine to disturb.
- Full `flutter test` / `flutter analyze` are blocked by a concurrent peer edit leaving
  `qfli_studio_core/lib/editor/editor_page.dart` uncompilable (`Expected 'else' or comma`
  at 1605) and by p6's injected-runner fix for `test/offline_regression_test.dart`. Only
  owner-scoped tests were run, per coordinator instruction.

## Terminal title task (10-09 R3/R5)

- Both controlled and legacy paths now return `python <relative path>`; `.mpy` uses the
  same contract; spaces/nested paths are single-quoted; no version suffix, no Chinese
  success prose. Shared core already provides the inline prompt (R2) and tap/hold run
  gestures (R4); no shared-core edit was needed.
