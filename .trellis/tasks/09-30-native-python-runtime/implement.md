# Implementation Plan

- [x] Inspect current native, Dart, ArkTS, build, test, and device state.
- [x] Build the existing arm64 library and signed HAP; install and launch on a device; record the real self-check result.
- [x] Make each C VM invocation independent and run packaged on-device C VM checks for compile/run, errors, input, exit, and repeat runs (7/7).
- [x] Pass project and entry paths through Flutter, ArkTS, and NAPI; enable upstream file reading and project module import (on-device 10/10).
- [x] Add project-local file operations through the port and test read/write and path failures (device 14/14; expanded host C VM suite 51/51).
- [x] Add practical editor/runtime tools supported by the engine, then remove unfinished-work copy from normal app flows.
- [x] Run host C VM checks, Flutter test/analyze, ARM64 build/dependency scan, ArkTS copy checks, and signed HAP packaging.
- [ ] Install the latest signed HAP and confirm the complete 17/17 device self-check.
- [x] Review spec updates and commit each coherent batch using conventional messages, staging only task-owned files.

## Build and Validation Commands

- `& .\native\build.ps1 -SkipCopy` for native compilation and dependency scan.
- `sh native/tests/run_host.sh` on Linux, or `wsl.exe -d qfli-java-build --exec sh /mnt/d/MyNewProjects/qfli_python/native/tests/run_host.sh` on this Windows host.
- `flutter test` and `flutter analyze` for Flutter integration and tools-page checks.
- `hvigorw.bat assembleHap --mode module -p product=default --no-daemon` from `ohos` for packaging.
- `hdc install <signed-hap>`, `hdc shell aa start -a EntryAbility -b com.azurekiln.qfli.pyflow`, then inspect `QfliPyNative` hilog.

## Risk Points

- Generated `native/micropython_embed/genhdr` files are tracked and regenerate with Windows line endings and a build date. Do not stage incidental generated diffs.
- `ohos/entry/src/main/ets/entryability/EntryAbility.ets`, `main_pages.json`, and `AgreementReader.ets` were dirty before this task. Preserve them.
- The ArkTS bridge has two copies; contract edits must update both.

## Pending Device Gate

The signed HAP has been rebuilt with file append and compile-only checks (17 cases).
The latest installed-device evidence is 14/14 from the earlier file-I/O batch;
hdc currently reports no connected targets. Keep this task in progress until the
latest HAP is installed and launched and the 17/17 result is recorded.
On 2026-10-01 the user explicitly stopped further HarmonyOS runtime debugging;
this gate remains pending and does not block the requested Android delivery.

## Latest Local Verification (2026-09-30)

| Check | Result |
| --- | --- |
| Host C VM smoke | 51/51 |
| Full Flutter tests | 25/25 |
| Flutter analysis | No issues |
| ARM64 build and dependency scan | Passed; only the three allowed system libraries |
| ArkTS bridge SHA256 comparison | Identical copies |
| Signed HAP | Built successfully; includes the FlutterTask build |
| Whitespace check | `git diff --check` passed after removing generated formatting churn |

Native/backend and Python workflow code contracts were captured in the local
`.trellis/spec/` tree, which this repository intentionally ignores. The tracked
`native/README.md` records build prerequisites, commands, capabilities and limits.
Fresh full-app checkout verification remains separate because it requires the
adjacent shared-core package and a valid local HarmonyOS signing setup.

## Android APK Smoke (2026-10-01)

- Fixed APK build prerequisites by pinning the installed complete NDK
  `27.0.12077973`. Flutter's default `28.2.13676358` had only an installer
  directory and no `source.properties`; its download was stopped due to speed.
- Reduced Gradle heap from 8 GiB to 2 GiB, limited workers to two and JVM active
  processors to four, and bounded the Kotlin daemon heap to 512 MiB. The prior
  Gradle JVM crashed with a native-memory allocation failure.
- `flutter build apk --debug` passed; installed via `adb install -r` and launched
  `com.azurekiln.qfli.pyflow/.MainActivity` on `emulator-5556` (Android 17 x86_64).
- Verified the QFLIPyFlow home, Python tools empty state, creation of an
  `AndroidSmoke` Python project, and the source editor. Screenshots are under
  the ignored `build/android-smoke-*.png` paths.
- Run correctly reported unavailable backend with exit code 127. The Android
  activity has no native MethodChannel registration and the APK contains no
  Android MicroPython library. Android Python execution needs a separate JNI
  adapter and NDK build of the same C engine; this smoke test does not verify it.
- An intervening JVMX app owned the first page-size compatibility dialog;
  foreground package checks distinguished it from this APK.

## Android Native Runtime Delivery (2026-10-01)

- [x] Compile the existing C MicroPython engine through Android NDK/CMake for
  armeabi-v7a, arm64-v8a and x86_64; keep the same bridge, file I/O and VM.
- [x] Register `qfli_py/native` in Kotlin and forward UTF-8 byte arrays via JNI;
  execute on one background thread and return results on the main thread.
- [x] Add actual JNI debug self-checks plus release/profile no-op variants.
- [x] Correct shared stdin EOF, finite standard stream reads, stdout/stderr
  routing, and overflow of integer SystemExit values; verify recovery.
- [x] Build debug/release APKs and an x86_64 profile APK.
- [x] Install debug APK and pass **36/36** native cases on emulator-5556
  (Android 17 x86_64, 16 KiB pages).
- [x] Install release APK after shrinking; execute a multi-file editor project
  with `input.txt` and real project file I/O, exit 0; check syntax through UI.
- [x] Real host C VM **65/65**, Flutter **25/25**, analysis clean, changed C
  sources warning-clean, and whitespace check passed.
- [x] Inspect all three ABI native libraries: 0x4000 LOAD alignment and only
  libm.so/libdl.so/libc.so dependencies. Both debug and release APKs pass
  `zipalign -c -P 16 -v 4`. All nine release ELF libraries are aligned to at
  least 16 KiB.

Editor result: `ANDROID_PROJECT_OK android Ada:42`, exit code 0. The C engine
imported `src/helper.py`, consumed the project's input buffer, wrote
`android-result.txt` and read it back. Debug file contents were independently
read through `adb run-as` as `Ada:42`. Release syntax UI reported success.

Evidence is in ignored `build/android-native-selfcheck.log`,
`build/android-native-project-run.png`, `build/android-release-project-run.png`
and `build/android-release-syntax.png`. Artifacts are
`build/app/outputs/flutter-apk/app-debug.apk` (188,866,119 bytes) and
`app-release.apk` (70,925,142 bytes); release still uses the configured debug
signing key. The profile build used `--target-platform android-x64`.

The first Android run exposed the HAL's wrong -1 EOF marker (26/27 before the
fix). Additional review caught unguarded SystemExit overflow and upstream MCU
stdio behavior that assumed endless input and merged stderr into stdout.
`src/qfli_py_stdio.c` is the shared port adaptation; the upstream compiler and
VM remain unchanged, and the generated header churn was removed.

The first release build failed due to C: having zero free bytes while Gradle
extracted Flutter dependencies. After stopping the Gradle 8.14 daemon, its
generated `caches/8.14/transforms` was moved to
`D:/ProgramData/Gradle/cache-8.14-transforms` with a junction at the original
path, freeing about 8 GiB. The release rebuild then passed. No project-wide
SDK/cache path configuration was changed.

A shared-emulator page-size dialog listed Java/JVM libraries absent from this
APK. The actual release ZIP contains only libapp.so, libflutter.so and
libqfli_py.so per ABI; package path, focused activity and ELF inspection were
checked before attributing it. PyFlow-specific logcat had no runtime errors.

HarmonyOS x86_64 native build and HAP packaging passed earlier in this session,
before the final shared stdin/stdio/exit fixes. The user then requested Android
debugging only. No final HarmonyOS installation/runtime check was performed;
the original task remains in progress pending its separate final gate.
