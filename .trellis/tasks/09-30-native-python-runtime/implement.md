# Implementation Plan

- [x] Inspect current native, Dart, ArkTS, build, test, and device state.
- [x] Build the existing arm64 library and signed HAP; install and launch on a device; record the real self-check result.
- [x] Make each C VM invocation independent and run packaged on-device C VM checks for compile/run, errors, input, exit, and repeat runs (7/7).
- [ ] Pass project and entry paths through Flutter, ArkTS, and NAPI; enable upstream file reading and project module import.
- [ ] Add project-local file operations through the port and test read/write and path failures.
- [ ] Add practical editor/runtime tools supported by the engine, then remove unfinished-work copy from normal app flows.
- [ ] Run focused and full checks: native build/dependency scan, native smoke on device, Flutter test/analyze, HAP build/install/self-check.
- [ ] Review spec updates and commit each coherent batch using conventional messages, staging only task-owned files.

## Build and Validation Commands

- `& .\native\build.ps1 -SkipCopy` for native compilation and dependency scan.
- `flutter test test\python_app_test.dart` and `flutter analyze` for Flutter integration.
- `hvigorw.bat assembleHap --mode module -p product=default` from `ohos` for packaging.
- `hdc install <signed-hap>`, `hdc shell aa start -a EntryAbility -b com.azurekiln.qfli.pyflow`, then inspect `QfliPyNative` hilog.

## Risk Points

- Generated `native/micropython_embed/genhdr` files are tracked and regenerate with Windows line endings and a build date. Do not stage incidental generated diffs.
- `ohos/entry/src/main/ets/entryability/EntryAbility.ets`, `main_pages.json`, and `AgreementReader.ets` were dirty before this task. Preserve them.
- The ArkTS bridge has two copies; contract edits must update both.
