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
