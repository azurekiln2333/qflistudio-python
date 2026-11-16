# Design

## Boundary

The missing behavior is a remote native build with downloadable outputs. It lives
in .github/workflows and native build tooling. Keep application behavior intact.
Use existing CMake targets and native tests. Add native/CI.md for operational use.

## Jobs and contracts

- Linux: build native/desktop, run the existing C smoke suite linked against the
  built shared library, and run existing debugger checks when supported.
- Windows: build the existing desktop target on a GitHub Windows runner. Use the
  supported compiler path and run a real native probe with existing test tooling.
- Android: use the pinned NDK 27.0.12077973 and CMake native/android for arm64-v8a,
  armeabi-v7a and x86_64. Retain static C++ and 16 KiB alignment.
- OHOS: acquire a fixed official Linux OpenHarmony native SDK in the hosted runner,
  initialize the pinned MicroPython submodule, and configure native/CMakeLists.txt
  directly. Build arm64-v8a and x86_64. Retain dependency inspection and provenance.
- Use read-only workflow contents permissions and bounded job timeouts.
- Publish only runtime libraries, checksums, identification and small evidence files.
  Build intermediates and SDKs stay on ephemeral hosted runners.

## Compatibility

Native-only artifacts are not APK/HAP installers. Android and desktop Flutter
integration currently rebuild source; downloading a library does not switch those
builds to prebuilt mode. OHOS can consume the matching library in entry/libs/<abi>.
OpenHarmony cross-compilation alone cannot establish HarmonyOS device execution.

## Delivery

Push an explicit dedicated branch to the GitHub URL. The origin remote has multiple
push URLs, so do not use an unqualified git push origin. Keep default/release branches
unchanged. Inspect Actions through the authenticated GitHub API without logging secrets.
Record commit, run IDs, conclusions, artifact IDs, sizes and retention timestamps.

## Rollback

Workflow changes are isolated in a dedicated branch. Remove or adjust the workflows
to roll back CI. Do not delete existing local build outputs in this task.
