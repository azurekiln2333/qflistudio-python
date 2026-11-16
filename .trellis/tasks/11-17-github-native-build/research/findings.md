# Findings (2026-11-17)

## Repository

Original HEAD: 6a859a7. Original branch: release/python-storefront-20261015.
Working tree was clean; branch was eight commits ahead of the GitHub tracking branch.
GitHub repository: azurekiln2333/qflistudio-python (public), default branch main.
Actions enabled; current credential permits push. Do not expose credentials.
`origin` has multiple push URLs; explicit GitHub URL is required for this task.

`native/desktop/CMakeLists.txt` outputs the Windows DLL at its build-directory root,
including Release. Linux builds only libqfli_py_ffi.so, not a qfli_py_ffi executable.
`native/tests/smoke.c` can link the actual shared library. `native/tests/debugger.py`
uses Python ctypes and works with desktop dynamic libraries.

`ohos/entry/libs/arm64-v8a/libqfli_py.so` is tracked despite matching an ignore rule.
Do not treat every ignored-looking directory as disposable. No deletion authorized.

## Disk evidence

Logical bytes from the read-only inventory:

- build/: 12,586,813,838 bytes (12.59 GB / 11.72 GiB).
- build/content-import-avd/: 8,676,983,301 bytes, included in build/.
- Its userdata-qemu.img.qcow2: 6,425,214,976 bytes.
- Its snapshots/default_boot/ram.img: 2,147,549,184 bytes.
- native/build/: 41,570,490 bytes (39.65 MiB).
- The AVD config identifies PyFlow Import Test, x86_64 Android37.2.
- native/micropython_embed is tracked (~2.5 MB); upstream is a submodule (~40 MB tree).

## OHOS SDK

Official bundle:
https://repo.huaweicloud.com/openharmony/os/6.1-Release/ohos-sdk-windows_linux-public.tar.gz

Publisher checksum suffix: .sha256

SHA256: b833b75a64ee46bbd7880921abbb49b733ec5c8171b6684c9b524d57f624cee0
Content-Length: 2,499,936,800 bytes.
tar member: linux/native-linux-x64-6.1.0.31-Release.zip (835,615,943 bytes).
Native metadata: apiVersion=23, version=6.1.0.31, releaseType=Release.
After extraction, toolchain is native/build/cmake/ohos.toolchain.cmake.
This package was inspected through streaming metadata; no full SDK downloaded locally.
Local DevEco native metadata differs: API26, version26.0.0.105.

Use hosted Linux with direct CMake invocation; existing native/build.ps1 is Windows-only.
Do not use self-hosted runners as a substitute for offloading local disk use.

## GitHub references

- https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts
- https://github.com/actions/upload-artifact
- https://github.com/actions/checkout
- https://github.com/actions/runner-images

Artifacts belong to individual Actions runs. Download ZIPs after signing in.
workflow_dispatch UI requires default-branch workflow discovery; first-run push works
on a dedicated feature branch without updating main.
