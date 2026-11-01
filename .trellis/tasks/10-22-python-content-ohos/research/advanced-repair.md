# Original advanced Python content repair

Date: 2026-10-22. Owner: `implement_python_analyzer` for this narrow content
batch. Product source ownership was exclusively
`../qfli_studio_core/tool/python_content/python_topics_advanced.dart`.

## Boundary and result

The original topics61-120 contained incomplete method fragments, prose answers,
undefined example helpers, false measurements and four external-runtime mains.
The behavior lives in authored topic/answer data, so this batch repaired that
single source file and kept every topic ID and all121 exercise slots. It did not
generate shared aggregates, modify core UI/schema/import code or author new IDs.
Root owns model/export/verifier integration and generation serialization.

All60 advanced mains and121 answers now declare the embedded runtime and have
an exact main output or explicit nonempty answer behavior check. Each displayed
answer includes its needed classes/functions/imports; no verifier lesson prelude
is supplied. Package/file answers declare their own project fixtures.

## Repairs

- Completed class-method answers with their own class context, implemented
  missing helper functions and changed prose/statement fragments into executable
  programs. Added positive, empty/boundary and relevant rejection assertions.
- Corrected dropped coroutine sends, name-versus-node tree iteration, missing
  graph/maze helpers, lower-bound independence, retry exhaustion propagation,
  heap output ordering and negative monetary formatting.
- Replaced swap counts advertised as comparisons with actual comparison counts.
  Performance exercises count declared operations and include set-build cost,
  avoiding machine-time claims or invented internal hash-probe counts.
- Added complete standalone tests for algorithms, contract failures, intentional
  test-framework failures, full API routes and project data writes/reads.
- Topic117 teaches a real local `pricing` package with declared `__init__.py`
  and implementation fixtures. Topic118 defines explicit validated data models
  with integer monetary units and independent default lists. Topic119 reads
  declared data files and writes/reopens a real project report. Topic120 uses
  deterministic generator round-robin scheduling, event budgets and real close
  cleanup; it does not advertise threads, asyncio or wall-clock timeouts.
- Refreshed contextlib/functools prose for the new offline bundles and clarified
  module-level `re.split` versus compiled-pattern `.split` using local native
  `modre.c` as evidence.

The first real embedded pass found180/181 passing. The remaining exercise73:2
called `Exception.__init__`, which this MicroPython build does not expose.
Explicit message storage and `__str__` corrected it. The same latent problem in
lesson73's ValidationError branch was repaired, and the main now actually invokes
the invalid-email path so that branch is covered by exact output verification.

## Reproducible evidence

Export without aggregate writes:

```text
dart run tool/python_content/export_inventory.dart ../qfli_python/build/python-content-advanced-final.json
```

Actual embedded verifier (the selection is all integers61 through120):

```text
python tool/verify_python_content.py --inventory build/python-content-advanced-final.json --topics 61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100,101,102,103,104,105,106,107,108,109,110,111,112,113,114,115,116,117,118,119,120 --report build/reports/python-content-advanced-final.json
```

Final result: **181/181 passed, zero skips/failures**, including60 mains and121
exercise answers. Each unit executes in a fresh subprocess and project with
validated bundled modules, declared fixtures, finite deadline, exact expected
stdout where specified and appended behavioral assertions. CPython hosts ctypes
only; no curriculum code is accepted through host CPython execution.

The exported snapshot contains all306 original units, including the125 basic
units maintained by the other owner. This report selects181 advanced units only;
the root must run/retain the complete306-unit evidence for the combined batch.

Artifacts:

- Authored source SHA256:
  `8935044175b3550e5c25e1b9150c04bc2417bcb137269fa03866207c5e2b9eb2`.
- Full snapshot SHA256 and report inventorySha256 are identical:
  `3df91ddec29370474a72e3f808d307dc0acf5ac1b85a3d92551a91a04e323411`.
- Actual Windows DLL SHA256:
  `2329ef7d374e35dd5159db0f3f056b094effc9a0372ad29fe704af472a6c309f`.
- Runtime version in every final case: MicroPython1.24.1 (`ecfdd5d`).
- First-pass failures remain separately visible in
  `build/reports/python-content-advanced-first.json`.

`dart analyze tool/python_content/python_topics_advanced.dart` passed without
issues; `dart format` and owned `git diff --check` passed. The DLL window was
explicitly released to root and the native debugger owner after final execution.

## Remaining gates

Root must serialize aggregate generation and preserve non-Python/custom rows,
verify source/asset pairing and exercise ordinary fixture import. Installed OHOS
execution of every original unit remains required before any new-topic expansion.
These host results do not close that gate or the umbrella standalone-app goal.
No staging or commit was performed by this worker.
