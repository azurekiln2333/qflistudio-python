# Final verification — 2026-10-15

Repository: `D:/MyNewProjects/qfli_python`, branch
`release/python-storefront-20261015`. Coordinator `wA:p1`; verified Python Pi
workers `wA:p5`, `wA:p6`, `wA:p8`. All commits use explicit owned paths.

## Delivered behavior

- Both standalone and editor terminal commands use the registered Python
  delegate and the same real `PythonProgramRunner` as editor Run. Version
  output probes the actual runtime. Unsupported REPL/options/argv report an
  explicit error. Sandbox containment, nested entries, project-root input,
  stdout/stderr/status, cancellation and `.mpy` routing have regression coverage.
- OHOS uses asynchronous NAPI work and Promise completion, complete capability
  detection, controlled cancellation and upstream bytecode. Validation rejects
  NUL, invalid argument types and malformed numeric values. Legacy synchronous
  adapters and synchronous exceptions complete/clean up correctly. Failed queue
  preparation releases its C++ work context.
- Python's offline profile reuses shared navigation gates for Git/cloud/login/
  account/AI. Android release has no INTERNET permission. OHOS retains INTERNET
  for the existing legal-agreement WebView; normal product entry points remain
  offline. Removed the unused AGC placeholder metadata.
- Coordinated shared About identity correction in core commit `8b33443`:
  profile-based product name and offline description, with four widget cases.
- Replaced OHOS scaffold vendor/descriptions. Preserved the stale ignored
  x86_64 backend SO outside packaging; the arm64 HAP now contains exactly the
  matching `libapp.so`, `libflutter.so` and latest `libqfli_py.so`.
- All 120 paired tutorials/examples are substantive and validated individually:
  116 execute in the actual embedded MicroPython runtime; four explicitly use
  external CPython. No regeneration was needed. Preserved 1,500 non-Python
  entries and user-created data.
- Completed project-specific Trellis guidelines and archived the completed
  bootstrap/curriculum tasks. Shared-core source changes remain with their
  coordinated owners; no sibling app source was edited by Python workers.

## Executed checks

| Check | Result | Evidence |
| --- | --- | --- |
| Full app static analysis after core `8b33443` | No issues, 5.6 seconds | `build/python-final-analyze.log` |
| Full app Flutter tests | 91/91 | `build/python-final-tests.log` |
| Real Windows FFI smoke | 34/34 | `dart run tool/python_ffi_smoke.dart` |
| Real Linux C VM via WSL | 65/65 | `native/tests/run_host.sh` in `qfli-java-build` |
| Actual OHOS channel handler with platform/native doubles | 20/20 | `native/tests/ohos_channel_test.cjs`; not a device/VM test |
| Android real-device JNI debug self-check | 46/46 | `android-device.md`; fresh debug APK after terminal cwd fix |
| Shared terminal/editor/offline/sandbox suites | 25/16/33/25 passed | `shared-terminal-compat-wA-p8.md` |
| Shared About dialog | 4/4, analyzer clean | `core-about-identity.md` |
| Shared Python curriculum/render/import suites | 9/3/36 passed | `curriculum-audit-wA-p8.md` |
| Curriculum real-runtime/output audit | 120/120; asset mismatch 0 | `curriculum-audit-wA-p8.md` |
| Final OHOS native build/dependencies | Pass; only ace_napi, hilog_ndk, libc | `build/python-ohos-native.log`; native build logs |
| OHOS ArkTS source/package parity | Identical SHA256 `65FEF0F8F32677FCBC2363FC6BA6E611A2493C321910310D58216EB67CB70BCF` | `runtime-review.md` |
| Final Android release build after core `8b33443` | Pass, 75.8 seconds | `build/python-release-android.log` |
| Final signed OHOS release build after core `8b33443` | Pass, 104.6 seconds | `build/python-release-ohos.log` |

The independent final runtime review found no remaining finding. Historical
worker reports retain earlier intermediate counts; the final app count is 91
and the final channel-handler count is 20. Test doubles are not native device
evidence. Each platform's installed build is identified separately.

## Final build artifacts

| Artifact | Bytes | SHA256 |
| --- | --- | --- |
| `build/app/outputs/flutter-apk/app-release.apk` (20:03:32 +08) | 72,878,894 | `6549B2DF3125526EB944CC0EB2EF1CA983155BE6933D16C4C71A7F6D8AE46059` |
| `build/ohos/hap/entry-default-signed.hap` (20:06:05 +08) | 38,482,585 | `7917A010E0F577B463009066DD48212E992C60407DC947A45667D3E3FA2B7270` |

These hashes supersede earlier release builds in the worker's historical device
record. Android APK inspection confirms no INTERNET permission. Packaging,
signing and device conclusions below must remain distinct from build success.
Android final release passes `zipalign -c -P 16 4` and APK v2 signature
verification. Full ELF/ABI inspection is in `platform-build.md`.

## Outstanding gates and preserved work

- Latest final OHOS HAP installed successfully on explicit target
  `192.168.68.207:46551`. Launch still returns `10106102`: screen locked and
  developer mode cannot auto-unlock. User was asked to unlock and keep the
  screen on. Fresh 17 base cases, cancellation, bytecode and 6/6 argument
  validation self-checks remain unverified on that device. Fresh final launch
  log: `build/python-release-evidence/ohos-final-launch.log`. No lock bypass.
- Android Pi `wA:p8` confirmed native JNI46, app-created audit project and
  editor opening its `src/main.py`. Standalone/editor execution gestures,
  compile/stop and final release JNI usability remain unverified through UI.
  The bounded final check found peer `webforge` foreground; no competing
  release install/launch was attempted. SQL was notified that Python released
  its window. UI dumps also intermittently returned null; an enabled user
  accessibility auto-clicker was observed, but no causal isolation was done
  and it was not disabled. JNI46 does not establish these UI cases.
- Android release uses the existing debug signing configuration; OHOS uses the
  existing debug signing profile/certificate. Store-distribution signing is
  not established. No credentials were generated, replaced or exposed.
- Native Apple build/device verification requires an Apple host/Xcode, which
  is unavailable. Full Windows Flutter packaging lacks MSVC. Real Windows and
  Linux runtime checks above do not imply those platform builds passed.
- Initial unrelated OHOS icons, EntryAbility, route/AgreementReader work and
  local agent/tool configuration remain outside commits. The original dirty
  packaged SO was backed up under ignored `build/python-release-evidence/`
  before replacement with the reviewed, freshly built library.

## Commits and task disposition

Key Python product commits: `77f46d5` (OHOS async controls/runner), `7286cd9`
(terminal delegate/offline integration), `189d589` (NAPI/prepareRun cleanup),
`0b5d833` (OHOS metadata/packaging contract). Shared core About fix: `8b33443`.
Bootstrap, curriculum and terminal presentation tasks are archived. The current
task and native-runtime task remain open for the explicit device gates above.

The release and native-runtime tasks remain in progress while their hardware
gates are open. Completed work is committed; an open gate is not a code pass.
