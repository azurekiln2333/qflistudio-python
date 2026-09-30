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

The Android UI, project creation and editor were smoke-tested on an x86_64
Android 17 emulator on 2026-10-01. Android does not yet register the
`qfli_py/native` MethodChannel or package an Android MicroPython library;
running a Python entry currently returns exit code 127. The implemented native
Python execution path is HarmonyOS-specific; see [native/README.md](native/README.md).
