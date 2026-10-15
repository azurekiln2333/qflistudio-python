# Desktop and Apple Native Packaging

`native/` is a local Flutter FFI plugin named `qfli_python_native`. It packages
the same tracked MicroPython compiler/VM and shared C bridge used by Android
and HarmonyOS. It requires no MethodChannel registrar on these FFI targets.

| Target | App packaging | Runtime library |
| --- | --- | --- |
| Windows | Flutter FFI plugin CMake bundle | `qfli_py_ffi.dll` beside the executable |
| Linux | Flutter FFI plugin CMake bundle | `lib/libqfli_py_ffi.so` beside the executable |
| iOS | CocoaPods static framework, iOS 13+ | Symbols in the app process |
| macOS | CocoaPods static framework, macOS 10.15+ | Symbols in the app process |

The FFI contract in `src/qfli_py_bridge.h` includes `qfli_py_execute_into`,
`qfli_py_cancel_create/request/free`, `qfli_py_result_free` and `qfli_py_version`.
The legacy `qfli_py_run_into` entry remains available. The caller supplies result
storage and frees its strings with `qfli_py_result_free` before releasing that
storage. Cancellation tokens remain alive until their queued or executing call
completes. Platform adapters keep UTF-8 strings and the existing result layout.

## Standalone Windows DLL

Use CMake 3.15+, Ninja and MinGW GCC; Visual Studio and Flutter are not required
to build this C library. The helper discovers CMake/Ninja on PATH or in the
Android SDK's `cmake` installations. Pass the compiler path when it is not on
PATH, for example on this development machine:

```powershell
.\native\desktop\build.ps1 -Compiler D:\ProgramFiles\Dev-Cpp\MinGW64\bin\gcc.exe
```

Explicit tool paths are also supported:

```powershell
.\native\desktop\build.ps1 `
  -CMake D:\ProgramData\Android\Sdk\cmake\3.22.1\bin\cmake.exe `
  -Ninja D:\ProgramData\Android\Sdk\cmake\3.22.1\bin\ninja.exe `
  -Compiler D:\ProgramFiles\Dev-Cpp\MinGW64\bin\gcc.exe
```

The default output is `native/build/windows/qfli_py_ffi.dll`. GCC's runtime is
linked with `-static-libgcc`; locking uses Win32 and does not add a pthread DLL.
Full Flutter Windows builds still require Flutter's Visual Studio toolchain.
MSVC builds require version 19.28+ for C11, and use the same dynamic CRT as the
Flutter application.

## Standalone Linux or macOS Library

Install a C compiler, CMake 3.15+ and either Ninja or Make, then run:

```sh
sh native/desktop/build.sh
```

Default outputs are `native/build/linux/libqfli_py_ffi.so` and
`native/build/macos/libqfli_py_ffi.dylib`. The helper accepts `CC`,
`QFLI_PY_CMAKE`, `QFLI_PY_GENERATOR`, `QFLI_PY_BUILD_DIR`,
`QFLI_PY_BUILD_TYPE` and `QFLI_PY_JOBS` environment variables.
It selects Ninja when available and otherwise uses Unix Makefiles. Set
`QFLI_PY_GENERATOR` to select a generator explicitly; use a fresh build directory
when changing generators.

## Flutter and Apple Builds

After resolving the root app dependencies, Flutter discovers the local FFI
plugin and bundles the desktop library through
`qfli_python_native_bundled_libraries`. Do not edit generated plugin lists.

Apple app builds require macOS, Xcode and CocoaPods. The two Podspecs use the
shared `apple/podspec.rb` helper. Local path pods do not run `prepare_command`,
so loading the Podspec stages exact shared source files under the platform's
`Classes/build/qfli_py` directory. Those generated files are ignored by the
repository's existing `**/build/` rule and are copied again only if they change.
The shared engine and tracked headers remain the authoritative source.

The source lists exclude re1.5 text-included C files, the localtime include
hook and the original MCU stdio unit from separate compilation. Their files
remain staged for relative includes. The final app link retains execution,
cancellation, result and version symbols with `-u`, so `DynamicLibrary.process()` can find them after static
linking and dead stripping.

Availability, native execution and full app verification are separate checks.
A source configuration on Windows does not establish an iOS/macOS build or
runtime result; verify those targets on an Apple host.
