# Current OHOS all-original-example acceptance readiness

Date: 2026-10-26. Owner: read-only content-acceptance preparation for
`10-22-python-content-ohos`. No code, asset, core, HAP or device change.

## Conclusion

The current-source original inventory is **not ready to prepare**. The shipped
inventory's bound digest for `assets/content/tutorials.json` is stale against
the current core asset. The preparation gate fails today and refuses to write a
partial entry. This is the one blocker before a current OHOS baseline run.

The 1158 Python unit payloads themselves are unchanged. The drift is in
non-Python rows of the shared aggregate. The Dart inventory must be re-exported
from the current core assets. An old hash must not be reused.

The stale shared export blocks only the **preparation** step. Three further
gates stay open separately and are not closed by fixing it:

1. The current native library build (`libqfli_py.so` from current C sources).
2. A current-source audit HAP. The freshest existing HAP predates current FFI
   and debugger sources.
3. The installed-device run on a real, identified OHOS target.

Fixing the export does not verify, build or execute anything on a device.

## Blocker: shared aggregate digest drift

`tool/prepare_python_content_audit.py` compares every `assetDigests` entry to the
current `qfli_studio_core` asset. Actual result:

```text
ValueError: Core asset drift since inventory export: assets/content/tutorials.json
  at tool/prepare_python_content_audit.py:90
```

Evidence:

| Asset | Shipment inventory (2026-10-23) | Current core | Match |
| --- | --- | --- | --- |
| `assets/content/tutorials.json` | `055f0eb3d7415b5037ae02d6d0aa994a532280b9fd847203d44ccf9f2b0ca5ec` | `7d858d27e440cb0de93cbfa2cd2469ed99005c3cedf6a846d95ebbb355f694ba` | no |
| `assets/content/examples.json` | `df0555c005d4230ad8248fc0d0a44073d393e60fc3ae152254be3ca20f4306b6` | `df0555c005d4230ad8248fc0d0a44073d393e60fc3ae152254be3ca20f4306b6` | yes |
| `assets/tutorials/python.json` | `e669ac3d463a887bc90949818292950fd5cb516bd0827ac72aa76b5bf1637b13` | `e669ac3d463a887bc90949818292950fd5cb516bd0827ac72aa76b5bf1637b13` | yes |

Row-level comparison of `assets/content/tutorials.json` (Python rows excluded):

- Non-Python rows: 1700 in both the 2026-10-23 snapshot and the current asset.
- Same ID set: no added, no removed row.
- Changed rows: exactly two, `java-tutorial-107` and `java-tutorial-161`.
- `tutorials.json` mtime moved to 2026-10-23 06:05, after the 00:46 export.

Python payload comparison against the inventory (`build/python-content-original-shipped.json`):

- 120 `python-tutorial-NNN` lessons: `code`, `output`, `inputFixtures` all equal.
- 120 `python-example-NNN` examples: `code`, `expectedOutput`, `inputFixtures` all equal.
- 186 `aggregate-answer` rows: `answer`, `validation`, `expectedOutput` all equal.
- Python payload mismatches: 0.

Conclusion: another language worker edited two Java rows after the Python
inventory export. The shared file digest moved even though Python content did
not. Re-export is mandatory. Do not hand-edit the inventory digest and do not
reuse the old `055f0eb3` value.

## Ordered entry for the current-source baseline

Paths are relative to `D:/MyNewProjects/qfli_python` unless noted. Step 0 runs
from the adjacent core repository `D:/MyNewProjects/qfli_studio_core`.

Step 0 — refresh the Dart inventory from current core assets, from the core cwd:

```text
dart run tool/python_content/export_inventory.dart ../qfli_python/build/python-content-current-shipped.json --shipped
```

The output path is explicit and relative to the core cwd. The exporter resolves
`assets/...` against the core cwd, so run it from core, not from the product
repo. The written file lands in the product `build/` directory.

Expected: `Exported 1158 units from 120 topics.` The new inventory must record
`assetMismatches` empty and the current `tutorials.json` digest `7d858d27…`.
The `--shipped` flag is required. It adds the aggregate and legacy forms.
Step 1 and Step 2 read the same file as `build/python-content-current-shipped.json`
relative to the product repo root.

Step 1 — prepare the audit-only entry (product repo):

```text
python tool/prepare_python_content_audit.py \
  --inventory build/python-content-current-shipped.json \
  --output build/python_content_audit \
  --native-library ohos/entry/libs/x86_64/libqfli_py.so
```

Outputs below ignored `build/`: `main.dart`, `inventory.g.dart`, `inputs.json`.
The gate rejects drift, a non-embedded unit, a duplicate ID, a missing identity,
a missing behavioral expectation and bundled-module digest mismatch.

Step 2 — build the audit HAP in an exclusive build window:

```text
powershell -File tool/build_python_ohos_audit.ps1 -AuditKind content \
  -InventoryPath build/python-content-current-shipped.json
```

The driver runs step 1 itself, temporarily selects the entry ABI, uses
`ohos/entry/libs/x86_64/libqfli_py.so`, builds `build/python_content_audit/main.dart`,
restores both build profiles and does not touch a device. The default
`InventoryPath` is the stale export. Pass the refreshed path explicitly.

Step 3 — install the audit HAP and run on OHOS. Capture stages:

```text
hdc shell hilog -z 5000 -T QFLI_PYTHON_CONTENT_STAGE
hdc shell hilog -z 5000 -T QFLI_PYTHON_CONTENT_AUDIT
hdc file recv /data/app/el2/100/base/com.azurekiln.qfli.pyflow/files/qfli-python-content-audit.json  <local>
hdc file recv /data/app/el2/100/base/com.azurekiln.qfli.pyflow/files/qfli-python-content-audit.jsonl <local>
```

The audit pulls no network and runs only the installed app. Step 3 needs a
confirmed device target. That target is not established yet, see the next
section.

## Entry and fixture model

- Entry: `void startPythonContentAudit({required inventoryJson, required
  inventorySha256, required assetDigests, buildEvidence})` in
  `tool/python_content_ohos_audit.dart`, hash
  `d45a481c56b664649ea3b88dbbe3b1529338e1dba487bd21930b842179ff728e`.
- The generated `main.dart` passes the inventory and asset map from
  `inventory.g.dart`; `buildEvidence` comes from `inputs.json`.
- Each unit imports through the real `CodeImportService.importIntoProject` as an
  `ExampleCode` type `python`, then runs the real `PythonProgramRunner`.
- Fixtures: `inputFixtures` are project-relative files written by the importer.
  A `stdin` fixture becomes the project `input.txt`. example008 stdin retention
  is covered by `test/python_content_audit_test.dart`.
- Each unit runs in a fresh project. Imported files are reread and SHA-256
  compared before the run. Fail/timeout projects are retained; pass projects are
  removed only after all pending operations settle.

## Expected report fields

Final `qfli-python-content-audit.json` (schemaVersion 1, kind
`python-exhaustive-content-acceptance`):

- `expectedBundleName` `com.azurekiln.qfli.pyflow`,
  `expectedOhosPullPath` `/data/app/el2/100/base/com.azurekiln.qfli.pyflow/files/qfli-python-content-audit.json`.
- `operatingSystem`, `operatingSystemVersion`, `dartVersion`,
  `startedAtUtc`, `finishedAtUtc`, `reportFile`, `journalFile`, `journalFormat`,
  `workDirectory`.
- `inventorySha256` and `actualInventorySha256` (must be equal).
- `declaredAssetDigests`, `declaredBuildInputs`,
  `verifiedPackagedAssets`, `verifiedBundledModuleAssets`.
- `runtime`: `available`, `version`, `detail`, `transport`,
  `supportsCancellation`.
- `outputComparison`: `mode` `PythonProgramRunner line streams`,
  `rawByteComparison` false, `limitations`, `assertionOnlyUnits`.
- Counters: `planned`, `completed`, `passed`, `failed`, `unavailable`,
  `timedOut`, `omitted`.
- Gate fields: `ok`, `hostGatePassed`, `deviceGatePassed`, `status`,
  `pendingOperations`, `cancellationErrors`, `cleanupConfirmed`,
  `workDirectoryRemoved` and `retentionReason` when retained.
- `preflightErrors` (must be empty), `error` (must be null).
- `cases`: one terminal record per inventory row.

Per-row fields: `index`, `inventoryRowSha256`, `id`, `topic`, `kind`,
`sourceSha256`, `fixtureSha256`, `expectedOutputSha256`,
`expectedStdoutLines`, `expectedStderrLines`, `expectedExitCode`,
`hasBehaviorCheck`, `projectPath`, `importedEntry`, `importedFileSha256`,
`exitCode`, `stdout`, `stderr`, `nativeAndStreamsSettled`, `problems`,
`status`, `reason`/`stack` on failure, `startedAtUtc`, `finishedAtUtc`,
`projectRemoved` on pass.

`deviceGatePassed` becomes true only when all rows pass, `ok` is true,
operating system is `ohos` and transport is `methodChannel`. A host FFI run sets
`hostGatePassed`, never `deviceGatePassed`.

Journal `qfli-python-content-audit.jsonl` appends `before`, `imported` and
`after` snapshots per row plus `preflight:*` and `finished` stages.

## Device target status (read-only inventory, no verification)

A read-only environment inventory ran under grant `Device-inventory-Python-20261026-01`
(actualGrantSeq 683, ACK 684, RELEASE 685). Record:
`build/device-inventory-python-20261026-01/inventory.json`.

- `hdc.exe` is present at the SDK toolchain path.
- No matching hdc server process was found.
- The default TCP 8710 listener result was recorded as unconfirmed.
- No hdc client command was invoked.
- `target`: exact assigned target not established; identity, API, ABI and
  signing readiness are unavailable. No target substitution.
- `mutations`: none.

Meaning for this note: the device gate is unverified and cannot start yet. The
inventory proves only that a local `hdc.exe` exists and that no server is
confirmed. It does not prove a device exists, is reachable, is signed, or ran
the audit. Do not read it as device verification. Step 3 stays blocked until a
confirmed server and an identified target exist.

## 1158 unit consistency checklist

Kind counts in the shipped inventory must hold exactly:

| Kind | Expected |
| --- | --- |
| `authored-main` | 120 |
| `exercise-answer` | 186 |
| `aggregate-example` | 120 |
| `aggregate-lesson` | 120 |
| `legacy-example` | 120 |
| `legacy-lesson` | 120 |
| `aggregate-answer` | 186 |
| `legacy-answer` | 186 |
| total | 1158 |

Required checks after a current-source run:

1. `planned == completed == 1158` and `omitted == 0`.
2. `passed == 1158`, `failed == 0`, `unavailable == 0`, `timedOut == 0`.
3. Every record `status == 'pass'`. No `pending` or `running` row survives.
4. All 1158 `id` values unique; each `topic` in 1..120; each
   `runtime == 'embedded'`.
5. Each `sourceSha256` matches the inventory row `codeSha256`; each
   `fixtureSha256` set matches; each `expectedOutputSha256` matches.
6. `expectedExitCode == 0` and `expectedStderrLines == []` for all rows.
7. `inventorySha256 == actualInventorySha256 == digest(re-exported inventory)`.
8. `declaredAssetDigests == verifiedPackagedAssets` for all three core assets;
   `verifiedBundledModuleAssets` matches the manifest.
9. `preflightErrors` empty; `error` null; `cancellationErrors` empty;
   `pendingOperations == 0`; `cleanupConfirmed` true.
10. Record the re-exported inventory digest, the three asset digests, the audit
    HAP sha256, the packaged `libqfli_py.so` sha256, the device id and the
    report sha256. A host pass is not a device pass.

## Real source gaps

- G1 (blocker): `qfli_studio_core/assets/content/tutorials.json` current sha
  `7d858d27…` versus inventory `055f0eb3…`, caused by `java-tutorial-107` and
  `java-tutorial-161`. Fix is a fresh `export_inventory.dart --shipped`. Not a
  Python gap, but it blocks the shared preparation gate.
- G2: the freshest HAP is the 2026-10-22 module audit HAP. It predates current
  FFI and debugger sources. Content acceptance needs a new HAP built from the
  current sources; the module HAP is immutable evidence for its captured
  sources only.
- G3: no confirmed device target. The 2026-10-26 read-only inventory found no
  hdc server, invoked no hdc client and established no target. The installed
  device gate cannot start.
- G4: the 180-topic expansion (PRD C4) remains out of scope until this baseline
  closes. No new examples were authored here.

No host, HAP or device run was performed. Host numbers below are historical.

## Historical host evidence (not current-source, not device)

- `tool/verify_python_content.py` with
  `build/python-content-original-shipped.json` and the foundation DLL
  `2329ef7d374e35dd5159db0f3f056b094effc9a0372ad29fe704af472a6c309f` reported
  1158 planned, 1158 completed, 1158 passed, 0 failed, 0 asset mismatches,
  `deviceGatePassed:false`. Inventory sha
  `f1d891de16360a587e205a945e0a015c90040a267a68e5b7acfd614fa8838ec4`.
- `test/python_content_audit_test.dart` host window recorded 28/28 passed with
  13 content-audit cases, `deviceGatePassed:false`. It requires the current
  platform library or `QFLI_PYTHON_TEST_LIBRARY`.

## Tool hashes for binding

| File | SHA256 |
| --- | --- |
| `tool/python_content_ohos_audit.dart` | `d45a481c56b664649ea3b88dbbe3b1529338e1dba487bd21930b842179ff728e` |
| `tool/prepare_python_content_audit.py` | `83795ba638036e0310efe9b09b1e288b3d32e9b089300c0366636acc6e683225` |
| `tool/verify_python_content.py` | `9cbb347ce623376ea12a7ecf5750a9c32ec723788bb4892f67e7891fd51890c6` |
| `qfli_studio_core/assets/content/tutorials.json` (current) | `7d858d27e440cb0de93cbfa2cd2469ed99005c3cedf6a846d95ebbb355f694ba` |
| `qfli_studio_core/assets/content/examples.json` (current) | `df0555c005d4230ad8248fc0d0a44073d393e60fc3ae152254be3ca20f4306b6` |
| `qfli_studio_core/assets/tutorials/python.json` (current) | `e669ac3d463a887bc90949818292950fd5cb516bd0827ac72aa76b5bf1637b13` |
| shipped inventory `build/python-content-original-shipped.json` | `f1d891de16360a587e205a945e0a015c90040a267a68e5b7acfd614fa8838ec4` (stale binding) |

## Not run

No Dart, Flutter, native, SDK, HAP, channel publish or device command was run
for this note. The export, preparation, the audit HAP build and the
installed-OHOS run are coordinator gates. No hdc client was invoked under the
2026-10-26 inventory. This note only records the read-only drift finding, the
device-target status, the ordered entry, the fixture model, the report-field
contract and the 1158-row checklist.