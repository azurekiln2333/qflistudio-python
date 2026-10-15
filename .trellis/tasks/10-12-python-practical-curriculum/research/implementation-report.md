# Python curriculum — final verification record

Task: `.trellis/tasks/10-12-python-practical-curriculum`
Status: implementation complete; verification green. Not committed.

## Deliverables

- 120 Chinese tutorial lessons + 120 paired runnable examples, authored in
  `qfli_studio_core/tool/python_content/`:
  - `python_topic.dart` (model), `python_topics.dart` (aggregation),
  - `topics_basics.dart` (001–016), `topics_containers_functions.dart`
    (017–040), `topics_modules_oop.dart` (041–060),
  - `python_topics_advanced.dart` (061–120, authored by pi-python-advanced).
- Generator `tool/generate_python_content.dart` (load-drop-insert; preserves all
  non-Python entries; writes a run manifest).
- Verifier `tool/verify_python_content.dart` + `tool/python_content/run_embedded.py`
  (real-runtime execution).
- Emitted assets: Python segments of
  `assets/content/{tutorials,examples}.json` and `assets/tutorials/python.json`.
- Focused tests: `test/python_content_test.dart`, `test/python_content_render_test.dart`.
- Refresh decision: refresh-only; `example_code_store.dart` was NOT modified.
  Re-seeding defaults replaces built-in Python content; no persisted record is
  deleted by type. Proven by the AC4/R9 tests below.

## Runtime split (honest labeling)

- 116 embedded lessons: verified on the real embedded **MicroPython 1.24.1
  (ecfdd5d)** DLL (`native/build/windows/qfli_py_ffi.dll`).
- 4 CPython lessons (117–120): labeled `需要外部 CPython 环境`, verified on
  **CPython 3.13.3**. Never counted as embedded.

## Verification results

- `dart run tool/verify_python_content.dart`:
  - Embedded: **116 passed, 0 failed** (exit 0, stdout exact match).
  - CPython: **4 passed, 0 failed**.
  - Asset mismatches: **0**.
  - Report: `research/python-content-verification.json`.
- Independent review (pi-python-review, re-run on the real assets):
  - embedded **232/232** (tutorial+example code), CPython **8/8**, fails=0.
  - 120/120 tutorials+examples, EXT=4, difficulty 40/40/40, no missing fields.
  - Other languages: **1500/1500** preserved (100 each); Python 120/120.
  - `sourceLessonId` all `python-tutorial-NNN-lesson`.
  - Report: `research/review-report.md`.
- Tests:
  - `flutter test test/python_content_test.dart` → **9/9** (includes AC4/R9
    preservation: user Python + other-language records survive; no type purge).
  - `flutter test test/python_content_render_test.dart` → **3/3** (both offline
    page data sources render 120 lessons / 120 examples).
  - Shared content suites (repository/tutorial/import/structured/java) → all pass;
    combined run **83/83**.
  - `flutter analyze lib test` (core): clean.
  - `flutter analyze lib test` + `flutter test` (qfli_python app): **57/57** clean.

## Fixes applied during review

- 016/051: removed hard-coded RNG values (embedded RNG differs from CPython).
- 023: set output via `sorted(...)`.
- 042: `sys.platform` assertion instead of printing `win32`.
- 043: `ZeroDivisionError` text `divide by zero` (embedded); noted in pitfalls.
- 046/049/050/052: avoid printing Chinese containers (`repr` escapes non-ASCII);
  drop `json.dumps` kwargs (`ensure_ascii`/`indent` unsupported on embedded).
- 004/027: string step-slicing is unsupported on embedded
  (`NotImplementedError`); fixed exercise answer to `"".join(reversed(s))` and
  documented the limitation in 027.
- `sourceLessonId` corrected to `python-tutorial-NNN-lesson` in generator/verifier.

## Non-blocking reviewer notes

- 094/106/120 exercise answers are prose (concept/verification exercises) —
  accepted by the reviewer.
- 049 explain length — expanded; no explain is under 60 chars.

## Non-Python content safety

- Generator re-reads live files each run and drops only `language == "python"`
  rows; a run manifest lists the preserved foreign ids. Post-run counts confirm
  1500 non-Python tutorials + 1500 non-Python examples unchanged.
