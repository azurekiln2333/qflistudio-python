# Native Python Runtime Design

## Boundaries

- Flutter owns project selection, entry resolution, display, and user-facing commands.
- ArkTS passes typed MethodChannel arguments to the NAPI module.
- Android Kotlin registers the same MethodChannel, encodes strings as standard UTF-8 byte arrays, and calls JNI on one executor with a 1 MiB stack. Results return on the main thread. The Android CMake target consumes the tracked embedding sources without regenerating shared files during parallel ABI builds.
- The C bridge owns VM lifetime, per-run state, source compilation, error capture, and runtime path setup.
- Upstream MicroPython owns parsing, bytecode generation, execution, builtins, and module semantics. Port code only adapts platform I/O and filesystem access.

## Execution Contract

`run` and `checkSyntax` accept source, stdin, heap size, project path, and entry path. ArkTS maps `checkSyntax` to the sixth NAPI/C `compileOnly` argument. It parses and compiles without calling the resulting function. Both return exit code, stdout, stderr, and a truncation flag. Subsequent runs must not see globals or imported project modules from earlier runs. Errors in compilation and execution use the same result shape.

The file port uses upstream stream helpers with POSIX descriptors. Relative `open` paths resolve from the canonical project root, and existing paths or new-file parent directories must remain within it. Descriptors are tracked outside the GC heap and closed on normal and exceptional run completion. This check applies to `open`, not the upstream module reader; the runtime is not a security sandbox for untrusted code.

## Verification

An in-app native self-check calls the C bridge through ArkTS and NAPI with real source cases, including repeated-run isolation. The Flutter tests check argument forwarding and display behavior. A signed HAP installation and hilog result establish the packaged device path. This method is necessary because the device denies execution of binaries copied into `/data/local/tmp`.

The Linux host smoke executable links the same generated MicroPython sources and C bridge, including the file port. It checks real filesystem effects, compile-only non-execution, script expression silence, and descriptor counts after repeated runs. It complements the packaged-device checks. Widget checks exercise file discovery, syntax checking, and execution at phone and desktop sizes.

## Compatibility

MicroPython is not CPython. Claims and UI should identify the actual engine. `sys.path` and file access must use the app's project location; app-wide current directory changes are avoided because Flutter and native code share a process.

Android builds all three Flutter ABIs with static C++ linkage and 16 KiB ELF page
alignment. Debug startup checks exercise the actual JNI library; release/profile
builds omit those checks. `sys.platform` is selected in the shared port header
using `__ANDROID__`. Both platforms use the same C API and VM state isolation.

## Desktop and Apple Continuation

Add a local FFI plugin package under native/ for Windows/Linux shared-library
bundling and iOS/macOS CocoaPods static linking. Dart uses the same native
result fields in an isolate, following the existing Lua project's pattern.
The Android/OHOS channel remains available for the existing adapters and mocks;
tests inject that transport explicitly where the host otherwise selects FFI.

Add an exported C entry qfli_py_run_into(result, source, stdin, heapKb,
projectPath, entryFile, compileOnly) and retain qfli_py_result_free/version.
FFI allocates the result struct, always frees native buffers with the engine's
function, then releases argument/result allocations. Static Apple linking must
retain these exported symbols against dead stripping.

The shared C port receives the required Windows adaptation: OS-native locking
without a pthread DLL, clocks/sleep, UTF-8 Windows file paths, canonical final
paths, case-aware containment, and a custom Windows module reader. POSIX targets
retain their current implementations and upstream parser/compiler/VM.
Both the original port and tracked embedding port headers remain synchronized.
Do not regenerate date-dependent embedding headers just for platform binding.

Ownership: parent owns shared C port/platform/FFI exports and validation;
Dart worker owns lib backend/runner integration, ffi dependency and focused
tests; build worker owns native local-plugin manifests/CMake/Podspecs and build
helpers. All workers preserve unrelated OHOS agreement edits and adjacent repos.
