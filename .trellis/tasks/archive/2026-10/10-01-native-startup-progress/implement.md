# Execution

- [x] Inspect the actual main project and existing PyFlow entry shells.
- [x] Obtain task creation and implementation consent.
- [x] Implement Flutter progress and deferred first-frame handoff.
- [x] Implement HarmonyOS splash builder and event forwarding.
- [x] Implement Android native loading surface and matching themes.
- [x] Run a full task review and repair findings.
- [x] Run Flutter tests/analyze, build APK and attempt HAP packaging.
- [x] Verify Android cold-start frames and native-to-Flutter transition.
- [x] Update startup specs and record verification evidence.

## Validation

- flutter test; flutter analyze
- flutter build apk --debug
- flutter build hap --debug (build only, no HarmonyOS device/emulator)
- Android emulator-5560 is an independent workspace-owned test instance.
  Capture startup video/frames for light and dark cold starts, then verify home
  controls and Python native availability.
- Keep builds sequential to avoid shared tool/cache pressure.

## Initial Evidence

- Main Android entry is a plain FlutterActivity; its native progress pattern is
  currently HarmonyOS-specific. This task adapts the same contract for Android.
- PyFlow Index.ets currently has no splash builder; its Dart startup currently
  submits a Flutter fallback frame before the stores finish.
- Android launch/normal themes use generic backgrounds with no explicit brand
  startup image or progress view.
- Preserve existing dirty agreement changes and do not stage unrelated files.

## Implementation Gates

- Focused startup lifecycle tests: 8/8. Full Flutter suite: 33/33.
- flutter analyze: no issues. git diff --check: clean.
- Full-scope checker reviewed Dart, Android, OHOS and resources; no findings.
- Android resource AAPT2 compilation passed; actual embedding API overrides
  and minSdk 24 compatibility confirmed.
- Fresh debug APK build passed, installed on emulator-5560.
- Android uses supported opaque RenderMode.texture so the native overlay can
  draw while Flutter is deferred. Default Surface mode prevents every Android
  view from drawing before Flutter UI display. Texture adds composition cost.
- OHOS replays cached progress and unregisters the same eventHub callback.
- Signed debug HAP build passed: build/ohos/hap/entry-default-signed.hap.
  No HarmonyOS devices/emulators were started.
- Initial Android video pixel inspection found a short system-splash exit
  blank interval (light frames 22/23, dark frame 38). API 31+ now retains the
  system view until the native overlay submits a frame, then removes it
  synchronously. NormalTheme retains the branded window background.
- Final checker re-reviewed this repair, API guards, observer merge/lifetime,
  main-thread callback and hardware acceleration prerequisites: no findings.
- Real editor run of src/example_custom.py produced 424242 and exit code 0.
- Final light/dark/repeated cold starts: 207 decoded frames, zero blanks.
  All three reached the home page and passed native JNI self-check 36/36.
  A real editor run was repeated against the final APK with the same result.
- See verification.md for artifact hashes, actual video frames and limitations.
