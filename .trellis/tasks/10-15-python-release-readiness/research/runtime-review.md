# Independent runtime review

## Initial p5 rev2 status (2026-10-15)

Owner `wA:p5` completed all four findings. `build/runtime-review/bridge-review.cjs` now
reports **7/7 PASS** (was 5/7). Review round 2 (int-double validation, malformed-result
throw, NUL/heap self-check) is also done; the reviewer's real handler suite
`node native/tests/ohos_channel_test.cjs` reports **19/19 PASS**. Full details in
`research/runtime-wA-p5-completion.md`. `test/python_ohos_bridge_test.dart` is reduced
to the byte-identical-copy test only. For finding 4, the terminal owner can now call:

```dart
final PythonRuntimeInfo info = await const PythonProgramRunner().runtimeInfo();
// info.available, info.version (e.g. '1.24.1 (ecfdd5d)'), info.detail,
// info.supportsCancellation, info.supportsArtifacts, info.transport
```

`runtimeInfo()` reuses the real `available` probe (no copied logic); it is not a mock
and needs no version constant. Terminal owner should use it instead of a hardcoded
run-title claim.

## Scope and evidence

- Reviewer cwd: `D:/MyNewProjects/qfli_python`; active task: `10-15-python-release-readiness`.
- Reviewed `native/src/qfli_py_napi.cpp`, both `QfliPyNative.ets` copies, the controlled C API and cancellation primitive, `lib/python_runner.dart`, and the terminal delegate integration.
- The implementation remains owned by Pi `wA:p5`; findings were sent to the coordinator before any overlapping write. This reviewer does not stage or commit code and does not edit sibling apps/core.
- Findings retain the initial failure context; the final reviewed state and follow-up verification are recorded below.

## Concrete findings sent to the owner

1. **Legacy synchronous native results never complete the channel.** `nativeRunControlReady()` correctly returns false for an old SO, but `runNative()` is only declared to return a Promise; it directly returns the old native object. The method handler unconditionally calls `.then()`, throws `TypeError`, and never sends a Flutter result. Normalize old synchronous results with an async wrapper (or an explicit Promise) while retaining its real output/exit code.
2. **A synchronous NAPI throw escapes cleanup.** After marking the session submitted, the handler calls `runNative()` outside a try block. A synchronous throw occurs before `.catch()` exists, so the token stays registered and the Flutter call stays unresolved. Normalize synchronous exceptions into the Promise rejection path and release the claimed session exactly once.
3. **NAPI argument validation differs from FFI/JNI.** `GetStringArg()` accepts embedded NUL, then `Execute()` passes `.c_str()` to the C API. A source or `input.txt` containing NUL is silently truncated on OHOS; paths/artifact destinations have the same issue at the native boundary. Optional argument conversion failures are ignored, and `napi_get_value_int32()` coerces/wraps invalid heap values. Reject embedded NUL, wrong types, non-integral/nonfinite/out-of-range heap values before queuing. Preserve omission defaults for legacy optional parameters.
4. **Terminal version diagnostic became stale.** `lib/python_terminal.dart` tells users a run title shows the real SO version, while the new runner title deliberately contains only `python <relative path>`. The diagnostic must describe an available version surface accurately or use a real probe. This is assigned to the terminal owner through the coordinator.

## Executed channel reproducer

Command from the Python repository:

```powershell
node build/runtime-review/bridge-review.cjs
```

The ignored scratch harness loads the actual packaged ETS source, strips imports and the startup self-check call, transpiles using the locally installed SDK TypeScript compiler, and invokes the actual registered method handler with isolated platform/NAPI doubles. It does not replace the handler with a copied implementation.

Initial result: **5/7 passed; 2/7 failed**.

| Scenario | Initial result |
| --- | --- |
| Legacy synchronous result completes channel | Fail: `runNative(...).then is not a function` |
| Synchronous native throw reports failure and releases token | Fail: uncaught `native sync failure` |
| Async native rejection reports failure and releases token | Pass |
| Success preserves stdout/stderr/exit/truncation; late stop is harmless | Pass |
| Duplicate submission does not claim/free the active token twice | Pass |
| Separate queued sessions retain separate cancellation tokens | Pass |
| Compile and bytecode paths reach the corresponding native arguments | Pass |

This proves handler behavior only. It is not ArkTS type-checking, native VM execution, real worker scheduling, platform build success, or device cancellation evidence.

## Ownership and lifetime assessment

- ArkTS MethodChannel callbacks and Promise completion callbacks share the platform event thread. Session lookup, submitted-state changes, cancellation calls, map removal and token free are therefore serialized within this environment.
- Native work copies the input strings into `RunWork` before queuing; no JS handles are accessed on the worker. The C runtime mutex serializes global VM state. Queued cancellation signals the target token, and C checks it after obtaining its lock.
- On the successful asynchronous path, `Complete()` creates JS-owned strings, resolves the Promise, frees the C output/error buffers, deletes async work and deletes `RunWork`. ArkTS later frees the token after the worker is finished. Late cancellation sees no map entry.
- The initial tests in `test/python_ohos_bridge_test.dart` inspected source tokens and copy equality. They did not catch either reproduced handler failure; do not cite those static tests as behavior or native execution proof. The owner subsequently retained only the copy-equality test.
- The current OHOS startup self-check has 17 legacy cases plus separate loop cancellation and artifact compile/run checks. The artifact check uses the source text passed in memory; it does not itself demonstrate removal of an on-disk source file. The existing actual native lifecycle suite provides stronger source-removal coverage on the host; final OHOS device results must be recorded separately.

## Maintained behavior harness

The coordinator authorized promoting the reproducer into:

```powershell
node native/tests/ohos_channel_test.cjs
```

The command resolves repository paths relative to the script, so it can run from any cwd. TypeScript discovery uses an explicit `QFLI_ARKTS_TYPESCRIPT` package/JS-file override first, then existing SDK environment/local.properties paths and known DevEco installations. It does not install dependencies or access the network. Set the override when using a different SDK layout.

The maintained harness additionally covers missing/partial/full capability exports, pre-submission stop, stale handles, failed allocation, unknown methods, source/stdin/heap/Unicode/path preservation, artifact routing after removal of a real source fixture, and channel cleanup when native argument validation rejects NUL/invalid heap/type values. Native rejection is deliberately doubled: those cases prove argument preservation and transport cleanup, not C++ validation itself. The fixture test does not create or execute actual `.mpy`; the real native lifecycle suite and final device tests own that evidence.

An intermediate run after the first two fixes passed **18/18** groups. A nineteenth group checks that malformed fulfilled native results are transport failures rather than fabricated script exits. The twentieth group checks direct `prepareRun` rejection with partial cancellation exports. The final reviewed result is **20/20**.

Recommendation for the separate `test/python_ohos_bridge_test.dart`: keep the automatic Flutter byte-parity assertion and replace the broad source-contains assertions with this actual handler behavior suite. Merely finding `createCancel` or `napi_queue_async_work` text does not verify reachable behavior or ownership.

## Final review result

After the coordinator confirmed the implementation was ready, the maintained handler suite passed **19/19** groups. The explicit compiler-file override was also exercised from `native/tests/` as the working directory, confirming that compiler override and repository path resolution work independently of the caller's cwd. The follow-up review of changes since commit `77f46d5` then passed the expanded **20/20** suite.

- Final ETS copies: SHA256 `65FEF0F8F32677FCBC2363FC6BA6E611A2493C321910310D58216EB67CB70BCF` (both identical).
- `node --check native/tests/ohos_channel_test.cjs`: pass.
- `node native/tests/ohos_channel_test.cjs`: 20/20 pass on the final reviewed snapshot.
- `git diff --check` on NAPI, both ETS copies and the runner: pass.
- `dart analyze lib/python_runner.dart lib/python_terminal.dart test/python_ohos_bridge_test.dart`: pass, no issues, exit 0.
- The coordinator's final full analyzer log `build/python-final-analyze.log` was read and reports `No issues found!`; the coordinator separately reported 88/88 full-app tests passing with the real DLL present. This reviewer did not duplicate the app test run.
- The owner reduced `test/python_ohos_bridge_test.dart` to the independent byte-parity assertion as recommended.

The initial four concrete findings are resolved in the reviewed source. The async ArkTS wrapper normalizes old synchronous results, converts synchronous throws into rejected Promises and rejects malformed outcomes. NAPI checks all supplied string/type conversions and rejects actual NUL. Heap conversion now explicitly checks a finite, integral number in `[0, INT32_MAX]`; tokens must be finite, integral, nonnegative JS safe integers. Terminal `--version` now uses `PythonProgramRunner.runtimeInfo()` and the actual backend probe instead of promising a version-bearing title.

No outstanding normal-path defect was found in token ownership, queue isolation, worker-to-platform handoff, artifact argument routing, relative run labels, or native stdout/stderr/exit/truncation propagation. This is a source/handler verdict; the coordinator's actual native/build/device gates remain authoritative.

## Follow-up robustness review since `77f46d5`

Both previously recorded robustness notes are now resolved:

- `Run()` owns its not-yet-queued `RunWork` with `std::unique_ptr`. Argument-validation, Promise-creation, async-work creation and queue-failure exits therefore release the context and its strings. Ownership is transferred with `release()` only after `napi_queue_async_work` succeeds; the existing `Complete()` remains the sole owner after queuing and frees native buffers, work handle and context. Completion runs on the event-loop thread, so it cannot race the final ownership transfer within the submitting callback.
- Context allocation catches `std::bad_alloc` and raises a JS error; argument-string allocation also catches `std::bad_alloc`. Invalid-argument cleanup preserves the specific pending JS TypeError/RangeError. Source review confirms that these C++ exceptions do not escape the `Run` NAPI boundary. Allocation-failure fault injection was not performed, so this is source/compiler evidence for the exceptional allocation path.
- `prepareRun()` now invokes the same complete-export `nativeRunControlReady()` predicate used by the capability probe before calling `createCancel`. Missing create/cancel/free exports cannot create a session through that path. The new behavior case confirms direct-call rejection for each missing export; source inspection confirms the guard precedes allocation.

Follow-up checks run by this reviewer: Node syntax check, actual-handler **20/20**, identical ETS hashes above, and `git diff --check 77f46d5` for NAPI/both bridges/harness all pass. Only this report was edited during the follow-up review; no app tests or builds were duplicated.

P5's successful native compile was independently confirmed from `native/build/cmake-arm64-v8a/build.log`: the current `qfli_py_napi.cpp` compiled, `libqfli_py.so` linked, and the dependency scan passed with only `libace_napi.z.so`, `libhilog_ndk.z.so`, and `libc.so`. The built SO is **2,523,880 bytes**, written at `2026-10-15 19:26:45`, after the reviewed NAPI source at `19:25:58`. The coordinator owns copying this latest library and rebuilding/reinstalling the corresponding final HAP.

No unfixed finding remains from this review. The raw native token remains a trusted pointer owned by the ArkTS registry; numeric shape checking is not an authentication mechanism or an untrusted-code security boundary, as documented in source.

## Remaining external gates

- Coordinator owns native/OHOS/Android builds and device execution. No platform pass is inferred from this source review.
- Update the native runtime spec's outdated assertion that OHOS retains only the legacy channel once the current bridge is built and verified.

Coordinator evidence received at review completion: the final full analyzer exited clean (`build/python-final-analyze.log`, 11.0 seconds); the app test suite passed 88/88 with the actual DLL; the rebuilt OHOS release HAP was signed, built and installed successfully. Device launch returned `10106102` while the device was locked. The coordinator requested a normal user unlock and is waiting; no OHOS execution/self-check pass is claimed here. Expected HAP artifact: `ohos/entry/build/default/outputs/default/entry-default-signed.hap`.

Pi p6 had one further terminal edge correction pending at the initial review: root selection for an unmarked nested file should use the terminal cwd as its fallback. The coordinator owns the resulting final single app-suite/build rerun. The **20/20** handler verdict covers the final reviewed native bridge; scoped Dart analyzer and 88/88 app evidence above identify the earlier snapshot validated before the p6 correction and the latest native robustness change.
