# Native builds on GitHub Actions

These workflows build the embedded MicroPython libraries on GitHub-hosted machines.
They do not require a local runner, Flutter, the adjacent `qfli_studio_core` checkout,
or app-signing credentials.

## Run and download

Open this repository's **Actions** tab. Select **Native build** or
**Native OHOS build**, then open the run for the intended branch and commit.
At the bottom of its summary, select a package under **Artifacts** to download a ZIP.
Sign in to GitHub to download artifacts. The workflow requests **14 days** of retention;
the run page shows the actual expiry. These files are not GitHub Release attachments.

Native source changes trigger the workflows on push and pull request. Manual dispatch
is also defined. GitHub displays the manual **Run workflow** button once the workflow
exists on the default branch; a push to the CI branch can trigger its first run.

| Workflow | Artifact | Main file | Target |
| --- | --- | --- | --- |
| Native build | `native-linux-x64` | `libqfli_py_ffi.so` | Linux x86_64 FFI |
| Native build | `native-windows-x64` | `qfli_py_ffi.dll` | Windows x86_64 FFI |
| Native build | `native-android-arm64-v8a` | `libqfli_py.so` | Android ARM64 JNI |
| Native build | `native-android-armeabi-v7a` | `libqfli_py.so` | Android ARM32 JNI |
| Native build | `native-android-x86_64` | `libqfli_py.so` | Android x86_64 JNI |
| Native OHOS build | `native-ohos-arm64-v8a` | `libqfli_py.so` | OpenHarmony ARM64 NAPI |
| Native OHOS build | `native-ohos-x86_64` | `libqfli_py.so` | OpenHarmony x86_64 NAPI |

Each package includes `SHA256SUMS` and `BUILD_INFO.txt`. The build information identifies
the source commit and toolchain. Small test reports or binary inspection reports provide
the evidence for that target. A library is uploaded only after its build and validation
steps pass. OHOS retains a successful ABI artifact if the other ABI fails; the overall
job still reports failure in that case.

Linux and Windows run real native checks. Android and OHOS are cross-compiled and
inspected; those jobs do not establish execution on an Android or HarmonyOS device.
No APK, AAB, HAP, Windows application installer, or Apple package is produced here.

## Toolchains and local use

Desktop and Android builds consume the tracked `native/micropython_embed` package.
Android uses NDK `27.0.12077973`, static C++ linkage and 16 KiB ELF segment alignment.
OHOS initializes the pinned MicroPython 1.24.1 submodule and regenerates embedding inputs.

OHOS uses the official OpenHarmony **6.1 Release** Linux SDK, native version
**6.1.0.31 / API 23**. The SDK bundle is pinned by SHA256. This differs from the
development machine's DevEco native SDK **26.0.0.105 / API 26**. Check the packaged
application on the intended device before treating a cloud build as release validation.
The provenance JSON records paths and inputs on the GitHub runner; it is not a portable
assertion that another local SDK and checkout match those inputs.

For OHOS app packaging, place the downloaded library in
`ohos/entry/libs/<abi>/libqfli_py.so`. Match the app's ABI and source commit. The current
release app selects ARM64. An x86_64 library alone does not provide an x86_64 Flutter app.

For standalone FFI testing, the loader accepts an explicit library path. Its development
locations are `native/build/windows/qfli_py_ffi.dll` and
`native/build/linux/libqfli_py_ffi.so`. Android and desktop Flutter integration still
compile native sources during app builds. Downloading a library does not configure those
integrations to consume prebuilt binaries.

## Local disk use

The 2026-11-17 inventory measured logical file sizes, in decimal units:

| Directory | Size | Purpose |
| --- | ---: | --- |
| `build/` | 12.59 GB | App outputs and test data |
| `build/content-import-avd/` (inside `build/`) | 8.68 GB | Test emulator disk and boot snapshot |
| `.dart_tool/` | about 567 MB | Dart/Flutter generated files |
| `ohos/entry/build/` | about 257 MB | OHOS app outputs |
| `native/build/` | 41.57 MB | Native libraries, objects, logs and evidence |

Do not add the emulator row to the `build/` total: it is already included.
Logical sizes can differ from physical disk allocation for sparse emulator images.
The emulator includes test-device state, and `build/` also holds prior acceptance evidence.
Preserve any needed app packages, reports or emulator data before deleting generated files.
No local files are removed by these workflows.

Moving native compilation to GitHub avoids local native intermediates and CI toolchains.
It does not remove existing Flutter outputs or emulator snapshots. Full local app builds
can recreate their own caches and continue to need the app toolchains.
Keep `native/micropython_embed`: it is tracked build input, not a disposable cache.
`native/third_party/micropython` is the pinned upstream source submodule.
