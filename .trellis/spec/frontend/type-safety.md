# Dart and Native Boundary Type Safety

## 1. Scope / Trigger

Use for result types, channel payloads, FFI or transport changes. This app uses
null-safe Dart/Flutter APIs, not TypeScript or web schema-validation libraries.

## 2. Existing Types

- `PythonNativeTransport { automatic, methodChannel, ffi }` uses an exhaustive
  transport-selection switch.
- `PythonSyntaxResult`: success/error/version; `PythonCompilationResult` adds
  artifactPath.
- Shared `ProgramRunResult`: streams, exitCode and optional cancel.
- `PythonFfiExecution`: `Future<Map<String, Object?>>` and cancel;
  `PythonFfiException`: typed code/message.
- `_NativeResult extends Struct`: `@Int32()` fields and `Pointer<Utf8>` strings.
  Native FFI typedefs have corresponding Dart signatures.

## 3. Contracts

- Widgets consume typed operations/results. Raw maps and pointers stay inside
  runner/FFI adapters, which own decoding.
- Receive platform data as `Object?`, then validate map and integer exitCode.
  Optional capabilities require `== true`; absent fields do not advertise
  support. Preserve legacy boolean availability probes.
- Preserve nullable meanings: null run is unclaimed, optional cancel means no
  handle, and native error may be null. None implies empty success.
- Native strings use UTF-8. FFI rejects embedded NUL/invalid heap integer ranges
  before marshalling; JNI uses UTF-8 byte arrays, not modified-UTF-8 APIs.
  Keep C layout/signatures synchronized with all adapters.
- Submit actual paths. Display labels are presentation and must not be parsed
  into executable shell commands.
- `path` and `ffi` are direct dependencies. Declare packages directly imported
  here rather than relying on the core's transitive dependency graph.

## 4. Validation & Error Matrix

| Input/result | Interpretation |
| --- | --- |
| Missing/non-integer exitCode | Invalid result / not-run status |
| Old bool probe | Available only for true; optional capabilities false |
| Null native error | No diagnostic text added |
| Absent/false capability | Gate operation or explicit unsupported result |
| Embedded NUL / oversized FFI int | Reject before native invocation |

## 5. Good / Base / Bad Cases

- Good: a widget displays the compilation result's artifact path.
- Base: valid results preserve integer exit and separate text streams.
- Bad: dynamic casts throughout UI, invalid exits defaulted to zero, or ordinary
  UTF-8 passed to JNI's modified-UTF-8 constructor.

## 6. Tests Required

`test/python_app_test.dart` covers malformed results, legacy probes and payloads.
`test/python_ffi_test.dart` covers NUL/integer rejection and loader errors.
Real C/FFI checks establish Unicode/path/ABI behavior; the analyzer alone cannot
prove layouts or marshalling. Read [Python FFI](../backend/python-ffi.md).

## 7. Wrong vs Correct

```dart
// Wrong: an absent capability advertises support.
final supportsArtifacts = raw['bytecode'] != false;
// Correct: only explicit capability enables it.
final supportsArtifacts = raw['bytecode'] == true;
```

References: [runner](../../../lib/python_runner.dart),
[FFI types/validation](../../../lib/python_ffi.dart),
[C ABI](../../../native/src/qfli_py_bridge.h).
