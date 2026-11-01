# Original topics 001–060 exercise repair

## Ownership and boundary

This batch owns only these authored sources in the shared core:

- tool/python_content/topics_basics.dart (001–016)
- tool/python_content/topics_containers_functions.dart (017–040)
- tool/python_content/topics_modules_oop.dart (041–060)

The behavior gap was that 65 exercise answers had no executable behavioral
expectation, and some depended on missing lesson context or contradicted their
prompts. Each answer now runs independently, without an implicit lesson prelude,
with exact stdout, appended assertions, or both. No topic was added. All 60 main
program code/output/fixture/runtime inventory records compare equal to the
pre-edit snapshot. IDs and topic learning objectives are unchanged.

No shared model, UI, schema, native source, generator, aggregate JSON, content
store or other language was changed by this batch. No commit was created.

## Repairs and checks

- 008: explicit exercise stdin fixture (6 7), exact product 42.
- 009: defines score before its branch program.
- 016: guesses sequentially through the bounded 1..100 range, stops on the
  actual seeded target and checks the counter; no unbounded random guessing.
- 017–028: exact deterministic output or semantic container assertions;
  sorted intersection output avoids depending on set order.
- 029–040: complete functions, defaults, varargs, global state, recursive
  boundaries, closure independence, decorator forwarding/results/exceptions
  and generator exhaustion receive meaningful edge or negative checks.
- 042: prints the actual first import directory, compares it with the root
  entry directory using __file__, and reads a declared project identity
  fixture through that directory. No host/device path is hardcoded.
- 043: corrects the prompt from dividend-zero to divisor-zero, and checks
  zero numerator, zero denominator and negative values.
- 044–050: exercise exceptions, file contents, blank/whitespace lines and
  JSON round trips have complete setup and explicit expectations.
- 051: checks three integers in range and reseeding reproducibility on the
  embedded RNG; no CPython random sequence is used as an expectation.
- 052: contains its own load/save persistence program, then counts completed
  todos and checks missing-file and empty-list behavior.
- 053–057: check zero/negative dimensions, separate account state,
  rejected deposits, read-only conversion, score bounds and super-based
  inherited initialization. 055 now converts Fahrenheit to Celsius as asked.
- 058: uses both name and describe from unrelated concrete classes, checks
  empty input and missing interfaces, and prints readable summary lines.
- 059: checks both coordinates, zero values, subclass-aware construction and
  missing-coordinate rejection.
- 060: retains Money amount/currency and display methods; equality checks
  amount, currency and incompatible types.

There are 60 exact-output answers and 37 assertion-checked answers, with overlap,
covering all 65 answers. Exact beginner outputs were reasoned from the programs;
assertions specify independent behavior and failure cases.

The first real-VM pass was 124/125. It exposed the embedded runtime's escaped
Unicode repr when printing the Chinese summaries inside a list in answer 058.
That answer now prints each summary as ordinary text; its assertion still checks
the full returned list. The repeated complete batch passed 125/125.

## Actual host evidence

The root and direct-tools worker released the serialized native test window
before this run. The verifier ran every unit in a fresh subprocess and isolated
project using the actual shipped DLL plus manifest-checked bundled modules.
CPython hosted ctypes and did not execute the curriculum programs.

Snapshot: build/python-content-basics.json

Report: build/reports/python-content-basics.json

- UTC run: 2026-10-22T11:06:15.143595+00:00 through
  2026-10-22T11:06:30.898555+00:00
- Selection: topics 1–60, 60 authored mains + 65 exercise answers
- Planned/passed/failed: 125 / 125 / 0
- Runtime: MicroPython 1.24.1 (ecfdd5d)
- Inventory SHA256:
  c069f8c57a701a1556462022fbc4d6b8bcc6bced50aef9aef261c7416e51fd50
- DLL SHA256:
  2329ef7d374e35dd5159db0f3f056b094effc9a0372ad29fe704af472a6c309f
- deviceGatePassed: false

Reproduction from the core:

    dart run tool/python_content/export_inventory.dart ../qfli_python/build/python-content-basics.json

From the Python repository:

    python -X utf8 tool/verify_python_content.py --inventory build/python-content-basics.json --topics 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60 --report build/reports/python-content-basics.json

All three owned Dart source files pass dart analyze; dart format was applied,
and git diff --check is clean. No runtime defect remains in this selected host
batch. Installed OHOS execution, ordinary import fixture preservation, shared
aggregate generation and the original 061–120 units remain the parent task's
separate acceptance gates; this report does not claim those passed.
