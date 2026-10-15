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

NAPI exports asynchronous `run(source, stdin, heapKb, projectPath, entryFile,
compileOnly, token, artifactOutput, bytecodeFile)` plus `version()`,
`createCancel()`, `cancel(token)` and `freeCancel(token)`. MethodChannel
`qfli_py/native` handles `available`, `prepareRun`, `cancel`, `run`,
`checkSyntax` and `compile`. Syntax checking and compilation use compile-only
execution; only compilation supplies an artifact output path.

The legacy C ABI remains available. Controlled callers use
`qfli_py_execute[_into](..., compile_only, token, artifact_output, bytecode_file)`.
Create/request/free cancellation tokens through `qfli_py_cancel_*`. The caller
retains its token until queued or executing work has completed. Native VM state
is touched only by the worker under the runtime lock; stop only sets an atomic
flag. A pending or executing stop returns 130 with KeyboardInterrupt. Exception
printing clears the active token before writing diagnostics. Long sleeps check
the signal every 20 ms; arbitrary blocking native I/O is not interruptible.

Android probe includes `runControl: true` and `bytecode: true`. `prepareRun`
registers a token and returns an opaque string ID before `run` is submitted.
`run` accepts `runId`; `cancel(runId)` signals it directly on the platform
thread. Registry lookup, signaling, removal and token freeing share one lock.
Completion removes the ID, making late cancellation harmless.

OHOS detects cancellation exports before advertising `runControl`/`bytecode`.
Its ArkTS registry maps opaque string run IDs to native cancellation tokens.
A claimed token stays alive until its asynchronous native Promise settles;
success, rejection and malformed native outcomes release it exactly once.
Duplicate submission cannot claim an active ID; late cancellation is a no-op.
NAPI queues VM execution on async work, keeping ArkTS available for stop calls.
The C runtime mutex serializes concurrent workers. `runNative` normalizes
legacy synchronous outcomes and converts synchronous native throws to Promise
rejection; a channel handler must always complete its result.

All NAPI string arguments reject NUL. Supplied optional arguments must match
their declared types. Heap sizes are finite integral values in `[0, INT32_MAX]`;
native token values are nonnegative safe integers owned by the trusted registry.
Numeric shape validation is not a security boundary for arbitrary addresses.

Platform adapters are HarmonyOS ArkTS/NAPI and Android Kotlin/JNI. Android
calls the same C API on one executor with a 1 MiB stack and returns results
on the main thread. JNI exchanges standard UTF-8 byte arrays and rejects
embedded NUL in arguments; never pass ordinary UTF-8 to JNI modified-UTF-8 APIs.

Inspect the actual HAP library entries after packaging. A selected Flutter ABI
needs matching `libapp`, `libflutter` and the current `libqfli_py`; a leftover
library in ignored `ohos/entry/libs/<abi>` can be packaged even when that ABI
was not rebuilt. Preserve stale generated libraries outside the packaging tree
before a single-ABI release build. Do not advertise an ABI with only an old
backend SO and no matching Flutter runtime. Rebuild that ABI before testing it.

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

`compile` accepts `artifactOutput`, invokes upstream `mp_compile_to_raw_code`
and `mp_raw_code_save`, and writes bytecode-only .mpy data through the existing
project file resolver/tracker. Compile errors do not touch a previous artifact;
I/O failures are reported and may leave partial output. `run` can accept
`bytecodeFile` and uses upstream `mp_raw_code_load_file`. Imported .mpy modules
use the same upstream importer; source files are unnecessary after compilation.
File format/version and integer-width compatibility are enforced by upstream.
Keep both port configs and generated qstr headers synchronized; do not edit
upstream serializer or invent a different bytecode format.

The tools page discovers .py/.mpy and exposes compile/stop commands. Compilation
saves a sibling .mpy and refreshes the file list. Source-only commands are
disabled for bytecode. Retain the run callback while working, cancel on page
disposal, and also cancel a run handle arriving after disposal. Outputs are
buffered until native completion; preserve stdout/stderr and actual exit codes.

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
  `encoding/errors/newline` arguments and interactive stdin.

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
- `node native/tests/ohos_channel_test.cjs`: execute the real ArkTS handler
  with native/platform doubles to verify capabilities, sync/async failure
  cleanup, cancellation ownership and artifact argument routing. Compiler
  discovery accepts `QFLI_ARKTS_TYPESCRIPT`; no dependency download occurs.
  This is channel behavior evidence, separate from actual NAPI/device execution.
- The Flutter OHOS bridge test checks byte parity of both source copies;
  do not replace behavior coverage with source-string presence assertions.
- `test/python_lifecycle_test.dart`: real loop/sleep interruption, pre-start
  and queued stop, token isolation, recovery, early runner result, upstream
  artifacts without entry/imported source and rejected bytecode/path escapes.
- Android's ordinary debug entry must pass the expanded 46-case JNI self-check;
  additionally operate the normal tools page to stop a loop and compile/run an
  artifact after removing its source from the selectable file set.

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
