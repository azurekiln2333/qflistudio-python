# Backend Directory Structure

## 1. Scope / Trigger

Use when locating execution, native adapters, packaging or persistence work.
The backend is an embedded C VM; this application has no HTTP server.

## 2. Ownership Map

| Path | Responsibility |
| --- | --- |
| `lib/python_runner.dart` | Project source/input, transport selection and terminal results |
| `lib/python_ffi.dart` | FFI bindings, worker isolate and allocation ownership |
| `native/src/qfli_py_bridge.{h,c}` | C ABI, VM lifetime and execution |
| `native/src/qfli_py_{hal,stdio,file,reader,platform}.*` | Streams, project files and platform primitives |
| `native/src/qfli_py_{jni,napi}.cpp` | Android JNI and OHOS NAPI adapters |
| `native/port/` | Maintained MicroPython feature and HAL configuration |
| `native/micropython_embed/` | Generated, tracked embedding inputs and qstr headers |
| `native/tools/` | Embedding generation and ELF dependency inspection |
| `native/{android,desktop,windows,linux,apple,ios,macos}/` | Platform build/package integration |
| `native/ohos/QfliPyNative.ets` | Source bridge copied into the OHOS app |
| `ohos/entry/src/main/ets/plugins/QfliPyNative.ets` | Packaged OHOS bridge |
| `native/tests/`, `test/`, `tool/python_ffi_smoke.dart` | C, Flutter and real-FFI checks |

## 3. Contracts

- Put VM semantics in common C. Adapters translate values, schedule work and
  manage handles; they do not implement another interpreter.
- Declare exported functions in `qfli_py_bridge.h`; use `qfli_py_` names and
  matching Dart typedefs. Internal declarations belong in owning headers.
- Modify port inputs and regenerate embedding inputs through
  `native/tools/build_embed.py`; inspect generated diffs for semantic changes.
- Keep both ArkTS copies identical. Source-template changes alone do not enter
  the packaged app.
- Shared project/config/content stores belong to `../qfli_studio_core`, the path
  dependency in `pubspec.yaml`. Coordinate edits with other language workspaces.

## 4. Validation & Error Matrix

| Change | Companion review |
| --- | --- |
| C field/signature | FFI struct/typedef, JNI and NAPI conversion |
| Port module or qstr | Generated headers and affected builders |
| OHOS method | Both ArkTS copies and runner capability probe |
| Native packaging | Actual artifact contents and loader dependencies |

## 5. Good / Base / Bad Cases

- Good: add a common C operation, then expose it through existing adapters.
- Base: runner reads a real entry and invokes the packaged VM.
- Bad: platform-only Python semantics or generated qstr edits without their input.

## 6. Checks Required

Follow [Native Python Runtime](./native-python-runtime.md),
[Python FFI](./python-ffi.md) and [Android Build](./android-build.md).
Verify bridge hashes and explicit owned diffs before staging. Keep outputs under
ignored `build/` or `native/build/`.

## 7. Wrong vs Correct

Wrong: implement project files in a new Kotlin-only Python engine.
Correct: reuse `qfli_py_file.c` through the common ABI, as both adapters do.
See [the C header](../../../native/src/qfli_py_bridge.h) and
[the runner](../../../lib/python_runner.dart).
