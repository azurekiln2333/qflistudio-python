# Product debugger adapter

## Ownership and behavior boundary

The product had a real native debugger ABI but no `StudioDebugger` provider.
This batch maps that ABI into C's shared `debug_session.dart` contract without
adding shared-core UI or another debugger API. Native sources/builds remain
owned by the native worker. The root coordinator owns content audits and OHOS
EntryAbility/offline policy.

Owned files are `lib/python_debugger.dart`, `lib/python_debugger_ffi.dart`,
`lib/python_native_library.dart`, debugger-focused tests, the existing FFI
loader extraction, and only the debugger import/registration in `lib/main.dart`.
Other analyzer/tools/profile edits are preserved. The loader extraction keeps
desktop and Apple search order unchanged; normal mobile Run still uses channels.
Debugger mobile transport opens packaged `libqfli_py.so` directly and calls its
default-visible C ABI from Dart FFI. Execution runs on a separate isolate while
owner-isolate poll/control calls remain nonblocking. Android/OHOS packaged loader
and installed acceptance remain separate gates.

## Implemented mapping

- Live atomic breakpoint replacement; path validation/containment resolves
  filesystem aliases. Accepted lines stay pending until an actual native hit.
- Entry stop, resume, step into/over/out, actual stack/locals, current pause
  generations and explicit rejection of foreign/stale tokens and threads.
- No asynchronous Pause or unsaved document snapshots. Nonempty documents
  are rejected with a save requirement; there is no stale-disk fallback.
- Immutable full replacement snapshots with local increasing revisions.
  Output arrives only when native execute returns. No terminal phase, `done`,
  stop/dispose completion or VM lease release before actual worker cleanup.
- Event decoding validates schema/session/order/types at the transport boundary.
  Malformed data requests Stop while retaining the lease until actual exit.
- Native values are copied without invoking user representation hooks; class
  and bytecode locals are explicitly unavailable when native metadata is absent.
  Dictionary children preserve actual key/value pairs. Cycles and unbound
  locals carry reasons rather than pretending their children/values exist.
  Dynamically keyed module globals may have empty or NUL-containing names;
  those legal copied names are preserved rather than treated as corrupt data.
- Limits: 128 breakpoints, 16 frames, 64 variables/frame, four children per
  container, two native container levels, 256 code units per shown name/value,
  256 Ki stdout, 64 Ki stderr, 8 Ki diagnostic text. UTF-16 truncation preserves
  surrogate pairs. Native's combined truncation flag marks both streams.
- Cleanup failures retain the lease and `stopping`; Stop and repeated dispose
  can retry cleanup, and no terminal completion is manufactured.
- A failed Stop dispatch is retryable. While actual exit remains pending, a
  200 ms timer retries only rejected/throwing Stop calls. Successful dispatch
  cancels retries. This also recovers protocol-error Stop failures while the
  shared UI is already waiting for termination. Real exit cancels all timers.
- Scoped `ffi.using` arenas own FFI argument/result storage, including partial
  allocation failures. Native-owned output/error buffers use `result_free`.

## Validation status

Root's serialized current focused window passed 28/28 tests: 11 protocol adapter
regressions, four actual-FFI debugger scenarios, and 13 content-audit cases.
Actual FFI proved entry/all steps/breakpoint before file effects, imported Unicode
paths, Stop while paused/running with subsequent normal Run, and inspection that
does not invoke custom representation hooks. Native owner released Windows DLL SHA256
`52e7400fdcd50cb03d94026ad6331c3b27770e2795e3418259d54e4d3a79a54e`;
28 native cases passed separately. Logs: `build/python-current-focused-tests.log`
and `build/python-current-focused-analyze.log`. That analysis found six adapter
test lint infos, now fixed in source.

After that window, source review found nonretryable failed Stop dispatch and
cached disposal preventing cleanup retries. Both are corrected, four additional
meaningful regressions were added, and FFI partial allocations now use arenas.
Those changes have NOT yet run tests/analyzer. The next serialized window must
run all 15 protocol tests plus the four real-FFI tests and scoped analysis.
All six adapter INFO fixes from the previous window are authored. After the
October 24 host restriction no Dart/Flutter/analyzer/test/build/device process
was started by this worker. The final small name/diagnostic-bound changes need
formatter verification in that next named window as well.

No installed OHOS debugger acceptance is claimed by this document.
