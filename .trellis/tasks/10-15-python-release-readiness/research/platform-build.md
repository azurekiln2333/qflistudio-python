# Research: Platform builds and runtime verification

- Query: Determine reproducible Windows/native, Android and OHOS build and verification paths, actual local tools/device targets, and missing release/runtime gates.
- Scope: internal (repository source, installed SDK metadata and read-only device listings)
- Date: 2026-10-15
- Repository: `D:/MyNewProjects/qfli_python`; CWD and Git root were verified to match. No sibling workspace was modified. Research only: no builds, installs, launches, device state changes, staging or commits were performed.

## Final artifact verification (2026-10-15 20:09, read-only follow-up)

This section supersedes initial artifact/runtime-gap observations below. The initial survey remains historical. Current OHOS sources now implement asynchronous controlled execution, cancellation and bytecode transport; both final ArkTS copies match SHA256 `65FEF0F8F32677FCBC2363FC6BA6E611A2493C321910310D58216EB67CB70BCF`.

Coordinator identifies the final shared-core snapshot as `8b33443` (About identity correction, four focused checks). Existing final app logs independently show **91 tests passed**, analyzer **No issues found (5.6s)**, Android release build **75.8s**, and OHOS release build **104.6s**. No additional builds or tests were run by this researcher.

| Current final release artifact | Bytes | Modified (Asia/Shanghai) | SHA256 |
| --- | --- | --- | --- |
| `build/app/outputs/flutter-apk/app-release.apk` | 72,878,894 | 2026-10-15 20:03:32 | `6549B2DF3125526EB944CC0EB2EF1CA983155BE6933D16C4C71A7F6D8AE46059` |
| `build/ohos/hap/entry-default-signed.hap` | 38,482,585 | 2026-10-15 20:06:05 | `7917A010E0F577B463009066DD48212E992C60407DC947A45667D3E3FA2B7270` |

The final HAP under `ohos/entry/build/default/outputs/default/entry-default-signed.hap` has the same bytes, time and SHA256 as the Flutter output above. Detailed per-library ELF data and package metadata are saved in ignored `build/python-release-evidence/final-artifacts-platform.json`.

### Previous artifact snapshot (historical; superseded)

| Historical artifact | Bytes | Modified (Asia/Shanghai) | SHA256 |
| --- | --- | --- | --- |
| `build/app/outputs/flutter-apk/app-debug.apk` | 154,050,333 | 2026-10-15 19:32:53 | `362BC9269C7404983C555F91FE782C534EE8B28F6D843ECEA072D315BC9E7860` |
| `build/app/outputs/flutter-apk/app-release.apk` | 72,878,894 | 2026-10-15 19:37:37 | `2F160DB71DB1D824D413610ADE69B7D7C7570A84526B8B143C1FCD5263AB6811` |
| `ohos/entry/build/default/outputs/default/entry-default-signed.hap` | 39,293,440 | 2026-10-15 19:33:15 | `B99C89C10F7703529DA2371918AF333B2F93218E70FA43B224B80536396DB232` |
| `ohos/entry/build/default/outputs/default/entry-default-unsigned.hap` | 38,974,673 | 2026-10-15 19:33:12 | `3AD25003E36765E3EB1F1D666C504612B0DEC1ACEFEEA25F6B6915E5108F309F` |

### Checks against the current final releases

Independent final checks used Android build-tools **36.1.0**:

- `aapt2 dump permissions app-release.apk`: **no INTERNET**; only generated `com.azurekiln.qfli.pyflow.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`. Packaged ID `com.azurekiln.qfli.pyflow`, version 1.0.0+1, compile/target SDK 36, min SDK 24.
- `zipalign -c -P 16 4 app-release.apk`: **exit 0**.
- In-memory ZIP/ELF parsing: all nine Android native libraries across armeabi-v7a, arm64-v8a and x86_64 have LOAD alignment at least `0x4000`; every qfli_py uses `0x4000` and needs exactly `libm.so`, `libdl.so`, `libc.so`. App/engine libraries use `0x4000` or `0x10000` as appropriate.
- Final signed HAP contains **exactly three** native libraries, all arm64: `libapp.so`, `libflutter.so`, `libqfli_py.so`; no x86_64 library remains. Coordinator preserved the stale ignored x86_64 library at `build/python-release-evidence/initial-stale-x86_64-libqfli_py.so` before rebuilding.
- Packaged arm64 qfli_py exports `qfli_py_execute` and all cancellation create/request/free symbols; NAPI createCancel/cancel/freeCancel names are present. DT_NEEDED is exactly `libace_napi.z.so`, `libhilog_ndk.z.so`, `libc.so`. OHOS engine/native 4 KiB ELF alignment is separate from Android's 16 KiB requirement.
- Packaged HAP module confirms bundle/version, corrected vendor **`azurekiln`**, INTERNET and READ_PASTEBOARD permissions; placeholder client_id metadata is absent. Existing offline audit intentionally retained INTERNET for the preserved legal-page webview; Android release has no INTERNET.
- Android release signing remains configured to debug keys. Earlier 19:37-artifact `apksigner verify` passed with v2 and **`C=US, O=Android, CN=Android Debug`**, certificate SHA256 `3cf19ed8102760001b3d92f3e4f42a6e322a89ba987d93247b5f9d6afebc0b51`. Production Android signing remains an external release gate; the earlier certificate check is not presented as a fresh check of the 20:03 artifact.
- OHOS signing config still references existing Debug profile/certificate files. Production store-distribution suitability is unverified; no signing credentials were changed or logged by this researcher.

Device evidence remains tied to its actual artifacts: `android-device.md` and raw `native-selfcheck-debug-2.log` prove the earlier **19:32 debug** APK's actual-device **46/46** native checks. Neither that earlier debug result nor historical release SHA256 `C65082...`/`2F160D...` establishes execution of the final 20:03 release APK. Coordinator reports the Android foreground is held by a peer WebForge session, so no final release install was attempted; interactive terminal/editor UI and release-after-shrinking execution remain unverified for the final package. The earlier OHOS build/install record's launch error **10106102** came from a locked device; final HAP installation and runtime evidence belong to the coordinator's verification record.

This follow-up built/installed/launched nothing and changed no product/core/platform source, SDK, Git state or device state. Only this research report and the explicitly authorized ignored final artifact JSON were written.

## Initial survey (historical; superseded by final verification above)

### Task and specifications

Read this task's `prd.md`, `design.md` and `implement.md`, `.trellis/workflow.md`, backend index, `android-build.md`, `native-python-runtime.md`, `python-ffi.md` and frontend `native-startup.md`. Main-session authorization already covers builds and attempted deployment. The startup spec's earlier standing device restriction is historical; use current authorization and explicit targets, preserving peer sessions.

The initial task PRD contained a second appended scaffold (`Requirements: TBD` / unchecked TBD acceptance) after its substantive requirements; this was reported to the coordinator for planning-artifact cleanup.

### Installed tools and SDK selection

| Item | Read-only observation |
| --- | --- |
| Working Flutter | `D:/ProgramFiles/flutter_ohos/bin/flutter.bat`; PATH, Android/OHOS local.properties and `.dart_tool/package_config.json` agree |
| Flutter identity | Cache JSON: `3.27.5-ohos-1.0.1`, revision `12587c79e88aacf3172a84e536f226457d037594`; bundled Dart `3.11.5`; engine `42d3d75a56efe1a2e9902f52dc8006099c45d937` |
| Separate Flutter checkout | `D:/ProgramFiles/flutter` exists on master, but `bin/cache/flutter.version.json` and `bin/cache/dart-sdk/bin/dart.exe` are absent; many `dart-sdk.old*` directories remain. It is not a ready alternative SDK. Do not repair/change this shared installation as part of this Python task |
| Android SDK | `D:/ProgramData/Android/Sdk`; platforms 34, 35, 36, 36.1; build-tools 35.0.0, 36.1.0, 37.0.0 |
| Pinned Android NDK | `27.0.12077973`, valid `source.properties`; also installed 28.2.13676358 |
| Android CMake/Ninja | Both executables exist at `D:/ProgramData/Android/Sdk/cmake/3.22.1/bin/` |
| Windows C compiler | `D:/ProgramFiles/Dev-Cpp/MinGW64/bin/gcc.exe` exists; not on current PATH |
| Java | `JAVA_HOME=D:/ProgramFiles/Java/jdk-25`; DevEco JBR is 25.0.2; Android Studio JBR `D:/ProgramFiles/Android/Android Studio/jbr` is 21.0.10. Flutter settings contain no explicit `jdk-dir` |
| OHOS SDK | `D:/ProgramFiles/Huawei/DevEco Studio/sdk/default`, metadata HarmonyOS 26.0.0, API 26, SDK 26.0.0.105; native and toolchains packages present |
| OHOS native builder tools | `<DevEco>/sdk/default/openharmony/native/build-tools/cmake/bin/{cmake,ninja}.exe`, `native/build/cmake/ohos.toolchain.cmake`, `<DevEco>/plugins/app-analyzer/lib/python/python.exe` all exist |
| Hvigor / ohpm | `D:/ProgramFiles/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat`; `tools/ohpm/bin/ohpm.bat` on PATH |
| adb | `D:/ProgramFiles/platform-tools/adb.exe` |
| hdc | PATH selects `D:/ProgramFiles/Huawei/OpenHarmony/Sdk/23/toolchains/hdc.exe`; DevEco's API-26 toolchain also contains hdc.exe |

The local OHOS Flutter SDK contains both old Groovy and current Kotlin FlutterExtension definitions. Current Kotlin extension specifies compileSdk/targetSdk 36 and minSdk 24; do not infer the final packaged manifest from the older Groovy defaults (35/21). Inspect the built APK. `android/app/build.gradle.kts:9` pins NDK 27 regardless of the SDK extension's default NDK 28. Gradle wrapper is 8.14, AGP 8.11.1, Kotlin 2.2.20 (`android/settings.gradle.kts`).

Prefer the existing working OHOS Flutter for this task's Dart, analyzer, tests and both app platforms. Serialize Pub work in the same package; do not globally change Flutter config/JDK or shared SDK installations. If Java 25 causes Gradle incompatibility, use the installed Android Studio JBR 21 in the build process environment; Flutter doctor verbose can confirm which Java Flutter actually selects.

### Files found and source contracts

| File | Purpose / concrete contract |
| --- | --- |
| `native/desktop/build.ps1` | Standalone Windows DLL builder with explicit compiler/CMake/Ninja/build-directory and jobs options |
| `native/desktop/CMakeLists.txt:11` | Compiles tracked MicroPython embedding sources; fails if fewer than 100 translation units; includes shared adapters and FFI; static GCC runtime on MinGW |
| `native/windows/CMakeLists.txt:4` | Flutter FFI plugin bundles the same desktop target |
| `native/tests/run_host.sh:7` | POSIX GCC C bridge/VM smoke builder; output `native/build/host/qfli_py_smoke` |
| `native/tests/smoke.c:41` | `/proc/self/fd` counting makes this a Linux host test, not a portable native Windows test |
| `tool/python_ffi_smoke.dart:7` | Standalone real-library tests; immediately fails if probe unavailable; takes optional explicit library path |
| `test/python_ffi_test.dart:177` | Real runner test silently skips if native DLL/SO is absent |
| `test/python_lifecycle_test.dart:305` | Full native lifecycle group also silently skips if DLL/SO absent; build first |
| `native/src/qfli_py_bridge.h:49` | Cancellation token create/request/free and controlled execute API shared by desktop/Android |
| `native/src/qfli_py_bridge.h:81` | Controlled execute supports compile-only, cancellation token, artifact output and bytecode input; legacy API retained |
| `native/build.ps1:210` | OHOS builder checks/fetches fixed MicroPython v1.24.1 / commit `ecfdd5d`; first clone is build-time networking |
| `native/CMakeLists.txt:72` | OHOS CMake can regenerate tracked `micropython_embed/` during configuration when stale; do not run concurrently with Android compilation reading those sources |
| `native/CMakeLists.txt:267` | Static C++ link is mandatory; post-build dependency checker rejects unsupported dynamic dependencies |
| `native/android/CMakeLists.txt:9` | Parallel ABI builds read tracked embedding sources; excludes text-included C units; shared C VM plus JNI |
| `native/android/CMakeLists.txt:35` | Android uses upstream setjmp GC register capture and 16 KiB ELF alignment link options |
| `android/app/src/main/kotlin/com/example/qflistudio/c/MainActivity.kt:47` | Package is `com.azurekiln.qfli.pyflow` despite old directory name; registers native channel and startup self-check |
| `android/app/src/debug/kotlin/com/azurekiln/qfli/pyflow/QfliPySelfCheck.kt:55` | 36 base cases plus 10 lifecycle/artifact checks; profile/release provide no-op variants |
| `native/src/qfli_py_napi.cpp:123` | Current OHOS NAPI run synchronously calls legacy tokenless `qfli_py_run` |
| `native/ohos/QfliPyNative.ets:286` | OHOS channel currently supports available/run/checkSyntax only; no controlled run, stop or reusable artifact transport |
| `ohos/entry/src/main/ets/entryability/EntryAbility.ets:46` | Registers packaged native channel copy |
| `native/tools/check_so_deps.py` | Pure Python DT_NEEDED gate; no readelf dependency |
| `native/tools/inspect_so.py` | Diagnostic ELF identity/upstream symbol/C++ dependency inspection |

The VM is upstream MicroPython 1.24.1, not CPython. Finite input and buffered output, imports, file I/O, state isolation, exit status, compile-only and C result ownership are specified. CPython extension modules/pip, networking, interactive stdin and arbitrary blocking-I/O interruption are unsupported. OHOS controlled-run transport is currently absent and synchronous dispatch can block ArkTS/UI on an infinite loop; coordinator and runner worker must assess capability gating or implementation before claiming parity.

### Reproducible host verification

Run from the verified Python root. The commands below are proposed execution commands, not results from this research.

```powershell
./native/desktop/build.ps1 -Compiler D:/ProgramFiles/Dev-Cpp/MinGW64/bin/gcc.exe -CMake D:/ProgramData/Android/Sdk/cmake/3.22.1/bin/cmake.exe -Ninja D:/ProgramData/Android/Sdk/cmake/3.22.1/bin/ninja.exe -Jobs 2
& D:/ProgramFiles/flutter_ohos/bin/cache/dart-sdk/bin/dart.exe --packages=.dart_tool/package_config.json tool/python_ffi_smoke.dart native/build/windows/qfli_py_ffi.dll
& D:/ProgramFiles/flutter_ohos/bin/flutter.bat test --no-pub
& D:/ProgramFiles/flutter_ohos/bin/flutter.bat analyze --no-pub
```

- DLL output: `native/build/windows/qfli_py_ffi.dll`; existing DLL observation: 713,342 bytes, 2026-10-15 18:07 local. This timestamp alone is not test evidence.
- Dart real FFI smoke expected Windows count: **34**. It verifies finite stdin/EOF, Unicode source/paths/streams, independent stderr, import refresh, filesystem effects/path containment, compile-only, exception/exit recovery, globals reset, truncation and eight concurrent calls.
- Lifecycle Flutter group verifies real loop/sleep cancellation, pre-start/queued cancellation, token isolation/recovery and `.mpy` execution after deleting source, failed compile retention and bytecode/path errors.
- Linux: `sh native/tests/run_host.sh` builds/runs **65** C checks (44 check call sites, one repeated 20 times, plus two explicit checks). Requires Linux `/proc`, GCC/pthread and Unix filesystem semantics. Windows Git Bash alone does not establish Linux native behavior. A Windows DLL pass is separate from a full Flutter Windows GUI build, which requires Visual Studio C++ tools.

### Android build, packaging and runtime

```powershell
& D:/ProgramFiles/flutter_ohos/bin/flutter.bat build apk --debug --no-pub
& D:/ProgramFiles/flutter_ohos/bin/flutter.bat build apk --release --no-pub
& D:/ProgramData/Android/Sdk/build-tools/36.1.0/zipalign.exe -c -P 16 -v 4 build/app/outputs/flutter-apk/app-release.apk
& D:/ProgramData/Android/Sdk/build-tools/36.1.0/apksigner.bat verify --verbose --print-certs build/app/outputs/flutter-apk/app-release.apk
& D:/ProgramData/Android/Sdk/build-tools/36.1.0/aapt2.exe dump badging build/app/outputs/flutter-apk/app-release.apk
```

- Outputs: `build/app/outputs/flutter-apk/app-debug.apk` and `app-release.apk`; all configured ABIs are armeabi-v7a, arm64-v8a and x86_64. `--split-per-abi` can produce independent outputs when needed; the ordinary universal APK is the primary configured deliverable.
- Inspect ZIP entries for `lib/<abi>/libqfli_py.so`, `libflutter.so`, `libapp.so` and each plugin library. Extract to an ignored task-specific directory, then use `D:/ProgramData/Android/Sdk/ndk/27.0.12077973/toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-readelf.exe -lW <library>` and `-dW <library>`. Verify relevant LOAD segments align at least `0x4000`; verify package ZIP alignment too. Do not infer plugin/engine alignment from only qfli_py's CMake flags.
- Android qfli_py historically needs only `libm.so`, `libdl.so`, `libc.so`; verify fresh actual DT_NEEDED and ensure any additional non-system dependency is packaged.
- APK manifest must identify `com.azurekiln.qfli.pyflow`, actual SDK versions and intended release permissions. Debug/profile INTERNET comes from development manifests; inspect the final release merged package separately.
- **Store-signing gap:** `android/app/build.gradle.kts:57` signs release with debug signing configuration. A successful release build does not establish production store signing or an AAB deliverable.

Read-only `adb devices -l` returned one connected device:

```text
adb-d361e7a0-gqqQSM (2)._adb-tls-connect._tcp  device product:OPD2413 model:OPD2413 device:OP615EL1 transport_id:1
```

Quote the exact serial in PowerShell because it contains spaces and parentheses. Requery immediately before any authorized use; no emulator was listed. Proposed explicit runtime path:

```powershell
& D:/ProgramFiles/platform-tools/adb.exe -s 'adb-d361e7a0-gqqQSM (2)._adb-tls-connect._tcp' install -r build/app/outputs/flutter-apk/app-debug.apk
& D:/ProgramFiles/platform-tools/adb.exe -s 'adb-d361e7a0-gqqQSM (2)._adb-tls-connect._tcp' shell am start -n com.azurekiln.qfli.pyflow/.MainActivity
& D:/ProgramFiles/platform-tools/adb.exe -s 'adb-d361e7a0-gqqQSM (2)._adb-tls-connect._tcp' logcat -d -s QfliPyNative
```

Require fresh **46/46** debug JNI self-check evidence and a real editor project importing a helper, consuming input.txt, separating stderr, writing a file, stopping a loop and executing `.mpy` after source removal. Release has no startup self-check; operate the actual UI after release install to verify shrinking preserves JNI. Check foreground package before attributing screenshots. Installation/device authorization failures must remain separate from build results.

### OHOS native library, HAP and runtime

First build native serially relative to Android source consumption:

```powershell
./native/build.ps1 -Abi arm64-v8a -BuildType Release -DevEcoHome 'D:/ProgramFiles/Huawei/DevEco Studio'
python native/tools/check_so_deps.py native/build/cmake-arm64-v8a/libqfli_py.so
python native/tools/inspect_so.py native/build/cmake-arm64-v8a/libqfli_py.so
Get-FileHash native/ohos/QfliPyNative.ets,ohos/entry/src/main/ets/plugins/QfliPyNative.ets -Algorithm SHA256
& D:/ProgramFiles/flutter_ohos/bin/flutter.bat build hap --release --no-pub --target-platform ohos-arm64
```

- `native/build.ps1` output: `native/build/cmake-arm64-v8a/libqfli_py.so`, logs `configure.log`, `build.log`, `check_so_deps.log` and `.err` files. Default copies it to `ohos/entry/libs/arm64-v8a/libqfli_py.so`; `-SkipCopy` avoids replacing the existing initial dirty packaged SO while investigating.
- Preserve initial unrelated dirty `ohos/entry/libs/arm64-v8a/libqfli_py.so` until overlap is explicitly reviewed. The coordinator owns staging decisions.
- Native CMake and post-build check require static C++; expected current dependencies are `libace_napi.z.so`, `libhilog_ndk.z.so`, `libc.so`. Checker's wider allowlist also contains musl base libraries, libunwind and libz; no `libc++_shared.so` or `libstdc++.so`.
- Both ArkTS copies matched at observation: SHA256 `89EC5E7FB7AEBFDBBA53010CD1E1F92E08F5ACCD832AB643D9566C7F0243127C`. Rehash after worker changes.
- Full Flutter `build hap` compiles current Dart assets before Hvigor. Direct Hvigor alone can reuse stale Flutter assets. If direct repackaging is needed, cwd **must be** `D:/MyNewProjects/qfli_python/ohos`, command `& 'D:/ProgramFiles/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat' assembleHap --mode module -p product=default -p buildMode=release --no-daemon`.
- Expected HAP outputs: `ohos/entry/build/default/outputs/default/entry-default-signed.hap` and `entry-default-unsigned.hap`. Inspect the final ZIP for packaged arm64 qfli_py and plugin/Flutter libraries, then inspect the packaged stripped SO's DT_NEEDED too.
- Signing configuration references existing `.p12`, debug `.cer` and `QFLIPyFlow920Debug.p7b` files in `D:/Keystore`. Do not copy passwords into logs/research. File existence was checked; store-distribution suitability and device entitlement were **not** established.
- Product compatible SDK is 5.1.0(18), target is 26.0.0, bundle `com.azurekiln.qfli.pyflow`; at the initial survey AppScope vendor and package descriptions still contained template metadata. The final release corrected vendor to `azurekiln` and replaced the descriptions, as confirmed by the coordinator and final packaged vendor check above.
- Current OHOS module requests INTERNET and has `REPLACE_WITH_AGC_CLIENT_ID` metadata (`ohos/entry/src/main/module.json5:27,43`); report to offline/profile owner. Runtime UI gating and manifest permission policy are separate concerns.

Read-only `hdc list targets` returned `192.168.68.207:46551`. Requery and use an explicit target on every command. Proposed authorized runtime path, without changing connection/device state:

```powershell
& 'D:/ProgramFiles/Huawei/OpenHarmony/Sdk/23/toolchains/hdc.exe' -t 192.168.68.207:46551 install -r ohos/entry/build/default/outputs/default/entry-default-signed.hap
& 'D:/ProgramFiles/Huawei/OpenHarmony/Sdk/23/toolchains/hdc.exe' -t 192.168.68.207:46551 shell aa start -a EntryAbility -b com.azurekiln.qfli.pyflow
& 'D:/ProgramFiles/Huawei/OpenHarmony/Sdk/23/toolchains/hdc.exe' -t 192.168.68.207:46551 shell hilog -x
```

Use filtered fresh logs for `QfliPyNative`, module loading and MUSL-LDSO without globally clearing peer logs. Current source startup expectation is **17/17** OHOS cases; update expectations if worker expands it. Device self-check is actual ArkTS -> NAPI -> C VM evidence; signed HAP alone is insufficient. Normal standalone/editor workflows remain necessary beyond startup checks.

### Existing artifacts are not fresh validation

At observation, debug APK (188,866,282 bytes) and signed HAP (159,117,317 bytes) were dated 2026-10-11; release APK (70,925,142 bytes) was dated 2026-10-01; native OHOS built SO (2,517,608 bytes) was dated 2026-10-08. These establish expected locations only. Record fresh build exit codes, logs, hashes, manifests/dependencies/alignment and explicit installed-device outcomes after current changes.

## External References

No web documentation was needed. Tool/version claims come from local SDK package metadata, Dart/Flutter cached version metadata, installed JBR release files and current repository/SDK command sources. `D:/ProgramFiles/flutter_ohos/packages/flutter_tools/lib/src/commands/build_hap.dart:40` supports ohos-arm64/ohos-arm/ohos-x64 and defaults to signed device builds; source confirms --release and --no-pub support.

## Related Specs

- `.trellis/spec/backend/native-python-runtime.md`: C runtime, JNI/NAPI, cancellation/artifacts, required dependency/package/device checks.
- `.trellis/spec/backend/python-ffi.md`: FFI ownership/loading and real-host verification.
- `.trellis/spec/backend/android-build.md`: SDK/NDK, memory budgets and explicit target evidence. Its earlier 36-case description is superseded by current source's 46 total.
- `.trellis/spec/frontend/native-startup.md`: native startup/frame evidence and preserving channel registration.

## Caveats / Not Found

- No commands in this research built, installed, launched or tested a product. Connected targets are transient observations, not authorization to disrupt a peer's active app or evidence of execution success.
- Native PLATFORMS.md contains an outdated statement that cancellation/artifacts do not exist. `native/lifecycle.md` and current controlled C API/source supersede it for desktop/Android; OHOS still lacks transport parity.
- No production Android signing config or OHOS store distribution verification was found. Do not silently generate or replace release credentials.
- Apple execution needs an Apple host/Xcode; a Linux host suite needs a real Linux environment. Windows standalone native validation does not cover these targets.
- SDK/native regeneration and builds can change generated tracked inputs. Coordinator must review semantic generated changes, incidental timestamps/line endings and the initial dirty OHOS baseline before each explicit-path Conventional Commit.
