# Research: OHOS signed HAP delivery readiness

- Query: Build the current Python OHOS package for the user-designated 14u at `192.168.68.207:46551`.
- Scope: internal source and filesystem inspection only.
- Date: 2026-10-26.
- Delivery correction: use HDC for the OHOS target. ADB is not the delivery path. Root handles connection and delivery. No device command was executed by this researcher.

## Findings

The minimal app build command, after the root-owned current arm64 native rebuild and verified staging, is:

```powershell
& "D:\ProgramFiles\flutter_ohos\bin\flutter.bat" build hap --release --no-pub --target-platform ohos-arm64
```

The application release target is the normal `lib/main.dart`, not the generated module/content/debugger audit targets. `tool/build_python_ohos_audit.ps1:408` explicitly builds an x86_64 DEBUG audit HAP and is therefore the wrong build driver for this physical-device product delivery.

Signed output: `build/ohos/hap/entry-default-signed.hap`. Hvigor's corresponding signed output is `ohos/entry/build/default/outputs/default/entry-default-signed.hap`. A same-name old HAP is not success: both present files were113477086bytes with modification2026-10-22T11:07:15.342266Z. Require successful fresh build and compare output identity/packaged libraries before delivery.

`ohos/entry/build-profile.json5:6` limits native ABI to arm64-v8a and excludes x86_64/armeabi-v7a. The current app module includes phone,2in1,tablet. `ohos/AppScope/app.json5` identifies bundle `com.azurekiln.qfli.pyflow`, version1.0.0/versionCode1000000. No Android APK is involved.

Signing readiness was checked in memory with sanitized output. Product `default` selects signing configuration `releaseKey`. Its certificate, keystore and provisioning-profile files all exist. The unused `debugKey` provisioning-profile file is absent. Password fields are present, but credentials were neither printed nor copied. This proves file availability, not key validity, provisioning scope, device eligibility or successful signing. Do not replace identity or regenerate credentials automatically.

### Installed build inputs

All paths below were checked for existence without executing their tools:

| Role | Path |
| --- | --- |
| Flutter OHOS | `D:/ProgramFiles/flutter_ohos/bin/flutter.bat` |
| Native toolchain | `D:/ProgramFiles/Huawei/DevEco Studio/sdk/default/openharmony/native/build/cmake/ohos.toolchain.cmake` |
| CMake/Ninja | `D:/ProgramFiles/Huawei/DevEco Studio/sdk/default/openharmony/native/build-tools/cmake/bin/` |
| Java | `D:/ProgramFiles/Huawei/DevEco Studio/jbr/bin/java.exe` |
| Hvigor | `D:/ProgramFiles/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat` |
| Node | `D:/ProgramFiles/Huawei/DevEco Studio/tools/node/node.exe` |
| Signature verifier | `D:/ProgramFiles/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar` |

`ohos/local.properties` points hwsdk.dir to the DevEco SDK and flutter.sdk to the working flutter_ohos checkout. Existing DEVECO_SDK_HOME,HOS_SDK_HOME,JAVA_HOME are set to existing directories. OHOS_SDK_HOME and NODE_HOME are unset; do not invent an environment change solely from that absence. The repository's documented build uses the current Flutter environment. The older release-readiness note records Java25; this researcher ran no version command. Preserve shared SDK/global configuration.

### Native staging boundary

Root assigned the arm64 rebuild to a separate implement agent with the existing owned-process helper and `CMAKE_BUILD_PARALLEL_LEVEL=2`. The first user-authorized execution claim was global937; it was not a C-issued grant. That attempt failed before any compiler started because Windows PowerShell5 parsed the UTF-8-without-BOM script incorrectly. The following command is historical and failed; do not reuse it:

```powershell
powershell -ExecutionPolicy Bypass -File native\build.ps1 -Abi arm64-v8a -BuildType Release -SkipCopy
```

Root independently checked this source with the PowerShell7 AST parser and reported PASS. A future coordinated retry must select the exact PowerShell7 executable while preserving the native arguments:

```powershell
& "D:\ProgramFiles\PowerShell\7\pwsh.exe" -NoProfile -File native\build.ps1 -Abi arm64-v8a -BuildType Release -SkipCopy
```

No retry or compiler launch is claimed here. The actual original native process PID5264, FILETIME134374910053629792, reached terminal exit1 with Jobactive0 and handles closed. The original exec691bcf also reached actual terminal exit1. Root recorded releases949/951. Future request952 asks for <=600seconds after Web; it is pending and is not a current launch authorization or active reservation.

`native/build.ps1:242` uses `native/build/cmake-arm64-v8a`. It regenerates maintained embedding inputs, captures provenance, performs clean-first build, checks dependencies and finishes provenance before its copy branch. `-SkipCopy` leaves `ohos/entry/libs/arm64-v8a/libqfli_py.so` unchanged. After verified build/provenance, explicitly copy the new SO to that exact arm64 staging path. Do not copy a stale SO or use the x86 audit helper. The old staged arm64 SO is2524648bytes, modified2026-10-22T10:25:05.3036445Z, and predates current debugger changes. Old prebuilts lack the current debugger exports.

For the fresh HAP, inspect the ZIP's arm64 libqfli_py.so identity against the newly staged current-source SO. A release packager may strip bytes, so a hash mismatch needs comparison to the actual intermediate stripped library and ELF export/dependency checks, rather than silently accepting or requiring an impossible source-SO hash match. Ensure qfli_py_debug_* exports exist because Run uses MethodChannel while Debug separately loads FFI.

### Signature verification pattern

The existing driver at `tool/build_python_ohos_audit.ps1:298` uses the SDK verifier without credentials:

```powershell
& "D:\ProgramFiles\Huawei\DevEco Studio\jbr\bin\java.exe" -jar "D:\ProgramFiles\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar" verify-app -inFile "build/ohos/hap/entry-default-signed.hap" -outCertChain "build/python-delivery-verify.cer" -outProfile "build/python-delivery-verify.p7b"
```

Record exit status and output existence without printing extracted profile or signing material. Use existing exact owned-process helper for bounded actual commands under the root-coordinated build window. Snapshot a successful HAP under a new artifact name and record size/hash/timestamp before HDC delivery so an old same-name output cannot be substituted.

### Public signing validity preflight (2026-10-26T12:58Z)

Read-only .NET X509Certificate2 and SignedCms decoding inspected only the selected releaseKey public certificate and CMS provisioning profile. It executed no SDK, Java, signing CLI, compiler, build, download or device tool. No credential, private key, signing-config content, full profile, UUID or developer identifier was printed.

| Public field | Observation |
| --- | --- |
| Selected certpath certificate validity |2020-03-16T03:04:39Z through2049-03-16T03:04:39Z, currently valid by time |
| Profile validity |2026-09-14T11:58:31Z through2029-09-14T11:58:31Z, currently valid by time |
| Profile distribution-certificate validity |2026-09-14T11:58:31Z through2029-09-14T11:58:31Z, currently valid by time |
| Profile type/distribution |release / app_gallery |
| Profile bundle constraint |exact com.azurekiln.qfli.pyflow, matches current app bundle |
| Explicit device/UDID fields found |none in decoded profile property names; no device admission guarantee inferred |
| CMS signature mathematical check |SignedCms.CheckSignature(true) passed; chain trust and revocation were not evaluated |
| certpath versus profile distribution certificate |NOT equal by public certificate thumbprint |

The certificate mismatch needs root attention before expensive HAP signing. The configured certpath decodes as one X509 certificate (ContentType Cert), and importing the full file as X509Certificate2Collection still yields exactly one certificate. It does not contain the profile distribution certificate. This rules out a simple first-certificate-versus-chain ordering explanation for this file. No keystore was opened and no private-key association was checked, so this is a public input mismatch finding rather than a prediction of a particular signer error. Preserve current signing material until root decides how to select an already authorized matching certificate; do not regenerate identity or expose passwords. Existence-only signing readiness above is superseded by this more precise caveat.

### Existing keystore ephemeral preflight (2026-10-26)

Root authorized an additional read-only check of the already selected releaseKey PKCS12 material. The check read the existing store password in memory from the current configuration and attempted X509Certificate2Collection.Import with EphemeralKeySet only. It did not request Exportable, MachineKeySet, UserKeySet or PersistKeySet. No certificate, private key or password was exported, printed or written to a file. No signing/config/material file was modified. Public CMS decoding used the existing profile only.

The ephemeral collection import failed with the outer .NET invocation exception type System.Management.Automation.MethodInvocationException. The exact private-key identity, private-key presence and alias match are therefore UNAVAILABLE, not false. No private-key operations or alternate persistent import were attempted. No SDK, Java, compiler, build or signer was run. The failure does not establish a missing key, a key/profile mismatch, password invalidity, platform incompatibility or an invalid signing identity because those causes were not separately resolved. Preserve the existing release identity; do not infer a need for unsigned delivery or credential replacement from this unavailable check.

### Related specs and local references

- `.trellis/workflow.md`: research persistence and phase boundary.
- `.trellis/spec/backend/native-python-runtime.md`: real VM/build/device evidence.
- `.trellis/spec/backend/quality-guidelines.md`: dependency/provenance, signed-HAP and separate installed-runtime gates.
- `.trellis/tasks/10-22-python-offline-tools/{prd,design,implement}.md`: actual Tools/analyzer behavior and OHOS acceptance.
- `README.en.md:112`: release arm64 HAP command and output.
- `.trellis/tasks/10-15-python-release-readiness/research/platform-build.md:59`: existing SDK/environment findings, historical only.
- `.trellis/tasks/10-22-python-offline-debugger/research/current-ohos-native-build-readiness-20261026.md`: native provenance and sequential ABI builds.
- External references: none fetched; this is an internal build-readiness audit, not a claim of latest external SDK guidance.

## Caveats / Not Found

- No SDK/compiler/native/hdc/adb/device/signing tool ran during this research.
- Root reports current HDC target MRT-AL10/aarch64/OpenHarmony7.0.0.105; researcher did not independently probe it.
- Global918 was memoryDEFER. Global937 was a root user-authorized execution claim, not a C-issued grant. Its precompiler parser failure is terminal and released949/951. The PowerShell7 retry request952<=600seconds remains pending after Web. Root must reconcile current host capacity and ownership before any native retry or Flutter/Hvigor build; no current launch is implied.
- The current source's full Flutter tests/analyzer and current native30 debugger regressions are unrun. Package delivery cannot close these gates.
- Signing files exist for selected release configuration; certificate validity, profile target eligibility and actual release signing remain unverified until real build/signature verification.
- No new examples may be represented as installed-verified from a HAP build or transfer alone.
