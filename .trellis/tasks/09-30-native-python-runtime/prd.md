# Complete Native Python Runtime and Tooling

## Goal

Make QFLIPyFlow a usable Python IDE whose code is compiled and executed by a ported C runtime on HarmonyOS, with practical project tools and a release-ready interface.

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

## Acceptance Criteria

- [ ] A clean checkout can reproduce the native arm64 library and signed HAP using documented commands.
- [x] A repeatable test executes source through the C VM and checks successful output, compilation errors, exceptions, input, exit codes, and state isolation.
- [x] The installed app loads its native module and can run a project entry file on a device.
- [x] Entry files can import sibling and package `.py` modules, and project-local read/write works with predictable errors.
- [x] The app exposes practical Python workflow actions without unfinished-development copy.
- [ ] Flutter tests, native execution tests, static analysis, native build, HAP build, and device checks pass for the delivered scope.
- [x] Work is committed in coherent conventional commits; unrelated existing changes remain untouched.
