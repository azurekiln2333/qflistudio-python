# Python snapshot diagnostics and VM activity implementation

Date: 2026-10-22. Owner: `implement_python_analyzer`. No shared-core,
profile/main, UI, native/generated, assets or staging/commit writes.

## Delivered interfaces and behavior

- `const PythonCodeAnalyzer({this.runner = const PythonProgramRunner()})`
  implements the frozen core `CodeAnalyzer` interface. Root can register the
  constant provider on `pythonProfile` without changing core.
- Analyze the active snapshot first, then other captured project-owned `.py`
  buffers. Never reread their disk contents. Reject missing/obsolete/conflicting
  active snapshots, foreign buffers and unsupported active language/file types.
  Each compilation receives exact text including Unicode and CRLF.
- Only actual native `SyntaxError`/`IndentationError` with a matching absolute
  file and an existing source line becomes a diagnostic. Its half-open UTF-16
  range covers the full line, excludes the newline and may be an empty EOF
  insertion point. No inferred token column, undefined-name or import analysis.
- `PythonSyntaxResult.unavailableReason` separates compiler availability from
  syntax failure. Busy, missing/malformed/truncated native responses, unexpected
  output, cancellation and unlocated operational failures remain unavailable.
  No unsuccessful empty result is reported as clean code.
- `PythonRuntimeActivity.shared` is the default app-isolate gate across runner
  instances. `tryAcquire(PythonRuntimeOperation)` never queues. Operation values
  are `run`, `compile`, `analysis`, `debug`; a lease has idempotent `release()`.
  An optional runner `runtimeActivity` supports tests or a deliberately shared
  owner. Ordinary app integrations should use the shared default.
- Run/compile/check acquire before the first asynchronous capability probe and
  run retains ownership during bundle preparation. Controlled-run results wrap
  `exitCode` so early handles and cancellation requests retain the lease until
  the real backend completion. All early-failure and final-exit paths release.
  ProgramRunResult and native run ABI are unchanged.

## Checks

Final focused command passed **87/87, zero skips**:

```text
flutter test --no-pub --concurrency=1 test/python_code_analyzer_test.dart test/python_runtime_activity_test.dart test/python_source_check_test.dart test/python_lifecycle_test.dart test/python_app_test.dart test/python_package_runtime_test.dart test/python_module_imports_test.dart
```

The two new test files contribute 20 analyzer and eight activity tests. They
include actual DLL checks for unsaved Unicode/CRLF error ranges, valid code
containing file-write/input/import side effects without execution or writes,
and a genuinely running infinite loop which rejects checks promptly, cancels
and permits subsequent valid analysis. Existing real lifecycle, package and
automatic-import tests remain passing. MethodChannel tests separately verify
late native exit, cancellation which has not yet completed, malformed/throwing
completion, capability-probe/preparation races and failure recovery.

Actual runtime: `native/build/windows/qfli_py_ffi.dll`, SHA256
`2329ef7d374e35dd5159db0f3f056b094effc9a0372ad29fe704af472a6c309f`.

Targeted `flutter analyze --no-pub` on all five owned Dart/test files passed
without issues. `dart format` passed; owned tracked diff whitespace check passed.

## Remaining integration gates

- Root owns profile registration, full app checks, UI and OHOS verification.
  These host checks do not establish installed OHOS editor behavior.
- Core owns debounce, disposal and stale-response rejection against exact
  snapshots. This adapter retains no mutable request or document cache; a later
  request checks its own immutable text and rejects busy work rather than
  queueing it behind a running program.
- The shared activity gate coordinates the app Dart isolate, not direct C/FFI
  callers from other isolates or startup/platform self-checks. The native mutex
  remains authoritative for those. If ordinary production paths bypass the
  runner while editing, root must route them through this gate or coordinate a
  native nonblocking analysis entry before claiming that broader guarantee.
- Future debugger integration must retain a shared `debug` lease until the real
  native session settles, including stop while paused.

## Owned files

`lib/python_runner.dart`, `lib/python_code_analyzer.dart`,
`lib/python_runtime_activity.dart`, `test/python_code_analyzer_test.dart`,
`test/python_runtime_activity_test.dart`, and this evidence note.
