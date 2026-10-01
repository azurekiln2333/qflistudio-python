# Native Python Lifecycle And Bytecode

Windows/Linux/Apple FFI and Android JNI share the upstream MicroPython compiler
and VM. `PythonProgramRunner.run` accepts .py and .mpy. Controlled runs return
streams, an exit future and a stop callback before execution completes. Stop
uses a native per-run token; killing an isolate is not a native stop operation.

`PythonProgramRunner.compile` saves a sibling .mpy without executing the script.
The tools page provides compile and stop commands and discovers compiled files.
The upstream serializer/loader validates .mpy version and integer width. These
are bytecode artifacts, not standalone executables or CPython .pyc files.
Compile imported sources separately when distributing a source-free project.

The existing OHOS run/check channel and tokenless C ABI remain compatible.
OHOS does not expose the new host cancellation or artifact channel operations.
Stop is cooperative during VM execution and sleep; other blocking native I/O
cannot be interrupted. Compile errors preserve existing artifacts. A write
failure reports an error and can leave a partial artifact.

## Verification On 2026-10-02

- Windows real native FFI regression: 34/34 cases.
- Windows lifecycle/runner tests: loop and 60-second sleep cancellation,
  pre-start and queued stop, token isolation and recovery, real .mpy execution
  after deleting entry/imported source, invalid artifacts and path boundaries.
- Full staged Flutter suite: 57/57, including 360x800 and 1200x800 tools-page
  compile/stop workflows. Source analysis (lib/test/tool) passed.
- Android x86_64 debug APK: installed on emulator-5560 (API 37, 16384-byte
  pages), ordinary app entry passed 46/46 native JNI cases. Tools page stopped
  a real loop (exit 130) and compiled/reloaded main.mpy after renaming main.py
  (compiled-native 42, artifact-stderr, exit 0).
- Installed x86_64 release APK also passed real UI compilation, loop stop and
  source-free artifact execution after shrinking. Native ELF LOAD segments use
  0x4000 alignment; debug/release APKs passed zipalign -c -P 16 4. Dynamic native
  dependencies are libm.so, libdl.so and libc.so. The release APK is 26,971,354
  bytes, SHA256 51EEA2F6D3805F960E1484C2F32DF5901D015D0B560F88A0E97EE37C387281D2.
- Apple execution skipped: no Apple host or Xcode. Windows Flutter GUI skipped:
  no Visual Studio C++ tools. No Android ARM devices. Linux re-execution of this
  new lifecycle slice is pending the WSL approval service; prior Linux tests
  describe the earlier implementation and are not new lifecycle evidence.

Build the Windows DLL with native/desktop/build.ps1, then run the Flutter tests,
source analysis, and tool/python_ffi_smoke.dart. Android debug startup runs the
JNI cases automatically; release/profile contain the existing no-op self-check.
