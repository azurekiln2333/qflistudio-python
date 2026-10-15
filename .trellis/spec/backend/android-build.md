# Android Build

## 1. Scope / Trigger

Use for Android Gradle configuration and APK/emulator verification. Read the
native runtime spec before claiming Python execution support on Android.

## 2. Signatures

```powershell
flutter build apk --debug
adb -s emulator-5556 install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s emulator-5556 shell am start -n com.azurekiln.qfli.pyflow/.MainActivity
```

Use the target serial reported by `adb devices`, not an assumed default.

## 3. Contracts

- Application ID and activity package are `com.azurekiln.qfli.pyflow`.
- Android NDK is pinned to `27.0.12077973` in `android/app/build.gradle.kts`.
  A valid installation must contain `source.properties`.
- Gradle heap is 2 GiB, metaspace 512 MiB, code cache 256 MiB, active JVM
  processors four, workers two, and Kotlin daemon heap 512 MiB.
- `android/local.properties` supplies local SDK paths and remains untracked.
- Debug APK output is `build/app/outputs/flutter-apk/app-debug.apk`.
- `native/android/CMakeLists.txt` compiles tracked embedding sources and shared
  C adapters for armeabi-v7a, arm64-v8a and x86_64. It never regenerates the
  shared source tree during parallel ABI builds.
- Link static C++ and request 16 KiB page alignment; use upstream setjmp GC
  register capture with `MICROPY_GCREGS_SETJMP=1` on Android.
- Kotlin registers `qfli_py/native` through MainActivity; the exact request and
  result contracts are in `native-python-runtime.md`.
- Debug startup performs 46 actual JNI self-checks (36 base and 10 lifecycle/artifact cases). Profile/release supply a
  no-op class. JNI classes/methods and result constructor must retain names.

## 4. Validation & Error Matrix

| Condition | Action |
| --- | --- |
| Missing NDK `source.properties` | Install the configured complete package |
| JVM mmap allocation failure | Inspect `hs_err_pid*.log` and memory/worker budgets |
| APK build passes | Install and verify the actual activity, not only build output |
| Shared emulator foreground changes | Check `dumpsys window` package before evaluating screenshots |
| Android Python run | Real output and exit status from shared C VM |
| C drive full during Gradle transforms | Free or relocate generated cache; source build is not at fault |

## 5. Good / Base / Bad Cases

- Good: APK builds, installs, shows QFLIPyFlow, creates a Python project and
  opens `src/main.py` in the editor.
- Base: the Python tools page handles an empty project registry.
- Bad: an installer-only NDK directory is treated as ready, a JVM crash is
  reported as a source compiler error, or another app's dialog is attributed
  to this APK.

## 6. Tests Required

Build the APK, install it, check its package/activity and actual screenshots,
create a project and inspect application-specific logcat errors. Record
Android runtime availability separately. Native checks must report all cases
passing, and the editor must run a multi-file project with input and file I/O.
Verify release shrinking by installing the release APK and executing a project.
Build configuration changes use build/emulator evidence without redundant
Dart unit tests.

## 7. Wrong vs Correct

Wrong: assume `flutter.ndkVersion` is installed because the NDK directory
exists. Correct: require the pinned version's metadata and successful Gradle
configuration. Wrong: use a visible JVMX screenshot as evidence for PyFlow.
Correct: confirm `com.azurekiln.qfli.pyflow` owns the foreground window.
