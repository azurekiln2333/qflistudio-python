# Native Python Runtime Design

## Boundaries

- Flutter owns project selection, entry resolution, display, and user-facing commands.
- ArkTS passes typed MethodChannel arguments to the NAPI module.
- The C bridge owns VM lifetime, per-run state, source compilation, error capture, and runtime path setup.
- Upstream MicroPython owns parsing, bytecode generation, execution, builtins, and module semantics. Port code only adapts platform I/O and filesystem access.

## Execution Contract

`run` accepts source, stdin, heap size, project path, and entry path. It returns exit code, stdout, stderr, and a truncation flag. Subsequent runs must not see globals or imported project modules from earlier runs. Errors in compilation and execution use the same result shape.

## Verification

An in-app native self-check calls the C bridge through ArkTS and NAPI with real source cases, including repeated-run isolation. The Flutter tests check argument forwarding and display behavior. A signed HAP installation and hilog result establish the packaged device path. This method is necessary because the device denies execution of binaries copied into `/data/local/tmp`.

## Compatibility

MicroPython is not CPython. Claims and UI should identify the actual engine. `sys.path` and file access must use the app's project location; app-wide current directory changes are avoided because Flutter and native code share a process.
