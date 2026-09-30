# qfli_python

This Flutter app is an independent Git repository. Check out `qfli_studio_core` next to it before resolving dependencies.

```text
checkout-parent/
  qfli_studio_core/
  qfli_python/
```

Run `flutter pub get` here, then `flutter run` for the target device. The shared editor patch is provided by `../qfli_studio_core/vendor/re_editor`.

## Android APK

Install Android NDK `27.0.12077973` alongside the Android SDK. The app pins this
version in `android/app/build.gradle.kts`. Gradle uses a 2 GiB heap, two workers,
and a 512 MiB Kotlin daemon heap to keep emulator builds within a bounded memory
budget.

```powershell
flutter build apk --debug
adb -s emulator-5556 install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s emulator-5556 shell am start -n com.azurekiln.qfli.pyflow/.MainActivity
```

The debug APK is `build/app/outputs/flutter-apk/app-debug.apk`. Replace the
device ID with the one reported by `adb devices`.

Android and HarmonyOS compile the same upstream C MicroPython 1.24.1 engine and
share the VM, project imports, file I/O and compile-only syntax checker. Android
uses a Kotlin MethodChannel and JNI adapter; HarmonyOS uses ArkTS and NAPI.
Android packages `libqfli_py.so` for `armeabi-v7a`, `arm64-v8a` and `x86_64`, with
16 KiB page alignment. Native Android execution runs on a background thread.

The debug APK runs real native self-checks at startup. Inspect them with:

```powershell
adb -s emulator-5556 logcat -d -s QfliPyNative
```

On 2026-10-01, the Android 17 x86_64 emulator executed a project from the editor,
imported a sibling module, read `input.txt`, wrote and reread a project file, and
printed `ANDROID_PROJECT_OK android Ada:42` with exit code 0. See
[native/README.md](native/README.md) for contracts and MicroPython limitations.
