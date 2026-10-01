# Python FFI Contract

## 1. Scope / Trigger

Apply to `python_ffi.dart`, desktop/Apple native packaging and the shared
Windows file port. The existing native-python-runtime contract still applies
to the engine, JNI/NAPI adapters and output behavior.

## 2. Signatures

```c
void qfli_py_run_into(QfliPyRunResult *result, const char *source,
    const char *stdin_text, int heap_kb, const char *project_dir,
    const char *entry_file, int compile_only);
void qfli_py_result_free(QfliPyRunResult *result);
const char *qfli_py_version(void);
```

`PythonFfiBackend({String? libraryPath}).probe/run/start` uses the controlled
`qfli_py_execute_into` symbol on a worker isolate. `start` returns a result
future and cancel callback immediately. `PythonNativeTransport.automatic` selects FFI on Windows,
Linux, iOS and macOS; Android/OHOS retain their channel adapters. Tests can
explicitly choose either transport.

## 3. Contracts

- FFI owns argument/result storage. The C engine owns output/error buffers;
  free them through its exported function before freeing the result struct.
- Validate source/stdin/project/entry NUL and nonnegative Int32 heap size
  before marshaling. Preserve native errors and the existing not-run status.
- Desktop loader checks runner/lib directories and native/build/<platform>.
  Apple uses process symbols retained by app linker flags. Explicit library
  paths are development/test overrides, never an evaluator fallback.
- Shared C locking serializes all isolate invocations. Every run resets VM
  globals/modules and closes project descriptors, including error paths.
- The owner isolate creates a token, sends only its integer address and request
  data to the worker, and frees it in result completion. Late cancellation is a
  no-op after completion. Never capture FFI bindings or native function pointers
  in the worker closure. Apple app linker flags must retain execute and all
  cancellation exports as well as result_free/version.
- Windows uses OS-native UTF-8 paths, locking, clocks and module readers.
  Both tracked port headers must agree. Do not modify upstream lexer syntax.
- Apple local pods stage compilation units under their pod root; sibling ../
  source globs are insufficient. Compile textual includes only once.

## 4. Validation / Error Matrix

| Condition | Result |
| --- | --- |
| Missing library/symbol | Probe unavailable; run retains QFLI_PY_MODULE_MISSING |
| NUL argument / invalid heap size | INVALID_ARGUMENT before native allocation |
| Syntax check | No Python side effect or project artifact |
| Compilation with artifactOutput | Upstream .mpy written without executing |
| Pending/running stop | Exit 130; previous stdout retained; subsequent run works |
| Concurrent runs | Separate results; serialized C VM state |
| Native exception / explicit exit | Real traceback and exit code preserved |

## 5. Good / Base / Bad

Good: the default runner imports a project helper, reads input.txt and writes
an actual file while retaining stdout/stderr. Base: print(42) returns exit 0.
Bad: a platform channel mock is used as proof that a DLL or static pod runs.

## 6. Tests Required

- `tool/python_ffi_smoke.dart` must execute the real built C library.
- The native default-runner test must check imports, input, file effects,
  compile-only non-execution and separate standard error.
- Linux smoke must link the desktop SO and retain the VM's 65-case suite.
- Changes to shared C require an Android regression build and an explicit
  record of whether the new APK was installed and executed.
- Keep missing-library and argument failure tests; record unavailable target
  hosts as skips, never target-platform passes.

## 7. Wrong / Correct

Wrong: disable POSIX/VFS readers and supply only mp_reader_new_file on Windows.
Correct: also supply mp_lexer_new_from_file using mp_lexer_new and the custom
reader; the upstream lexer omits that adapter when those readers are disabled.

Wrong: kill a Dart isolate and assume its native C execution has stopped.
Correct: keep the worker alive through cleanup and signal its own native token.
