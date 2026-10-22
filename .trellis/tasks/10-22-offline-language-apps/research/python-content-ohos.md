# Python exhaustive content baseline

Date: 2026-10-22. See `python-content-audit.py`, its JSON report and the
authored export helper for reproducible evidence. All writes are task-local.

## Inventory and actual execution

| Item | Observed result | Limit |
| --- | --- | --- |
| Authored topics | 120, declared 116 embedded +4 CPython | Runtime labels are not acceptance. |
| Aggregate examples/tutorials | 120 Python rows in each | Other language rows also remain present. |
| Source/aggregate/legacy comparisons | Zero mismatches | Data parity does not prove runtime correctness. |
| Distinct example IDs/titles/code | No duplicates in current 120 | Expansion still needs substantive review. |
| Example bodies, actual host DLL, declared stdin | 116/120 exact stdout pass | Four imports fail. |
| Tutorial bodies, actual host DLL, current no-input flow | 115/120 exact stdout pass | Example008 input plus the four imports. |
| Exercise answers compiled in embedded VM | 176/186 compile | No claim all 176 run correctly. |
| Current OHOS channel handler with doubles | 20/20 checks pass | No native VM/device execution. |
| Installed OHOS inventory run | Not performed; hdc Empty | Release gate remains open. |

Real DLL: `native/build/windows/qfli_py_ffi.dll`, 713342 bytes, version
1.24.1 (ecfdd5d), SHA256
`b477bc176a55d86a58162e9e25a480ece2706643e93334475140453af23f4f2c`.
Each main snippet ran in a fresh temporary project with explicit input. The
report records actual stdout/error and expected-output comparison for every ID.
Direct CPython3.13.3 also passes117-120, reported separately and never counted
as embedded/OHOS correctness.

## Failures and product defects

- `python-example-117` / corresponding lesson: missing sysconfig.
- 118: missing dataclasses; 119: missing os; 120: missing threading.
- Tutorial008: EOFError with current tutorial import/no-input path.
- Exercise compile failures (topic:exercise): 73:1, 96:2, 98:2, 101:2,
  106:1, 111:1, 111:2, 115:2, 117:1, 120:2. Some are prose or partial function
  bodies, so correct execution/setup inventory is required rather than judging
  all fragments by standalone compile alone. Undefined referenced helpers such
  as bfs_all need explicit setup or a complete runnable solution.
- `../qfli_studio_core/lib/content/local_content_adapter.dart:84` builds
  ExampleCode from entry code but drops inputFixtures. The current ExampleCode
  model has no fixture field and CodeImportService writes the source. Python
  runner reads project input.txt. Thus direct verifier stdin success does not
  imply an imported sample works. C content owner was notified in global seq84.

## Existing artifact inspection

`python-content-ohos-artifacts.json` records the inspected current native SO
and HAP paths/timestamps/hashes. The native arm64 SO predates this task and has
the expected ace_napi/hilog/libc dependencies; the signed HAP is also an existing
artifact. This is neither a fresh build claim nor installed-runtime acceptance.
`python-content-ohos-channel.txt` records the channel-double command output.

## Plan implications

Repair original mains, answers and input/project fixtures before expansion.
Retain IDs, remove false external-only compatibility claims and run every unit
with explicit setup/expected behavior. Extend the verifier to inventory all
answers, not only main programs. Add a Python app-owned OHOS inventory harness
using the same runner/fixtures as normal app execution and record artifact/code
hashes and all unit results. Validate ordinary UI import/run too.

Request exclusive Python-only authored-file ownership and serialize aggregate
asset generation with C/other languages. C owns common fixture model/import
schema. Preserve non-Python records and custom saved examples. Only after the
original installed-OHOS baseline passes, add180 substantive topic pairs and
repeat exhaustive verification, resulting in at least300 Python pairs.

## Evidence coverage caveat

The exercise audit is compile-only, not complete semantic execution. Existing
source/asset identity is strong evidence for pairing, not proof of correct
solutions. No report currently closes all-example OHOS acceptance.
