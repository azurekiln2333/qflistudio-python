# Native CI contract

## 1. Scope / Trigger

Apply when changing .github/workflows/native-build.yml, native-ohos.yml, native-apple.yml or their
native build helpers. This is native-only GitHub-hosted CI, independent of Flutter
and adjacent shared-core repositories. See native/CI.md for user instructions.

## 2. Signatures

```text
sh native/desktop/build.sh
QFLI_APPLE_TARGET=<ios|macos> bash native/tools/ci_apple_build.sh
OHOS_SDK_NATIVE=<native-sdk> QFLI_OHOS_ABI=<arm64-v8a|x86_64> bash native/tools/ci_ohos_build.sh
python tool/python_native_provenance.py capture|finish|verify <existing arguments>
```

## 3. Contracts

- Use hosted runners, contents:read permissions, bounded job timeouts and exact ABI names.
- Selected publication targets are Android, OHOS, iOS and macOS. Existing compiler
  toolchains are used to build the project's runtime libraries, not rebuilt themselves.
- Pin Android NDK 27.0.12077973 and keep static C++ / 16 KiB ELF checks.
- Pin the official OHOS SDK bundle and checksum. Record native SDK version/API and
  source commit. An OpenHarmony SDK build does not establish HarmonyOS device acceptance.
- Apple/Android read tracked embedding inputs. OHOS initializes only the pinned
  MicroPython submodule and regenerates embedding inputs with the target compiler.
- Complete capture/build/dependency/finish/verify for one OHOS ABI before starting
  another ABI, because regeneration changes the shared embedding package.
- Upload only passing target outputs, SHA256SUMS, BUILD_INFO.txt and small reports.
  Set 14-day artifact retention. Never upload SDKs, CMake trees or private credentials.
- Include root GPL-3.0 LICENSE and the pinned upstream LICENSE-MicroPython in artifacts.
- QFLI_PY_LIBRARY_TYPE accepts SHARED (default) or STATIC. iOS requires STATIC;
  desktop default behavior stays shared. Keep common source selection in one CMake target.
- Use Xcode SDKs with explicit deployment minimums: iOS device13/simulator14,
  macOS ARM64 11/x86_64 10.15. Inspect the actual Mach-O platform per slice.
- The current origin remote has multiple push URLs. A GitHub-only request must push
  to the explicit GitHub repository URL, not all configured push destinations.

## 4. Validation & Error Matrix

| Condition | Required outcome |
| --- | --- |
| C smoke/debugger failure | Target fails; no passed library upload |
| SDK checksum mismatch | Stop before extracting or executing SDK tools |
| Unexpected ELF dependency/alignment | Target fails |
| OHOS source/tool/SDK drift | Provenance fails; no passed library upload |
| One OHOS ABI fails | Other ABI may complete; overall job still fails |
| Cross-compilation passes | Build evidence only; device gate remains separate |

## 5. Good / Base / Bad Cases

Good: download a run's ABI library and verify SHA256 plus source/toolchain metadata.
Base: the Mac debugger suite loads the exact dylib that will be uploaded.
Bad: call a self-hosted local build a cloud build that saves local disk space.

## 6. Tests Required

Run actionlint and Bash syntax checks before pushing. Observe actual cloud job results.
Check ZIP members, digests and ELF/Mach-O machine identities for published outputs.
Keep native runtime tests on executable host targets. A successful YAML parse alone
is not a successful build. Existing unrelated Flutter/device acceptance remains open.

Resolve temporary test roots with Path.resolve() before comparing paths returned by
the native runtime. Hosted Windows TEMP can contain an 8.3 alias such as RUNNER~1;
macOS /var may resolve to /private/var. Preserve path equality assertions and resolve
the fixture root instead of weakening assertions or altering native paths.

## 7. Wrong vs Correct

Wrong: ship an iOS dylib with a macOS platform identifier as an iPhone library.
Correct: compile with the matching iPhoneOS/iPhoneSimulator SDK and package distinct
device and simulator slices in an XCFramework. Inspect platform and architecture metadata.

Wrong: delete all ohos/entry/libs files because .gitignore mentions that directory.
Correct: check git ls-files; the ARM64 libqfli_py.so is tracked in this repository.
