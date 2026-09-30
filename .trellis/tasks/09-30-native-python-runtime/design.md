# Native Python Runtime Design

## Boundaries

- Flutter owns project selection, entry resolution, display, and user-facing commands.
- ArkTS passes typed MethodChannel arguments to the NAPI module.
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
