# Design

## Reference

The main project's lib/main.dart defers the first Flutter frame on HarmonyOS,
passes AppBootstrap progress to qflistudio/platform.startupProgress, waits for
the ready home build/layout, and releases the first-frame gate in finally.
Its native Index.ets supplies StartupSplash to FlutterPage.splashScreenView.
FlutterPage removes that builder from its firstFrameDisplayed renderer event.
EntryAbility forwards bounded numeric progress through EVENT_STARTUP_PROGRESS.

## Shared Contract

- MethodChannel: qflistudio/platform.
- Method: startupProgress; arguments: {progress: double in [0,1]}.
- Report actual local-store completion. Missing optional handlers must not
  prevent bootstrap or releasing the first-frame gate.
- Defer before runApp on Android and HarmonyOS. Ready must be true and the
  resulting home frame must finish layout before allowFirstFrame.
- Follow the reference's short minimum native display and settling time. No
  synthetic percentage may imply initialization has completed.

## Ownership

- Flutter worker: lib/main.dart, a small startup helper if justified, and
  focused Flutter lifecycle tests.
- Android worker: MainActivity.kt and necessary Android startup resources.
  Preserve qfli_py/native and its self-check registration. Ensure native draw
  is not blocked by FlutterActivity's surface first-frame pre-draw gate; inspect
  embedding APIs and use a supported render path. Dismiss only on actual ready
  Flutter UI display and clean up on activity/engine destruction.
- HarmonyOS worker: pages/Index.ets and the startupProgress branch in the
  already-dirty EntryAbility.ets. Preserve existing agreement and Python code.
  Progress listeners must unregister when the native splash disappears.
- Parent: task/spec records, platform builds, Android rendered evidence and
  scoped commits. Shared core and main reference project are read-only inputs.

## Compatibility and Recovery

The existing AppBootstrap exposes onProgress, so no shared-core API change is
needed. Other platforms keep their existing Flutter fallback. Gate release
belongs in finally. Native overlay removal is idempotent and activity recreation
cannot leave an overlay or stale channel handler behind.

## Android Rendering Decision

Use the supported opaque TextureView render mode. The embedding's default
Surface mode blocks the entire Android view tree until Flutter UI display;
the native progress view therefore cannot appear during a deferred first frame.
Texture mode has additional composition cost.

On Android 12+, replace the default system splash exit animation. Keep that
view until the native overlay has submitted a frame, then remove it
synchronously. Actual video showed blank frames during the default system
exit even when a native overlay was present. ViewTreeObserver frame-commit
callbacks are guarded by API 31, run on the UI thread, and require the existing
hardware acceleration setting. NormalTheme also uses the product icon window
background. Destruction clears the system listener and pending callback;
callbacks already posted validate the current overlay's identity.
