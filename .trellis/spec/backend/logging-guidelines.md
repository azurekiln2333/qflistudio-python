# Runtime Diagnostics and Logging

## 1. Scope / Trigger

Use for runtime diagnostics, self-check logs and startup warnings. This wrapper
defines no application-wide structured logging package or remote telemetry
pipeline. Match each existing diagnostic sink to its consumer.

## 2. Existing Sinks

| Sink | Purpose / source |
| --- | --- |
| Native HAL stdout/stderr buffers | Program output/exceptions; `qfli_py_hal.c` |
| `ProgramRunResult` streams | Shared terminal; `lib/python_runner.dart` |
| ArkTS `hilog`, tag `QfliPyNative` | Loader status and real runtime self-checks |
| Android debug tag `QfliPyNative` | Installed JNI self-checks; debug variant |
| Flutter `debugPrint` | Optional progress failure code; `app_startup.dart` |
| Logs under `native/build/` | Configure/compiler/dependency evidence |

## 3. Contracts

- Python stdout, stderr and tracebacks are execution data. Capture them through
  the HAL; host/platform logs must not replace the result channel.
- Runner diagnostics use `[qfli] `. Preserve program output without that prefix.
  A truncation flag becomes a visible diagnostic.
- OHOS uses `hilog.info` for load/version and self-check completion, and
  `hilog.error` for loader/case failures. Preserve the existing tag for filters.
- `_reportProgress` logs PlatformException.code only; absent plugins are allowed
  in alternate shells. Optional progress must not become fatal startup work.
- Self-check logs identify controlled cases/outcomes. Avoid new production dumps
  of source, `input.txt`, saved content or credentials. Program output may contain
  user data; new platform log copies need a concrete diagnostic purpose.
- Keep verbose logs in ignored build paths and concise evidence in the task.
  Distinguish historical outcomes from current-artifact verification.

## 4. Validation & Error Matrix

| Event | Evidence |
| --- | --- |
| Script executes | Output/diagnostic streams and actual exit |
| Module load fails | Probe detail and applicable loader log |
| Output limit reached | `truncated: true` and terminal diagnostic |
| Optional progress fails | Code-only warning; startup continues |
| Self-check fails | Case and observed result under existing tag |

## 5. Good / Base / Bad Cases

- Good: loader detail reaches terminal and its tag identifies the platform log.
- Base: Python stdout appears once in the terminal.
- Bad: log all source/input to hilog or mix build output into Python stdout.

## 6. Checks Required

`test/python_app_test.dart` checks diagnostics/truncation/stderr;
`test/startup_test.dart` checks progress handling. Native changes need installed
`QfliPyNative` logs compared with current cases, following
[Native Python Runtime](./native-python-runtime.md). A version log alone does
not establish a complete runtime pass.

## 7. Wrong vs Correct

Wrong: use host `printf` as Python output capture.
Correct: route output through `qfli_py_hal_write`, as
[qfli_py_stdio.c](../../../native/src/qfli_py_stdio.c) does.
See [OHOS diagnostics](../../../native/ohos/QfliPyNative.ets) and
[startup warnings](../../../lib/app_startup.dart).
