# Backend Error Handling

## 1. Scope / Trigger

Use for runner, FFI, channel adapters and native results. These are local
execution boundaries; HTTP error envelopes do not apply. VM details belong to
[Native Python Runtime](./native-python-runtime.md).

## 2. Signatures

```dart
Future<ProgramRunResult?> run({required String projectPath, required String entryFile});
class PythonFfiException implements Exception {
  const PythonFfiException(this.code, this.message);
  final String code;
  final String message;
}
```

Native results contain `exitCode`, `output`, `error` and `truncated`.
`ProgramRunResult` exposes streams, exit future and optional cancel.

## 3. Contracts

- Null run means unclaimed extension or missing entry. Claimed Python execution
  failures become visible results.
- Use `kProgramNotRunExitCode` (runner alias `notRunExitCode`) when no valid
  execution result exists. Preserve actual Python exits, including `sys.exit(n)`.
- Validate the result map and integer exit before interpreting completion.
  Missing/malformed results are failures, never exit 0 defaults.
- Keep stdout, explicit stderr and traceback separate from app diagnostics.
  Runner diagnostic lines use `[qfli] `; truncation is visible.
- Preserve `QFLI_PY_MODULE_MISSING` loader detail. MissingPluginException means
  unavailable channel; do not silently swap interpreters.
- Validate FFI arguments before marshalling. Free result/input allocations in
  `finally`, close streams and release execution resources on every exit path.

## 4. Validation & Error Matrix

| Condition | Result |
| --- | --- |
| Uncaught SyntaxError/runtime exception | Native exit 1 plus diagnostic |
| Explicit stderr with successful execution | Keep stderr and exit 0 |
| Cooperative cancellation | Native exit 130 and KeyboardInterrupt |
| Missing library/channel | Probe detail, visible failure and not-run status |
| FFI NUL / integer overflow | PythonFfiException before native invocation |
| Invalid result | Diagnostic and not-run status |

## 5. Good / Base / Bad Cases

- Good: preserve loader cause and allow a subsequent invocation to recover.
- Base: `print(42)` yields stdout and exit 0.
- Bad: turn every stderr string into exit 1 or platform errors into empty success.

## 6. Tests Required

Run `test/python_app_test.dart` for loader/result/exit contracts and
`test/python_ffi_test.dart` for validation/loader errors. Lifecycle tests plus
real native checks establish interruption and recovery. Channel mocks establish
adapter behavior only.

## 7. Wrong vs Correct

```dart
// Wrong: invalid response becomes success.
final exitCode = raw['exitCode'] ?? 0;
// Correct: reject absent/non-integer exit codes.
if (raw is! Map || raw['exitCode'] is! int) {
  return _failure(fileName, '$_appPrefix原生运行时返回了意外的结果。');
}
```

References: [runner](../../../lib/python_runner.dart),
[FFI cleanup](../../../lib/python_ffi.dart),
[JNI ownership](../../../native/src/qfli_py_jni.cpp).
