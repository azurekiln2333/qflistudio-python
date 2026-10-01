# Complete Native Python Runtime and Tooling

## Goal

Make QFLIPyFlow a usable Python IDE whose code is compiled and executed by the same ported C runtime on Android and HarmonyOS, with practical project tools and a release-ready interface.

## Confirmed State

- The app uses upstream MicroPython 1.24.1 in `libqfli_py.so`, reached through ArkTS and a Flutter MethodChannel. There is no Dart interpreter.
- On 2026-09-30, the native arm64 library and signed HAP built, the HAP installed on a connected device, and startup self-check executed Python with exit code 0.
- Existing Flutter tests mock the MethodChannel. They do not prove arbitrary source execution in the C runtime.
- At task start, the runtime had no project file access or ordinary `.py` module import, and reused VM state without an isolation check.

## Requirements

- Keep the upstream C MicroPython compiler and VM as the execution engine. Do not implement a Python subset in Dart or write a new interpreter.
- Make source compilation, normal execution, syntax errors, runtime errors, stdout, stderr, stdin, and exit status observable and correct across repeated runs.
- Support Python projects with multiple `.py` modules and practical project-local file operations; resolve entry files from the editor's actual project paths.
- Supply reproducible native build, packaging, and on-device execution checks that exercise the real C runtime, not only channel mocks.
- Add useful Python workflow tools where supported by the port, with honest capability boundaries for MicroPython-specific differences.
- Keep unfinished-work and build-instruction language out of normal app screens. Runtime failures should use concise, actionable messages.
- Commit each coherent implementation batch with a conventional commit message. Preserve unrelated dirty files.
- Android must package the shared C engine through NDK/JNI and register the existing MethodChannel protocol. Verify real execution on the Android emulator, including project imports, input, file I/O and compile-only syntax checks.
- The user narrowed current device debugging to Android on 2026-10-01. Do not launch or test HarmonyOS devices/emulators again in this session; preserve the pending HarmonyOS final device gate separately.

## Acceptance Criteria

## Cross-platform Continuation (2026-10-01)

The active user goal asks to implement missing platform runtime paths and test
only where the target environment is actually available. Android and OHOS
already reach the upstream C compiler/VM; Windows, Linux, macOS and iOS were
unwired plain Flutter shells at this audit.

- Package and invoke the same C MicroPython engine on these four native targets.
- Preserve compile/run, finite stdin/stdout/stderr, exit status, fresh VM state,
  project module imports and project-local files, including Windows Unicode
  paths and real path containment.
- Reuse the series' existing FFI/isolate pattern for desktop and Apple targets;
  keep mobile MethodChannel protocols and behavior compatible.
- Supply reproducible build/link configuration for desktop and Apple. Test real
  native execution on available Windows/WSL and Android; do not pretend a
  Windows host can build or test iOS/macOS without Xcode.
- Report the separate browser boundary: web/ is a Flutter template, while the
  current IDE and runner depend on dart:io/local projects. A browser VM would
  require WASM and a virtual project filesystem; native bindings cannot be
  presented as browser support.
- Other QFLI language projects have independent ongoing platform tasks and
  dirty source work. Their audit is read-only here while scope clarification
  is pending; do not overwrite parallel implementations or claim them complete.

## Original Acceptance Criteria

- [ ] A clean checkout can reproduce the native arm64 library and signed HAP using documented commands.
- [x] A repeatable test executes source through the C VM and checks successful output, compilation errors, exceptions, input, exit codes, and state isolation.
- [x] The installed app loads its native module and can run a project entry file on a device.
- [x] Entry files can import sibling and package `.py` modules, and project-local read/write works with predictable errors.
- [x] The app exposes practical Python workflow actions without unfinished-development copy.
- [ ] Flutter tests, native execution tests, static analysis, native build, HAP build, and device checks pass for the delivered scope.
- [x] Work is committed in coherent conventional commits; unrelated existing changes remain untouched.
- [x] Android APK contains the shared C VM and passes native self-checks and editor execution on the emulator.
