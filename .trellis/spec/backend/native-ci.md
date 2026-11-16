# Native CI contract

## 1. Scope / Trigger

Apply when changing .github/workflows/native-build.yml, native-ohos.yml or their
native build helpers. This is native-only GitHub-hosted CI, independent of Flutter
and adjacent shared-core repositories. See native/CI.md for user instructions.

## 2. Signatures

```text
sh native/desktop/build.sh
pwsh -NoProfile -File native/desktop/build.ps1 -Compiler <gcc.exe>
OHOS_SDK_NATIVE=<native-sdk> QFLI_OHOS_ABI=<arm64-v8a|x86_64> bash native/tools/ci_ohos_build.sh
python tool/python_native_provenance.py capture|finish|verify <existing arguments>
```

## 3. Contracts

- Use hosted runners, contents:read permissions, bounded job timeouts and exact ABI names.
- Pin Android NDK 27.0.12077973 and keep static C++ / 16 KiB ELF checks.
- Pin the official OHOS SDK bundle and checksum. Record native SDK version/API and
  source commit. An OpenHarmony SDK build does not establish HarmonyOS device acceptance.
- Desktop/Android read tracked embedding inputs. OHOS initializes only the pinned
  MicroPython submodule and regenerates embedding inputs with the target compiler.
- Complete capture/build/dependency/finish/verify for one OHOS ABI before starting
  another ABI, because regeneration changes the shared embedding package.
- Upload only passing target outputs, SHA256SUMS, BUILD_INFO.txt and small reports.
  Set 14-day artifact retention. Never upload SDKs, CMake trees or private credentials.
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
Base: Linux C smoke links the exact shared library that will be uploaded.
Bad: call a self-hosted local build a cloud build that saves local disk space.

## 6. Tests Required

Run actionlint and Bash syntax checks before pushing. Observe actual cloud job results.
Check ZIP members, digests and ELF/PE machine identities for published outputs.
Keep native runtime tests on executable host targets. A successful YAML parse alone
is not a successful build. Existing unrelated Flutter/device acceptance remains open.

## 7. Wrong vs Correct

Wrong: upload native/build/linux/qfli_py_ffi as the Linux library.
Correct: native/desktop produces libqfli_py_ffi.so. The Windows DLL is at the build
directory root even for Release because CMake explicitly sets configuration output paths.

Wrong: delete all ohos/entry/libs files because .gitignore mentions that directory.
Correct: check git ls-files; the ARM64 libqfli_py.so is tracked in this repository.
