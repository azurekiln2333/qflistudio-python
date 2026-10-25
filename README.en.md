# QFLIPyFlow (qfli_python)

[Simplified Chinese](README.md) | [Traditional Chinese](README.zh-TW.md) | [English](README.en.md)

QFLIPyFlow is a Python IDE for phones and desktops. The app runs Python code with an embedded MicroPython engine. The app is fully offline. The engine is not CPython. The app does not provide pip.

This repository is a standalone Git repository. Check out `qfli_studio_core` next to it before resolving dependencies.

```text
checkout-parent/
  qfli_studio_core/
  qfli_python/
```

Run `flutter pub get` here, then `flutter run` for the target device. The shared editor patch comes from `../qfli_studio_core/vendor/re_editor`.

## Features

- Project and file selection on real local projects.
- Syntax check. Compile only. No execution. No disk writes.
- Compile to `.mpy`. Write bytecode next to the entry file.
- Run and stop. Report real stdout, stderr and exit codes.
- Editor diagnostics. Analyze unsaved buffers.
- Module catalog. List built-in and bundled modules.
- Local package management. Install and delete project packages from local source.
- Built-in terminal. `python`, `python3` and `micropython` route to the same engine.
- Debug sessions. Implemented in source. See the verification status below.

## Engine

The engine is upstream MicroPython 1.24.1 (commit `ecfdd5d`). It carries the full compiler and bytecode VM. The port adapts files, standard streams, clocks, locking and lifetime. The port has no hand-written interpreter.

```text
Dart → MethodChannel('qfli_py/native') → Kotlin/JNI or ArkTS/NAPI → libqfli_py.so → MicroPython
```

Windows, Linux, iOS and macOS use a local FFI plugin. These platforms share the same C engine.

## Platforms and verification status

| Platform | Transport | Source | Verified |
| --- | --- | --- | --- |
| Android | Kotlin/JNI | Implemented | Historical host and emulator verification |
| HarmonyOS OHOS | ArkTS/NAPI | Implemented | Acceptance not complete |
| Windows | FFI | Implemented | Historical native-case verification |
| Linux | FFI | Implemented | Historical C ABI verification |
| iOS and macOS | FFI | Implemented | Not verified |

The historical checks in the table come from earlier builds. The current-source final suite has not been re-run.

Android and HarmonyOS share the VM, project imports, file I/O and the compile-only syntax checker.

Android: `libqfli_py.so` covers `armeabi-v7a`, `arm64-v8a` and `x86_64`. ELF segments use 16 KiB alignment. Debug startup runs 46 real JNI self-checks. On 2026-10-01 the x86_64 emulator ran a multi-file project. The project read `input.txt`, wrote a project file, and printed `ANDROID_PROJECT_OK android Ada:42` with exit code 0. That batch's release APK also passed runtime and syntax checks after install.

HarmonyOS: The ArkTS/NAPI adapter and the shared C engine are implemented. The 10-22 module HAP was built. That HAP predates the current FFI. The shared standard-stream and exit-code fix passed on the host C VM and Android. The current-source final HAP and device acceptance are not complete.

Windows and Linux: The Windows FFI smoke test passed 34/34 real native cases. The Linux C ABI passed 65/65 cases, including file effects and resource cleanup. The full Linux Flutter GUI has not been built.

iOS and macOS: No Apple host or Xcode is available here. Source integration, pod builds and link options are unverified.

## Offline policy

The app declares `isOffline: true`. The current tracked `ohos/entry/src/main/module.json5` does not request `ohos.permission.INTERNET`. HarmonyOS `EntryAbility.ets` sets `OFFLINE_ONLY = true`. It refuses `openAgreement`, `openUrl` and Huawei account `login`. The refusal happens before any remote provider is created. Local startup progress, document selection and text sharing stay available.

Note the difference between signed artifacts and source. The 2026-10-15 signed HAP still listed `ohos.permission.INTERNET`. That HAP predates the offline policy fix. Inspect the permission list again after installing a new HAP.

Host behavior evidence comes from `node tool/test_python_offline_platform.cjs`. The script drives the real EntryAbility handlers with platform doubles. It is not device acceptance.

## Limitations

- The engine is MicroPython. It is not CPython.
- No pip, no CPython C extensions and no complete standard library.
- Standard input comes from `input.txt` in the project root. There is no interactive stdin.
- Output returns after the run finishes. An infinite loop holds the run channel.
- Cancellation works inside VM loops and supported sleeps. Arbitrary blocking native I/O is not interruptible.
- The terminal only runs project `.py` and `.mpy` scripts. It refuses `-m`, `-c`, interpreter options and extra arguments. There is no interactive REPL.
- `.mpy` is a bytecode file. It is not a standalone program or a CPython `.pyc`.

## Bundled and built-in modules

The bundle provides 10 modules: base64, bisect, contextlib, copy, csv, functools, itertools, statistics, string and textwrap. Each module's source, license and SHA256 digest are recorded in `assets/python_stdlib/PROVENANCE.md` and `assets/python_stdlib/manifest.json`.

The built-in set has 17 modules: sys, math, cmath, json, random, time, re, binascii, heapq, array, collections, struct, io, errno, micropython, gc and builtins.

These lists describe only the tested scope. The lists make no CPython-compatibility claim.

## Local packages

Local package operations accept only local `.py`, directories, `.zip` and pure-source `.whl`. Downloads, build hooks and native extensions are unsupported. Every file is compile-checked before install. A failed transaction rolls back. The file-count limit is 4096. The per-file limit is 2 MiB. The total source limit is 16 MiB.

## Debug sessions

The source provides `PythonDebugger`. It uses real MicroPython sessions. It supports breakpoints, step into, step over, step out, stop on entry, call stacks and variables. It requires saved files. It does not accept unsaved source snapshots. The debug source must be a project-local `.py` file. Ordinary runs still pay the tracing cost. Current performance verification is not complete.

Device acceptance for debugging is not complete.

## Build

Android:

```powershell
flutter build apk --debug
adb -s emulator-5556 install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s emulator-5556 shell am start -n com.azurekiln.qfli.pyflow/.MainActivity
```

Android needs NDK `27.0.12077973`. The app pins this version in `android/app/build.gradle.kts`. The debug APK is `build/app/outputs/flutter-apk/app-debug.apk`. Replace the sample device ID with the one reported by `adb devices`.

HarmonyOS HAP:

```powershell
flutter build hap --release --target-platform ohos-arm64
```

The signed HAP is `build/ohos/hap/entry-default-signed.hap`. `ohos/entry/build-profile.json5` compiles only `arm64-v8a`. Packaging excludes x86_64 and 32-bit ARM libraries.

Native library:

The following command builds the HarmonyOS `libqfli_py.so`.

```powershell
& .\native\build.ps1
```

The script finds the toolchain. It fetches the pinned MicroPython 1.24.1 when the source is missing. It builds `libqfli_py.so`. It checks dynamic dependencies. It copies the result into `ohos/entry/libs/`.

Windows desktop:

```powershell
./native/desktop/build.ps1 -Compiler <gcc.exe> -CMake <cmake.exe> -Ninja <ninja.exe>
```

`native/desktop/build.ps1` builds only the Windows DLL.

Linux and macOS:

```sh
sh native/desktop/build.sh
```

`native/desktop/build.sh` calls CMake to configure `native/desktop`. The build target is `qfli_py_ffi`. `native/linux/CMakeLists.txt` references the same `native/desktop`.

## Test and verification commands

```powershell
flutter analyze --no-pub
flutter test --no-pub
dart --packages=.dart_tool/package_config.json tool/python_ffi_smoke.dart native/build/windows/qfli_py_ffi.dll
python tool/verify_python_modules.py
node tool/test_python_offline_platform.cjs
python native/tools/inspect_so.py
```

`sh native/tests/run_host.sh` runs the host C tests in a POSIX environment. Host results do not replace device acceptance.

Device self-check logs:

```powershell
adb -s emulator-5556 logcat -d -s QfliPyNative
hdc shell hilog -z 5000 -T QfliPyNative
```

## Layout

| Path | Purpose |
| --- | --- |
| `lib/main.dart` | Python profile, terminal hook and entry point |
| `lib/app_startup.dart` | Bootstrap and first-frame handoff |
| `lib/python_tools_page.dart` | Project and file tools, operation state |
| `lib/python_runner.dart` | Execution adapter and result types |
| `lib/python_ffi.dart` | Native bindings and worker isolate |
| `lib/python_packages.dart` | Local package transactions |
| `lib/python_code_analyzer.dart` | Unsaved-buffer diagnostics |
| `lib/python_debugger.dart` | Real MicroPython debug sessions |
| `native/` | Embedded MicroPython, port layer and platform adapters |
| `assets/python_stdlib/` | Bundled modules and provenance |
| `test/` | Profile, tools, startup and native-boundary regressions |

## More documentation

- `native/README.md`: native backend details and maintenance notes.
- `native/PLATFORMS.md`: platform builds and measured evidence.
- `native/lifecycle.md`: cancellation, bytecode and ownership.
- `.trellis/spec/`: coding contracts and verification guidance.
