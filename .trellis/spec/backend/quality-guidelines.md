# Backend Quality Guidelines

## 1. Scope / Trigger

Use before reviewing or committing execution, packaging or local file changes.
The VM, adapter contracts and shipped library must agree.

## 2. Reference Implementations

- `native/src/qfli_py_bridge.h` defines the ABI; `qfli_py_bridge.c` owns VM cleanup.
- `lib/python_ffi.dart` pairs C/Dart types and frees native memory.
- `native/tests/smoke.c` exercises the real VM, files and repeated runs.
- `test/python_lifecycle_test.dart` covers controlled runs and reusable artifacts.
- `analysis_options.yaml` includes `package:flutter_lints/flutter.yaml`.

## 3. Contracts

- Retain upstream compilation/VM behavior. Fix the port/adapter instead of
  adding a partial Dart Python interpreter.
- Preserve ABI layout, UTF-8/NUL rules, integer widths and ownership. Results
  use `qfli_py_result_free`; version strings are static.
- VM access stays under the C runtime lock. Cancellation signals a token and
  never mutates another thread's VM. Retain tokens until queued workers finish.
- Track project descriptors and clean them on normal/exceptional completion.
  Preserve finite stdin EOF and independent stdout/stderr.
- Synchronize port/generated inputs and ArkTS copies. Keep semantic changes,
  excluding incidental build-date and line-ending churn.
- Keep JNI classes/constructors with `@Keep`, required static C++ linkage, and
  existing ELF/ZIP alignment and dependency guards.

## 4. Validation Matrix

| Layer changed | Required evidence |
| --- | --- |
| Dart runner | Focused Flutter tests and full app analyzer/tests |
| C runtime/port | Real C/FFI runs, repeated-run/resource regression |
| Android JNI/package | APK, ABI/dependency/alignment inspection; device run separately |
| OHOS bridge/package | Bridge hashes, native dependencies, signed HAP; hilog separately |
| Desktop/Apple integration | Target build/run when available; identify unavailable hosts |

## 5. Good / Base / Bad Cases

- Good: a failing run closes its files and the next invocation works.
- Base: focused checks and complete application analyzer/tests pass.
- Bad: count skipped DLL tests as VM validation or package creation as a device
  runtime pass.

## 6. Checks Required

Run applicable commands from this repository:

```text
flutter analyze
flutter test
sh native/tests/run_host.sh
dart --packages=.dart_tool/package_config.json tool/python_ffi_smoke.dart native/build/windows/qfli_py_ffi.dll
```

The C command needs the documented POSIX/compiler environment. The FFI command
shown uses the Windows DLL. Read [Python FFI](./python-ffi.md),
[Android Build](./android-build.md) and
[Native Python Runtime](./native-python-runtime.md) for target-specific gates.
Record command, artifact and actual host/device outcome; missing prerequisites
remain open gates. Stage explicit owned paths and serialize Conventional Commits
when workers share the checkout.

## 7. Wrong vs Correct

Wrong: remove a dependency guard to package an incompatible SO successfully.
Correct: fix link inputs and let the dependency checker inspect the result.
See [OHOS CMake](../../../native/CMakeLists.txt) and
[the checker](../../../native/tools/check_so_deps.py).

## 8. Bounded Windows validation and publication

### Scope and entry points

Use this contract for serialized host verification windows. It does not grant
native compilation, SDK builds, signing or device operations.

```python
run_owned(argv: list[str], *, timeout_seconds: float,
          cleanup_seconds: float, cwd: str | Path,
          log_path: str | Path, report_path: str | Path,
          environment: dict[str, str] | None = None) -> dict
```

`tool/python_owned_process.py` owns the exact suspended child, its creation
FILETIME and a private Windows Job. The observer fixture
`run_python_granted_window.py` coordinates a separate `run_python_host.py` child.
The child writes local evidence and never publishes a global final status.
The observer states its own PID and role; it never claims it has itself exited.

### Resource and validation contracts

A phase can RELEASE only when the retained root is terminal, its Job has zero
active processes and every owned handle is closed. Required report evidence:

- `state == "FINISHED"`, `release == "RELEASE"`,
  `cleanupConfirmed == true`, `handlesRetained == false`.
- `process.terminal == true`, `process.jobActiveProcesses == 0`,
  `process.handlesClosed == true`.
- Exact `process.pid`, `process.creationFiletime100ns`,
  `process.processHandleDecimal` and `process.jobHandleDecimal`.

An exit code or PID lookup cannot replace that proof. On unconfirmed cleanup,
retain the original handles and continue observation. Never kill a PID obtained
from a later process scan. A failed check can RELEASE verified resources while
its validation result remains FAIL. A missing child report cannot establish PASS.

Reserve ACK, verification, cleanup and final publication inside the fresh named
grant's total budget. Never replay a consumed grant. The observer default total
ceiling is 180 seconds. A nominal timeout does not prove cleanup occurred within
that budget; report actual terminal and publication times.

Before execution, bind every executed test file and actual native DLL. Always
bind `native/build/windows/qfli_py_ffi.dll`; also bind the effective
`QFLI_PY_DEBUG_TEST_LIBRARY` and `QFLI_PYTHON_TEST_LIBRARY` overrides. Missing
libraries refuse before Flutter starts. Recheck suite, binary, owned source,
product and shared-core identities after execution. A frozen binary's digest
proves its identity, not that current native sources produced it.

Before composing final publication, downgrade validation for source drift or an
identity-read exception. The global message and local result must agree. Preserve
the resource RELEASE when its exact cleanup proof still holds.

### Validation matrix

| Condition | Required result |
| --- | --- |
| Tests fail, exact root terminal, Job empty, handles closed | Validation FAIL, resources RELEASE |
| Root exit 0, Job still active | HOLD, retain handles, no final handoff |
| Missing DLL or invalid grant | Refuse before verification starts |
| Suite/DLL/source changes or final identity read fails | Validation FAIL, never publish PASS |
| Child report absent after proven child cleanup | Validation FAIL, resources RELEASE |
| Window exceeds total budget | Validation FAIL, retain measured timing |

### Isolated verification boundary

Both `verify_run_python_host.py` and `verify_run_python_granted_window.py` must
install strict doubles before every call into runner `main`, `run` or window
execution. Unknown fake commands raise. No fake may fall back to real execution.
A deliberately weakened argument guard must still produce zero real publication,
process, SDK or device I/O. Refuse optimized Python and non-Windows verification;
neither stripped assertions nor the platform guard may manufacture a PASS.
Use always-on checks rather than bare `assert` for acceptance.

Required synthetic cases cover live Jobs after root exit, open handles, missing
identity, failed checks with clean release, missing binaries, test/binary drift,
final identity-read failure, budget exhaustion, unknown fake commands and guard
regression. Synthetic results establish decision logic only. Run real Windows
process controls under a fresh grant before SDK-dependent validation.

Wrong: the verification child publishes RELEASE while its own root is live.
Correct: the observer publishes after it observes the managed child's exact
terminal state, Job zero and closed handles.
