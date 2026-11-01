# Current-source OHOS native build readiness (debugger audit)

Date: 2026-10-26. Owner: Python read-only preparation for
`10-22-python-offline-debugger`. This note is source and document only.

Nothing here was executed. No compiler, CMake, Ninja, Flutter, Dart, SDK,
hvigor, signing, hdc, device or channel command was run. No artifact, source,
core file or build profile was changed. Every command below is a **later**
command for a coordinated window.

## Conclusion

Classify readiness in three separate layers. Do not merge them.

**Build-source readiness: prepared, pending a distinct host grant.** The
prerequisites exist on disk, verified with `Test-Path` only and no execution:
the upstream MicroPython source at `native/third_party/micropython`, the
generated `native/micropython_embed` tree, the toolchain, and the preparation
and inspection scripts. Nothing was run and no version was read. A distinct host
grant for the build is still required. It is not authorized now.

**Build output: not produced yet, by design.** No current-source SO and no
`native-build-evidence.json` exist for either ABI. That is the purpose and
output of the build, not a prerequisite that blocks it. Their absence says
nothing about build-source readiness. It only means the build has not run.

**Post-build, HAP and device acceptance: open.** HAP preparation, the arm64
device HAP and installed-device verification are separate later gates. The
missing confirmed device target gates installed verification only. Grant 683 is
retired and grant 703 belongs to the JSON host, so no device is implied.

The `-SkipCopy` build can proceed under a fresh host grant. It does not need a
device, a HAP or an acceptance report.

The build shape itself is unambiguous. Two **separate** single-ABI builds, each
with its own build directory and its own provenance manifest, run one after the
other. They are never a single dual-ABI build and never run in parallel.

## SDK and tool paths (filesystem lookup only)

Resolved by `Test-Path` only. No tool was invoked and no version was printed.
DevEco home is the default install location.

| Role | Path | Present |
| --- | --- | --- |
| DevEco home | `D:\ProgramFiles\Huawei\DevEco Studio` | yes |
| OHOS NDK native root | `<DevEco>\sdk\default\openharmony\native` | yes |
| CMake toolchain | `<NDK>\build\cmake\ohos.toolchain.cmake` | yes |
| CMake | `<NDK>\build-tools\cmake\bin\cmake.exe` | yes |
| Ninja | `<NDK>\build-tools\cmake\bin\ninja.exe` | yes |
| llvm-strip | `<NDK>\llvm\bin\llvm-strip.exe` | yes |
| HAP signing tool | `<DevEco>\sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar` | yes |
| Java | `<DevEco>\jbr\bin\java.exe` | yes |
| Host Python 3 (default) | `<DevEco>\plugins\app-analyzer\lib\python\python.exe` | yes |
| hvigor | `<DevEco>\tools\hvigor\bin\hvigorw.bat` | yes |

`ohos/local.properties` has four keys: `hwsdk.dir`, `flutter.sdk`,
`flutter.versionName`, `flutter.versionCode`. Only the key names are recorded.
No value is copied into this note, and no signing configuration is read,
printed or stored anywhere in it.

Two different resolvers exist. Do not assume one covers the other:

- `native/build.ps1` does **not** read `hwsdk.dir`. It probes
  `-DevEcoHome`, then `$env:DEVECO_HOME`, then fixed install paths, and accepts
  a candidate only when `<candidate>\sdk\default\openharmony\native\build\cmake\ohos.toolchain.cmake`
  exists.
- `tool/build_python_ohos_audit.ps1` reads the single `hwsdk.dir` line when
  `-HapSignTool`, `-Java` or `-LlvmStrip` are omitted, and derives the three
  SDK paths from it.

## Shipped libraries to preserve

Both ABIs ship a prebuilt SO. These are frozen baseline artifacts.

| Path | Bytes | SHA256 |
| --- | --- | --- |
| `ohos/entry/libs/arm64-v8a/libqfli_py.so` | 2524648 | `cb26d20b16d796a36043560e49631a18a4fa055a6842de0d7c504b100fe59bcc` |
| `ohos/entry/libs/x86_64/libqfli_py.so` | 2394848 | `78b31d943fe93a63e9de654d95cbec16bc12507e686d79acf5fba41003671717` |

Both are dated 2026-10-22. Current debugger sources in `native/src/qfli_py_debug.c`
and `native/port/` are newer than these SOs, so neither shipped SO can be
presented as current-source evidence. Preserve both files until a coordinated
window replaces them on purpose.

## Exact separate both-ABI native build

`native/build.ps1` is single-ABI per invocation. `bothABI` means two sequential
runs, each with its own `native/build/cmake-<abi>/` directory.

Parameters that matter:

- `-Abi`: `arm64-v8a` (default), `x86_64`, `armeabi-v7a`.
- `-BuildType`: `Release` (default) or `Debug`.
- `-SkipCopy`: build only, do not copy into `ohos/entry/libs/`.
- `-Clean`: deletes `native/build/cmake-<abi>/` first. Avoid it once a
  provenance manifest is finished.
- `-DevEcoHome`, `-Python`: explicit overrides.

### arm64-v8a (device payload) — run first

```powershell
powershell -ExecutionPolicy Bypass -File native\build.ps1 `
  -Abi arm64-v8a -BuildType Release -SkipCopy
```

### x86_64 (audit HAP payload) — run after arm64 finishes

```powershell
powershell -ExecutionPolicy Bypass -File native\build.ps1 `
  -Abi x86_64 -BuildType Release -SkipCopy
```

Why sequential: both runs regenerate the shared
`native/micropython_embed/` package through the `qfli_py_regen` target. Two
concurrent runs would race on that generated tree and on the same source
snapshot each provenance capture fingerprints. Two directories is not enough
for parallelism. Run them one at a time.

### What each run does, in order

1. Locate the NDK from the candidate list and require CMake, Ninja and the
   toolchain file.
2. Locate host Python 3, preferring the DevEco bundled `python.exe`.
3. Check `native/third_party/micropython/py/makeqstrdefs.py`. Clone the source
   if absent, then require commit `ecfdd5d` (upstream v1.24.1).
4. Create `native/build/cmake-<abi>/` and run CMake configure with
   `-DOHOS_ARCH=<abi>`, `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON` and
   `-DQFLI_PY_PYTHON=<python>`.
5. Build the `qfli_py_regen` target, then reconfigure. This regenerates the
   current native inputs.
6. Run `tool/python_native_provenance.py capture` and write
   `native/build/cmake-<abi>/native-build-evidence.json` in the pending state.
7. Build with `--clean-first --target qfli_py`.
8. Run `native/tools/check_so_deps.py` as a gate.
9. Run `python_native_provenance.py finish`, which marks the manifest complete
   and re-verifies it.
10. Copy `native/build/cmake-<abi>/libqfli_py.so` into
    `ohos/entry/libs/<abi>/libqfli_py.so` **unless** `-SkipCopy` was passed.

Artifacts after a `-SkipCopy` run:

- `native/build/cmake-arm64-v8a/libqfli_py.so` plus `native-build-evidence.json`
- `native/build/cmake-x86_64/libqfli_py.so` plus `native-build-evidence.json`

## ABI, export and provenance inspection

All four commands are read-only inspection of an existing file. None compiles,
stages or installs.

```powershell
python native\tools\check_so_deps.py  native\build\cmake-arm64-v8a\libqfli_py.so
python native\tools\inspect_so.py     native\build\cmake-arm64-v8a\libqfli_py.so
python native\tools\check_so_deps.py  native\build\cmake-x86_64\libqfli_py.so
python native\tools\inspect_so.py     native\build\cmake-x86_64\libqfli_py.so
```

What each one proves:

- `check_so_deps.py` parses ELF `DT_NEEDED` and fails when any loaded library is
  not guaranteed present on the device namespace. `libc++_shared.so`,
  `libstdc++.so` and `libc++abi.so` are rejected on purpose. CMake also runs it
  as `POST_BUILD`, so a bad link fails the build.
- `inspect_so.py` reports the full `DT_NEEDED` list, the embedded
  `MICROPY_VERSION_STRING` / `MICROPY_GIT_HASH` engine identity and upstream
  marker symbols, plus undefined C++ symbols. With no argument it inspects the
  arm64-v8a path. Pass the path explicitly to avoid checking the wrong ABI.

Provenance verification, per ABI:

```powershell
python tool\python_native_provenance.py verify `
  --manifest native\build\cmake-arm64-v8a\native-build-evidence.json `
  --library  native\build\cmake-arm64-v8a\libqfli_py.so

python tool\python_native_provenance.py verify `
  --manifest native\build\cmake-x86_64\native-build-evidence.json `
  --library  native\build\cmake-x86_64\libqfli_py.so
```

`verify` re-snapshots the live build directory and rejects the manifest unless
all of these hold:

- `schemaVersion` is 2 and `kind` is `completed-python-native-build`.
- `buildExitCode` and `dependencyCheckExitCode` are both 0.
- `abi` is a supported OHOS triple and matches the ELF header machine field
  (62 for x86_64, 183 for arm64-v8a, 40 for armeabi-v7a).
- Every `sourceDigests` entry still matches, including
  `native/micropython_embed/py/vm.c`, `native/micropython_embed/py/emitglue.h`
  and `native/tools/debug_overlay.py`.
- All six tool roles are fingerprinted: `cCompiler`, `cxxCompiler`, `linker`,
  `ar`, `ranlib`, `python`.
- Every configured SDK include and link input still matches, including the
  extensionless libc++ headers and at least one static library.
- `output` equals the SHA256 and byte size of the library passed in.

Exports check, debugger specific:

```powershell
python tool\prepare_python_debugger_audit.py `
  --native-library native\build\cmake-x86_64\libqfli_py.so `
  --output build\python_debugger_audit
```

The preparer reads the SO and rejects it unless it is ELF64 little-endian with a
supported machine field and contains all five exports:

- `qfli_py_debug_capabilities`
- `qfli_py_debug_create`
- `qfli_py_debug_execute_into`
- `qfli_py_debug_poll_json`
- `qfli_py_debug_command`

Presence of these symbols only rejects a definitely old library. It does not
prove a working debugger. The preparer also re-checks every bundled module
digest in `assets/python_stdlib/manifest.json`, records all source digests, and
requires the two copies of `QfliPyNative.ets` to be identical. It refuses to
write outside `build/`.

## Source-bound HAP preparation order

The order is fixed. Native build and provenance come before the HAP, and the HAP
comes before any device work.

### Step 1 — build and verify the x86_64 SO

Run the x86_64 command above, then the `check_so_deps.py`, `inspect_so.py` and
`python_native_provenance.py verify` commands for x86_64. Do not continue on any
failure.

### Step 2 — stage the x86_64 SO (coordinated swap)

`tool/build_python_ohos_audit.ps1` hard-requires the SO at
`ohos/entry/libs/x86_64/libqfli_py.so` and its manifest at
`native/build/cmake-x86_64/native-build-evidence.json`. Both are fixed paths in
the driver.

So the staged x86_64 SO must occupy the shipped x86_64 path for the duration of
the build. Inside the coordinated window only:

1. Record the shipped hash `78b31d94…` and copy the shipped file aside.
2. Copy `native/build/cmake-x86_64/libqfli_py.so` into
   `ohos/entry/libs/x86_64/libqfli_py.so`.
3. After the HAP build and verification, restore the shipped file and confirm
   its hash is `78b31d94…` again.

Do not touch `ohos/entry/libs/arm64-v8a/`. The driver never reads it.

### Step 3 — build the debugger audit HAP

```powershell
powershell -ExecutionPolicy Bypass -File tool\build_python_ohos_audit.ps1 `
  -AuditKind debugger
```

Defaults already point at `native/build/cmake-x86_64/native-build-evidence.json`,
`build/python-ohos-audit-build.log` and `build/python-ohos-audit-build.json`.
Pass `-HapSignTool`, `-Java` and `-LlvmStrip` only to override `hwsdk.dir`.

The driver then, in order:

1. Opens an exclusive lock at `build/.ohos-audit-build.lock`.
2. Copies the entry profile bytes aside and records its hash.
3. Rejects the manifest unless `abi` is exactly `x86_64`, then runs
   `python_native_provenance.py verify`.
4. Runs `prepare_python_debugger_audit.py` itself with a fresh build nonce and
   writes `build/python_debugger_audit/{main.dart,suite.g.dart,inputs.json}`.
5. Re-checks every declared source and asset digest before and after the build.
6. Rewrites the entry profile ABI to x86_64: `abiFilters` becomes `["x86_64"]`
   and the `**/x86_64/**` exclude becomes `**/arm64-v8a/**`.
7. Builds `flutter build hap --debug --no-pub --target-platform ohos-x64 -t
   build/python_debugger_audit/main.dart`.
8. Requires exactly one `entry-default-signed.hap`, verifies its signature with
   `hap-sign-tool.jar verify-app`, and checks that packaged native entries are
   x86_64 only and include `libqfli_py.so` and `libflutter.so`.
9. Restores the entry profile bytes, restores `JAVA_TOOL_OPTIONS`, and writes
   `build/python-ohos-audit-build.json` with `profileRestored`,
   `rootProfileUnchanged` and `environmentRestored`.

The driver never writes, copies or prints signing configuration. It only
verifies an already-signed HAP and deletes the two extracted verification files
it creates under `build/`.

### Step 4 — arm64-v8a HAP (separate, coordinated)

The driver builds only the x86_64 audit HAP. A device payload is a different
artifact. After the arm64 SO and its provenance exist and after a coordinated
staging of `ohos/entry/libs/arm64-v8a/`, the device HAP is built with:

```powershell
flutter build hap --release --target-platform ohos-arm64
```

The x86_64 audit HAP is never device evidence, and the arm64 HAP is never audit
evidence.

## Default-copy and coordination hazards

| # | Hazard | Consequence | Mitigation |
| --- | --- | --- | --- |
| H1 | `native/build.ps1` copies into `ohos/entry/libs/<abi>/` by default | Overwrites a frozen shipped SO and shifts the baseline that other tasks reference | Always pass `-SkipCopy`, keep artifacts in `native/build/cmake-<abi>/`, stage only inside a coordinated window |
| H2 | The audit driver requires the SO at `ohos/entry/libs/x86_64/` | A staged SO must temporarily replace the shipped x86_64 file | Record `78b31d94…`, back up, stage, restore, re-verify the hash |
| H3 | The driver rewrites exactly one `"abiFilters": ["arm64-v8a"]` | A committed both-ABI profile makes `Replace-One` throw before any build starts | Keep the entry profile single-ABI; never commit the temporary edit |
| H4 | Provenance `verify` re-snapshots `native/build/cmake-<abi>/` | `-Clean` or a second configure in the same directory invalidates a finished manifest | One directory per ABI; never clean a finished build; run the ABIs sequentially |
| H5 | A missing `native/third_party/micropython` triggers a git clone | Needs network and git, and pins commit `ecfdd5d` | Confirm the source is present before a window; never substitute another source |
| H6 | No `native-build-evidence.json` exists today | No prior provenance can be reused | Every manifest must come from a fresh current build |
| H7 | Shipped SOs are dated 2026-10-22 | They predate current debugger sources | Do not present them as current evidence |
| H8 | `-Abi` default is `arm64-v8a` | A run without `-Abi` silently builds the device payload | Pass `-Abi` explicitly on every invocation |
| H9 | `inspect_so.py` defaults to the arm64 path | Inspecting the wrong ABI gives a misleading pass | Pass the SO path explicitly |

## Device and grant status

- Grant 683 is retired. Grant 703 belongs to the JSON host, not to any device.
- No hdc client was run. No target was established. No device identity, API,
  ABI or signing readiness was confirmed.
- This gates installed-device verification only. It does not gate the native
  `-SkipCopy` build or HAP preparation.
- Nothing in this note implies device verification of any kind.

## Tool hashes (read-only, for later binding)

| File | Bytes | SHA256 |
| --- | --- | --- |
| `native/build.ps1` | 16633 | `39a2e203990ad5fb4b7842be191b2568dfc8078f84346f5f1aa502138534ff12` |
| `native/CMakeLists.txt` | 13392 | `ab5e0d1a18597711df6dfc4c18eaf7f3cb8a989e3a96c53328650ea5544c6d28` |
| `native/tools/inspect_so.py` | 8679 | `567d05e5f795736b59dead2840e6e4a331c641271ba54eed994e3d2dc03fcf7c` |
| `native/tools/check_so_deps.py` | 7625 | `97cc11496ef95cc7c85234f2b59a5e11a1b39d6712eef4f4d2f9737aab98b07c` |
| `native/tools/build_embed.py` | 31707 | `7ab7f6f865ba69c97d69088226ac09898f9642bb2f237b7c1d3cf57d7aed3a70` |
| `native/tools/debug_overlay.py` | 5401 | `b435f0dfc68a761da97044687c67a6c08246c7e14177d3726c9705c2c53fefcb` |
| `tool/python_native_provenance.py` | 16412 | `f25ad2f5ef09cd8554a58fcbd036d38b4c312808e2cf876ddf42400b984ce7da` |
| `tool/prepare_python_debugger_audit.py` | 8142 | `b69506a1027b3242d66b027eaf496d6e792fd4c22108641199a0ae9626e765c4` |
| `tool/build_python_ohos_audit.ps1` | 27954 | `a2f7c648bbc4b73a9da2dae59d53e0eac1918c6dbfc6b30f57ebfbc6278e3d9a` |
| `tool/python_audit_inputs.py` | 3987 | `f139c43e9457bdb851b69d80e4f6955a6aea3121c67cefc8fb3b396948d24d50` |
| `ohos/entry/libs/arm64-v8a/libqfli_py.so` (shipped) | 2524648 | `cb26d20b16d796a36043560e49631a18a4fa055a6842de0d7c504b100fe59bcc` |
| `ohos/entry/libs/x86_64/libqfli_py.so` (shipped) | 2394848 | `78b31d943fe93a63e9de654d95cbec16bc12507e686d79acf5fba41003671717` |

Current entry ABI selection in `ohos/entry/build-profile.json5`:
`abiFilters` is `["arm64-v8a"]` and `excludes` is
`["**/x86_64/**", "**/armeabi-v7a/**"]`. The driver expects exactly this shape.

## Not run

No compiler, CMake, Ninja, Flutter, Dart, SDK, hvigor, signing, hdc, device or
channel command was run for this note. Only `Test-Path` and file hashing were
used, to locate tools and to pin existing bytes. No file under `native/`,
`ohos/`, `lib/`, `tool/` or `qfli_studio_core/` was created or modified by this
work. Only this readiness note was written.
