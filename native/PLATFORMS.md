# Native Python Platforms

The retained MicroPython 1.24.1 C compiler and VM are shared by every native
platform. The port adapts files, standard streams, clocks, locking and lifetime.
It does not implement a substitute Python parser or VM.

## Build and Package

- Android uses the existing Kotlin/JNI bridge and packaged `libqfli_py.so`.
- OHOS uses the existing ArkTS/NAPI adapter.
- Windows/Linux use the local `native/pubspec.yaml` FFI plugin. Its CMake files
  compile the tracked embedding package and bundle the resulting DLL/SO through
  Flutter's installer. A desktop test build lives in `native/build/<platform>`.
- iOS/macOS local pods stage the tracked C inputs in their pod root and compile
  a static archive. App link flags retain `qfli_py_run_into`,
  `qfli_py_result_free` and `qfli_py_version`; Dart opens process symbols.

Windows uses UTF-8 to wide-character path conversion, canonical handle paths,
case-aware containment, native locking and timers, and a custom module reader.
When POSIX/VFS readers are disabled, the port must also supply
`mp_lexer_new_from_file`; supplying only `mp_reader_new_file` fails at link time.
The upstream lexer still owns Python syntax.

## Verification

On 2026-10-02, the owning repository's Windows MinGW build succeeded. The
standalone Dart FFI smoke passed 34/34 actual native cases: source/output UTF-8,
finite stdin and EOF, stderr, imports, refreshed module state, text/binary file
I/O, Unicode paths, path errors, compile-only non-execution, syntax/runtime
errors, exit codes, state reset, truncation and eight concurrent invocations.

Linux CMake built `libqfli_py_ffi.so` in a fresh output directory. Linking the
existing host test executable to this shared library passed 65/65 cases,
including filesystem effects and resource cleanup. This establishes the Linux
C ABI and VM; a full Linux Flutter GUI has not been built or run.

The Android regression build and final Flutter result are recorded in the task
implementation notes. Prior Android packaged runtime evidence is in README.md;
do not count a new APK build alone as a fresh installed-runtime pass.

No Apple host/Xcode or Visual Studio C++ installation is available. Apple
source integration and MSVC build support are unverified on their target hosts.
Native Windows FFI execution and Linux C execution were verified directly.

## Commands

```powershell
./native/desktop/build.ps1 -Compiler <gcc.exe> -CMake <cmake.exe> -Ninja <ninja.exe>
dart --packages=.dart_tool/package_config.json tool/python_ffi_smoke.dart native/build/windows/qfli_py_ffi.dll
flutter test --no-pub
flutter analyze --no-pub
```

`native/desktop/build.sh` builds Linux/macOS. Use `QFLI_PY_BUILD_DIR` for a fresh
output directory when an old CMake cache belongs to another generator/toolchain.

## Remaining Limits

MicroPython is not CPython and does not provide pip or CPython extension modules.
The current C API buffers output and has no running-program cancellation API.
Infinite loops cannot be stopped through the current runner. Syntax checking
does not produce a reusable bytecode artifact. These remain explicit runtime
requirements in the cross-product audit.
