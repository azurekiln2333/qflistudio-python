# Exhaustive installed-OHOS content harness

Date: 2026-10-23. Scoped implementer: `implement_python_analyzer`.

## Ownership and boundary

The gap is exhaustive installed-app evidence for every authored, aggregate and
legacy runnable unit. Host-DLL content passes do not establish installed OHOS
acceptance. The behavior belongs in a product-owned audit entry that uses the
same shared import service and Python runner as the editor.

Exclusive files in this batch:

- `tool/python_content_ohos_audit.dart`: reusable audit plus standalone status UI.
- `tool/prepare_python_content_audit.py`: build-only entry/input preparation.
- `test/python_content_audit_test.dart`: failure/lifetime/import regressions.
- This research note.

No curriculum, shared core, native/debugger, normal UI, signing, build driver or
device changes are owned here. Parent owns export/generation, HAP integration,
device queue, final acceptance and commits. Other workers' edits are preserved.
The Trellis pre-development context and content PRD/design/implementation
artifacts were read before implementation.

## Entry and preparation contract

```dart
startPythonContentAudit({
  required String inventoryJson,
  required String inventorySha256,
  required Map<String, String> assetDigests,
  Map<String, Object?> buildEvidence = const {},
});
```

`runPythonContentAudit` accepts the same arguments plus required `Directory
storage`, optional real `PythonProgramRunner`, `AssetBundle`, operation/settle
deadlines and progress callback. Its default runner uses the installed platform
transport. Host acceptance requires FFI; device acceptance requires the actual
`Platform.operatingSystem == 'ohos'` and `transport == 'methodChannel'`.

Preparation consumes an existing shipped export without invoking any generator:

```text
python tool/prepare_python_content_audit.py --inventory build/python-content-original-shipped.json --output build/python_content_audit
```

Optional `--native-library` binds an existing little-endian ELF64 x86_64/arm64
input; `--build-metadata` supplies a JSON object. Preparation writes only below
ignored `build/`: `main.dart`, `inventory.g.dart`, `inputs.json`. It rejects an
unchecked/nonembedded/duplicate unit, mismatches, missing identities and asset
drift. Declared hashes require independent HAP inspection; they do not identify
loaded memory by themselves.

Source digests include runner/FFI/loader/package code, both native channel
adapters, EntryAbility and Index. Core importer source, the original inventory,
all three core content assets and bundled Python assets are separately bound.
Core assets load only as `packages/qfli_studio_core/<relative asset>`; bundled
modules use product `assets/python_stdlib/` paths.

## Execution and durable evidence

Each unit creates a fresh project. `CodeImportService.importIntoProject` imports
an actual `ExampleCode` as `src/main.py`; the service handles stdin aliasing and
all project fixtures. Every imported file is reread and SHA-256 compared before
calling `PythonProgramRunner.run`. The report records source, row, expected
output and fixture identities, imported-file hashes, exit and both streams.
Null expected output requires explicit nonempty validation; assertion-only
units retain actual output without inventing a declared stdout expectation.

Every input row receives `pass`, `fail`, `unavailable` or `timeout`, including
malformed rows and units blocked by a failed prerequisite. Missing behavior and
asset mismatches cannot pass. A timeout aborts later native submissions. Native
exit and both stream completions are observed together; an early stream error
cannot permit project deletion before the native exit. A late handle still
receives Stop. Timed-out/failed projects and all unsettled work are retained.
Late completion never rewrites the final report or deletes retained projects.

`qfli-python-content-audit.jsonl` appends durable row snapshots before import,
after import and after completion. `qfli-python-content-audit.json` is a compact
progress checkpoint during execution and the complete self-contained report at
finish. This avoids rewriting gigabytes of growing row data on device. The
checkpoint names its journal and format; final counters include planned,
completed, passed, failed, unavailable, timedOut and omitted.

Runner comparison is explicitly weaker than host raw-output comparison:
`PythonProgramRunner` removes one terminal LF and one terminal CR per line. The
audit applies exactly that transformation to declared stdout. It preserves
spaces and extra blank lines, and does not claim to distinguish a missing final
LF. Expected stderr is empty and expected native exit is zero.

## Verification status

Source authoring is complete. Thirteen focused regressions are authored,
including missing/hash/mismatch/behavior cases, exact whitespace, incremental
journal evidence, timeout/late handle/import/stream settlement and real
`LocalContentAdapter -> CodeImportService -> PythonProgramRunner` example008 and
package117. The real test defaults to the current platform's build library;
`QFLI_PYTHON_TEST_LIBRARY` selects another existing library explicitly.

The parent completed a bounded host window and released it at global seq329 to
Java. `build/python-current-focused-window.json` records terminal processes,
51.17 seconds total and `deviceGatePassed: false`. Its expanded test log,
`build/python-current-focused-tests.log`, records **28/28 passed**, comprising
11 debugger protocol, 4 actual-FFI debugger and **13 content-audit tests**. The
content subset includes the actual adapter/import/embedded input008 and
package117 regression; no content test was skipped. These are scoped host
results, not an exhaustive installed-OHOS acceptance result.

The window's analysis returned exit 1 for ten INFOs. Four belonged to this
harness: one `use_null_aware_elements` and three
`curly_braces_in_flow_control_structures`. A subsequent source-only change
replaced the optional event-map entry with `'record': ?row` and added the three
blocks. Owned harness formatting passed afterward. No analysis, test or build
was rerun after that source change; parent retains the next verification
window. The other six INFOs belong to debugger test ownership. Preparation
execution and final packaged acceptance are still separate gates.

The configurable immutable foundation DLL is local host evidence only, never
an installed-device claim. Parent reports its separate original inventory has
1158 rows, zero asset mismatches and all 1158 actual host-VM passes, SHA-256
`f1d891de16360a587e205a945e0a015c90040a267a68e5b7acfd614fa8838ec4`.

The original installed-OHOS baseline, matching final HAP, physical ARM64 and
subsequent 180-topic expansion remain parent-owned open gates.
