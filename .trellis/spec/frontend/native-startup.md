# Native Startup

## 1. Scope / Trigger

Read before changing Flutter bootstrap, Android startup views or HarmonyOS
FlutterPage splash handling. The main project supplies the HarmonyOS reference;
PyFlow additionally applies the same first-frame contract to Android.

## 2. Signatures

```dart
Future<void> runWithAppStartup({
  required Widget app,
  required ProjectStore store,
  required AuthStore auth,
  required SettingsStore settings,
  required ValueNotifier<bool> ready,
});
// MethodChannel('qflistudio/platform')
invokeMethod<void>('startupProgress', {'progress': progress});
```

Android receives the call in MainActivity. HarmonyOS forwards it to
EVENT_STARTUP_PROGRESS and caches the latest value in pyflowStartupProgress.

## 3. Contracts

- Defer the first engine frame before runApp on Android/OHOS, then wait for
  framework layout before beginning the three existing store loads.
- AppBootstrap reports actual completion as 1/3, 2/3, 1; no synthetic progress.
- Keep the reference waits: initial 160 ms, minimum native display 1100 ms,
  post-load 320 ms. Await the ready home frame's endOfFrame before allowing
  the first engine frame. Release the gate in finally.
- Progress reporting is optional and cannot hold the first-frame gate. Native
  handlers accept finite numbers, clamp to [0,1], and return null on success.
- Android uses RenderMode.texture. The embedding's default Surface mode
  installs a pre-draw gate for the entire Android view tree, preventing the
  native progress overlay from drawing while Flutter frames are deferred.
  Texture mode adds composition overhead; revisit with embedding changes.
- Android removes its overlay only after onFlutterUiDisplayed, with a 200 ms
  fade. Engine cleanup and activity destruction clear views/channel handlers.
  Preserve the independent qfli_py/native registration and debug self-check.
- On API 31+, register the system SplashScreen exit listener before
  super.onCreate. Remove that system view synchronously only after the native
  overlay's ViewTreeObserver frame-commit callback (API 29+) or real Flutter
  display. The callback requires the manifest's hardwareAccelerated=true.
  Default system splash exit yielded actual blank frames in both modes, even
  with a native overlay in place. Keep the product icon in NormalTheme's
  window background; clear the splash listener and pending commit callback on
  destruction. A late callback must check the overlay's identity before use.
- OHOS passes StartupSplash through FlutterPage.splashScreenView. The bundled
  embedding removes it on its actual renderer first-frame event. Subscribe
  with the same function used for unsubscribe, and replay AppStorage's latest
  progress to cover events sent before aboutToAppear.
- Product icon is 96 logical units; bar is 4, horizontal margin 32, maximum
  width 420, bottom margin 48. Startup backgrounds are #F8F9FF / #111418.
- Other platforms retain the Flutter fallback. Shared core/reference remain
  separate packages; this startup implementation requires no core API change.

## 4. Validation & Error Matrix

| Condition | Behavior |
| --- | --- |
| Progress handler absent or PlatformException | Continue bootstrap and release first-frame gate |
| Native progress response remains pending | Continue bootstrap without awaiting progress |
| One local store load fails | Existing AppBootstrap catches it and still marks ready |
| Unexpected bootstrap failure | finally releases gate; original error remains visible |
| Invalid native progress | INVALID_PROGRESS, no state update |
| Progress outside [0,1] | Clamp and report success |
| Activity/engine cleanup before first frame | Clear overlay and channel handlers |
| OHOS listener registers late | Replay cached progress and continue live subscription |

## 5. Good / Base / Bad Cases

- Good: native product icon/progress stays visible and transitions directly
  to the initialized home page.
- Base: missing optional platform handler still reaches home.
- Bad: removing the native view because progress reached 1 before the ready
  home was rendered, or deferring Flutter under an Android Surface pre-draw gate.

## 6. Tests Required

- Use the actual test binding/layout to prove defer-before-runApp, initial
  layout before load, real completion progress, and ready layout while deferred.
- Verify minimum display/post-load waits, failed loads/channels, pending native
  responses, finally release and nonnative fallback.
- Run full flutter test/analyze and build/install a fresh APK. Record repeated
  light/dark cold starts, inspect actual decoded frames and foreground package,
  and verify native Python self-check plus a real editor run.
- Attempt HAP packaging and report missing gates. Do not start HarmonyOS
  devices/emulators while the standing user restriction applies.

## 7. Wrong vs Correct

```dart
// Wrong: load completion does not prove the ready page finished layout.
ready.value = true;
binding.allowFirstFrame();
// Correct: native splash removal follows the actual rendered first frame.
ready.value = true;
await binding.endOfFrame;
binding.allowFirstFrame();
```
