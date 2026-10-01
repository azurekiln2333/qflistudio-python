# Native Python Runtime

## 1. Scope / Trigger

Apply this contract to changes in `native/`, both `QfliPyNative.ets` copies,
and `lib/python_runner.dart`. The engine is upstream MicroPython 1.24.1
(`ecfdd5d`); port code adapts I/O and lifetime. Parsing and execution remain
in the upstream C compiler and VM.

## 2. Signatures

```c
QfliPyRunResult qfli_py_run(const char *source, const char *stdin_text,
    int heap_kb, const char *project_dir, const char *entry_file,
    int compile_only);
void qfli_py_result_free(QfliPyRunResult *result);
```

NAPI exports `run(source, stdin, heapKb, projectPath, entryFile, compileOnly)`
and `version()`. MethodChannel `qfli_py/native` handles `available`, `run`,
and `checkSyntax`. The latter maps to `compileOnly=true`.

Platform adapters are HarmonyOS ArkTS/NAPI and Android Kotlin/JNI. Android
calls the same C API on one executor with a 1 MiB stack and returns results
on the main thread. JNI exchanges standard UTF-8 byte arrays and rejects
embedded NUL in arguments; never pass ordinary UTF-8 to JNI modified-UTF-8 APIs.

## 3. Contracts

| Field | Type | Meaning |
| --- | --- | --- |
| `source` | string | Entry source; C strings are UTF-8 and NUL terminated |
| `stdin` | string | Complete input buffer; Dart reads project `input.txt` |
| `heapKb` | integer | Default 8192; allocation is reused after the first run |
| `projectPath` | string | Absolute root; relative `open` paths resolve here |
| `entryFile` | string | Absolute entry; traceback, `__file__`, `sys.argv[0]` |

Response: `{exitCode: number, output: string, error: string|null,
truncated: boolean}`. Probe: `{available: boolean, version: string,
detail: string}`. The C caller frees result buffers with `qfli_py_result_free`.
HAL stdout/stderr arrays have capacities of 256 KiB and 64 KiB respectively.
The C result is NUL-terminated text, not an arbitrary binary output channel.

`input()`, `sys.stdin` and `sys.stdin.buffer` share the finite HAL cursor.
`input()` returns `CHAR_CTRL_D` on exhausted input so upstream raises EOFError;
stream reads return zero bytes at EOF. `src/qfli_py_stdio.c` replaces the
upstream MCU stdio implementation in all three builders. Explicit stdout and
stderr writes use `qfli_py_hal_write` without altering exception capture's sink.
Both streams are unbuffered; flush and close are no-ops as in the upstream port.

Each invocation holds the C mutex, resets HAL input/output, calls
`gc_init/mp_init`, establishes stack control, starts file tracking, executes,
captures the result, closes tracked files, and calls `mp_deinit`.
Globals and imported modules cannot persist between runs.

`sys.path` starts with the entry directory followed by the project root.
Use upstream POSIX reading for `.py` imports and never change process cwd.
`checkSyntax` compiles the selected source without executing it or resolving
its imports. `mp_compile` uses `is_repl=false` for scripts.

`open(file, mode='r')` / `io.open` support `r/w/a/x`, optional `+`, `b/t`,
upstream stream methods, iteration, and context managers. Project paths use
`realpath`; new files require an existing parent inside the project.
Descriptors stay tracked until run cleanup even when the Python object is
collected. The upstream module reader is outside this path check; this is
not an isolation mechanism for untrusted Python code.

## 4. Validation & Error Matrix

| Condition | Result |
| --- | --- |
| Successful script / syntax check | Exit 0; error may contain explicit stderr |
| Compilation / uncaught runtime exception | Exit 1, traceback in error |
| `sys.exit(n)` | Exit n, no traceback |
| `sys.exit('reason')` | Exit 1, reason in error |
| `sys.exit()` integer conversion overflows | Exit 1, OverflowError; next run works |
| `input()` at EOF | Exit 1, EOFError |
| Standard stdin at EOF | Empty string / empty bytes |
| `sys.stderr.write()` | Captured in error, independent of exit status |
| Missing file / unavailable project root | `OSError: ENOENT` |
| Resolved `open` target / parent outside project | `OSError: EACCES` |
| Existing target with mode `x` | `OSError: EEXIST` |
| Read/write after close | `OSError: EBADF` |
| Invalid mode | `ValueError` |
| Directory passed to `open` | `OSError: EISDIR` |
| Native module missing | Probe unavailable / `QFLI_PY_MODULE_MISSING` |

## 5. Good / Base / Bad Cases

- Good: an entry in `src/` imports a sibling and a package and writes
  `notes.txt` in the project root.
- Base: `print(42)` returns `42\n`; a bare `42` returns no output.
- Bad: `open('../outside.txt', 'w')` fails; syntax checking
  `open('new.txt', 'w')` must not create the file.
- Unsupported: CPython extension modules, pip, `os`, networking,
  `encoding/errors/newline` arguments, interactive stdin and run cancellation.

## 6. Tests Required

- `sh native/tests/run_host.sh`: compile the real C bridge and MicroPython;
  assert imports refresh, file modes/stream methods work, path errors propagate,
  compile-only has no side effects, and `/proc/self/fd` counts stay stable
  after both successful and exceptional runs.
- Include finite stdio EOF, shared input/text/binary cursor, stderr routing,
  integer-exit overflow and subsequent successful execution.
- Android: build APK, inspect all ABI libraries and 16 KiB ELF/ZIP alignment,
  install on emulator, verify all debug JNI self-checks and an editor project
  that imports a helper, consumes `input.txt` and writes a project file.
- Keep JNI result/native classes and constructor with `@Keep`; verify an
  installed release APK after shrinking. Supply the self-check class for all
  three Android variants; only debug executes it.
- `flutter test`: assert source and project/entry paths cross the channel;
  this does not prove C execution.
- `flutter analyze`, `native/build.ps1`, and signed HAP packaging must pass.
- Compare SHA256 of both ArkTS copies. Install the final signed HAP and inspect
  `QfliPyNative` hilog for the current complete case count.
- Keep `-static-libstdc++` and `check_so_deps.py` checks. Allowed current
  dynamic dependencies are `libace_napi.z.so`, `libhilog_ndk.z.so`, and `libc.so`.
- Keep semantic generated port/qstr changes; remove incidental line-ending
  and build-date changes before staging.

## 7. Wrong vs Correct

```c
// Wrong: script expressions are echoed as REPL results.
module_fun = mp_compile(&parse_tree, source_name, true);
// Correct: script compilation; only explicit output is captured.
module_fun = mp_compile(&parse_tree, source_name, false);
if (!compile_only) mp_call_function_0(module_fun);
```

Closing only files explicitly closed in Python leaks descriptors between
VM invocations. Always call `qfli_py_file_end()` before `mp_deinit()` on
normal and exceptional completion.

Wrong: use upstream MCU stdio unchanged with finite stdin; it returns requested
read size even after `mp_hal_stdin_rx_chr()` returns -1. Correct: return the
actual count and zero at EOF. Wrong: convert a `SystemExit` integer after the
exception guard unwinds without a new guard. Correct: catch conversion errors
and finish the same cleanup path.
