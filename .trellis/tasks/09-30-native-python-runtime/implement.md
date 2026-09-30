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
