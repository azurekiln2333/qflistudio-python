# Generic guideline completion evidence

## Boundary

The coordinator assigned this worker the eleven unfinished generic backend and
frontend guidelines, both indexes and this evidence file. Existing concrete
runtime/FFI/build/workflow/startup/content specs remain with their owners. This
worker changed no product, test, platform, sibling repository or task-state
files and did not stage or commit.

## Discovery

- Loaded the complete native hook output, release PRD/design/implementation plan,
  implement.jsonl, trellis-start, trellis-before-dev and trellis-spec-bootstrap.
- Read both layer indexes, all eleven generic templates, shared thinking guides
  and the bootstrap PRD. Generic templates were empty; existing concrete specs
  already described native execution.
- Inspected pubspec, analyzer configuration, app/runner/FFI/tools/startup sources,
  representative native interfaces/adapters/HAL and tests. Direct source reads
  were sufficient for this small wrapper; a graph index was unnecessary.
- Read shared-core persistence sources for ownership evidence without editing
  them. The wrapper defines no HTTP service, ORM/schema, React or flutter_hooks.
- Session discovery reported release/python-storefront-20261015 and no current
  task pointer. The supplied explicit release-task path was used and the
  discrepancy reported to the coordinator without changing the pointer.

## Source anchors

| Evidence | Documented rule |
| --- | --- |
| lib/main.dart: pythonProfile, main | Shared extensions, offline policy and one store set |
| lib/python_tools_page.dart: _refreshFiles, _execute, _compile, dispose, build | Actual file scans, generation guards, cancel cleanup and Material layout |
| lib/python_runner.dart: PythonNativeTransport, _probeNative, _completeControlled, _runNative | Transport/result types, explicit capabilities, valid exit/stream handling |
| lib/python_ffi.dart: _NativeResult, _validate, _invokeNative | ABI, argument checks, worker execution and allocation ownership |
| lib/app_startup.dart: _reportProgress, runWithAppStartup | Optional warning, readiness and finally-released first frame |
| native/src/qfli_py_bridge.h and qfli_py_bridge.c | Common C API, result/token ownership and VM lifecycle |
| native/src/qfli_py_hal.c, qfli_py_stdio.c, qfli_py_file.c | Captured independent streams, finite input and file cleanup |
| native/src/qfli_py_jni.cpp and qfli_py_napi.cpp | Platform conversion and result cleanup |
| native/ohos/QfliPyNative.ets; Android QfliPyNative.kt/debug self-check | Diagnostic tags, sessions and existing worker scheduling |
| test/python_app_test.dart, python_tools_page_test.dart, python_ffi_test.dart, python_lifecycle_test.dart, startup_test.dart | Payload/error/layout/lifecycle verification and real-library prerequisites |
| Core lib/store/project_store.dart: _readProjectRegistry, _reload, _persist | Local registry, revision protection, serialized temporary-file replacement |
| Core lib/store/settings_store.dart | Existing settings JSON ownership |

## Result

Replaced all eleven generic templates with English source-backed contracts and
examples, preserving filenames for existing Trellis references. The database
template now documents shared local persistence; the hook template documents
Flutter lifecycle. Each has seven concrete sections. Both indexes describe the
actual file set and distinguish documentation status from release verification.

## Verification

- Inline Python content validation passed for 13 owned specs: 77 relative links
  resolved, all eleven contracts had sections 1-7, code fences balanced, both
  index file sets matched their directories, and no template markers remained.
- `rg -n 'To be filled|To fill|TODO: fill|Fill in each|Replace with your'
  .trellis/spec/backend .trellis/spec/frontend` returned no matches (exit 1).
- `git diff --check -- .trellis/spec/backend .trellis/spec/frontend
  .trellis/tasks/10-15-python-release-readiness/research/spec-bootstrap.md`
  passed. Additional direct-file whitespace checks cover the ignored specs.
- No product tests were run for this documentation-only change. Application
  tests and native/platform builds remain the coordinator's release gates.

## Commit integration

`.gitignore` line 92 ignores `/.trellis/spec/`. Before this work only the backend
index, native-runtime and FFI specs were tracked in these layers. The coordinator
must explicitly force-add the eleven generic files and frontend index, then add
the already tracked backend index and this evidence. Avoid broad force-add of
the spec tree: the excluded concrete specs belong to other owners. The worker
has informed the coordinator and leaves commit/task archival to that session.
