# Verification

## Build and Review

- Flutter startup tests: 8/8; full suite: 33/33; flutter analyze: no issues.
- Android AAPT2 compiled all main resources; final APK built and installed.
- Full-scope check agent reviewed Flutter, Kotlin, ArkTS and resources twice,
  including the video-driven system splash repair. No remaining findings.
- Signed HAP build succeeded. No HarmonyOS devices/emulators were started;
  HarmonyOS visual handoff remains unverified on hardware under the user limit.
- git diff --check passed.

## Android Rendered Evidence

Independent device: emulator-5560, Android 17 x86_64 with 16 KiB pages and a
software GPU. Original-resolution startup recordings found a short blank
interval during the default system splash exit. Decoded light frames 22/23
were blank at 4.360633/4.393578 seconds; dark frame 38 was also blank.
Android now retains the system splash until the native overlay submits a
frame, then removes it synchronously.

The final recordings use 540x1212 at density 210, preserving the logical
viewport of the original 1080x2424 at density 420 while reducing software
recording overhead. Every actual decoded video frame was inspected for
visible app content; montage padding was excluded. Native icons/progress
and final home frames were also visually inspected.

| Final cold start | Actual frames | Blank frames | Home reported fully drawn |
| --- | ---: | ---: | ---: |
| startup-light-final-1 | 52 | 0 | 5.377 s |
| startup-dark-final-1 | 69 | 0 | 4.573 s |
| startup-light-final-2 | 86 | 0 | 4.797 s |

- Total: 207 decoded frames, no blank frames in the final recordings.
- All three launches reported COLD and foreground package com.azurekiln.qfli.pyflow.
- Native product image/progress stays visible before a usable home page.
- Each launch passed all 36 real native JNI self-checks.
- After the final launch, the editor ran src/example_custom.py through
  MicroPython 1.24.1; stdout was 424242 and exit code was 0.
- No application fatal exception or Flutter error was found in the captured logs.
- Debug/software-emulator timings are evidence of completion, not a production
  performance benchmark. Android versions before 12 were build/API reviewed;
  their visual startup was not separately recorded.

Generated evidence is retained under build/startup-verification/ and
build/content-import-device/startup-final-python-run.png, outside Git.

## Artifacts

- APK: build/app/outputs/flutter-apk/app-debug.apk
  - SHA256: DB89D972E6B8809F9BFD6524F0A2D72A10AC47004DECAED2F4F72440DF1EEB3D
- HAP: build/ohos/hap/entry-default-signed.hap
  - SHA256: CC4C02ACC5D0CE6CC928627D4BDC1BC4E452FC052946D32F0945B4FDC2F0ACB7

## Scope

Shared core and the main reference project were read-only inputs. Existing
OHOS agreement route/import/page registration and untracked workspace/editor
configuration were preserved. Only startup hunks of EntryAbility are staged.
The startup contract is documented in the intentionally local Trellis spec
frontend/native-startup.md; no ignored spec/journal paths are force-added.
