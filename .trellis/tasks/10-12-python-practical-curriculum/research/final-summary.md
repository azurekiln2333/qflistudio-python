# Final summary — Python practical curriculum (120 lessons)

Task: `.trellis/tasks/10-12-python-practical-curriculum` · Status: **PASS, no
blocking items** · Not committed.

## What shipped

120 Chinese tutorial lessons + 120 paired runnable examples, authored in
`qfli_studio_core/tool/python_content/` and emitted into the app's real content
assets; both offline page entry points now serve them.

## Modified / added files

Owned by this task (shared `qfli_studio_core`):

| File | Change |
|---|---|
| `tool/python_content/python_topic.dart` | new — topic model (`runtime: embedded\|cpython`) |
| `tool/python_content/python_topics.dart` | new — aggregation (001–120) |
| `tool/python_content/topics_basics.dart` | new — 001–016 |
| `tool/python_content/topics_containers_functions.dart` | new — 017–040 |
| `tool/python_content/topics_modules_oop.dart` | new — 041–060 |
| `tool/python_content/python_topics_advanced.dart` | 061–120 (authored by pi-python-advanced; only imported here) |
| `tool/python_content/run_embedded.py` | new — real-DLL batch runner |
| `tool/generate_python_content.dart` | new — load-drop-insert generator |
| `tool/verify_python_content.dart` | new — real-runtime verifier |
| `assets/content/tutorials.json` | modified — Python segment (120) |
| `assets/content/examples.json` | modified — Python segment (120) |
| `assets/tutorials/python.json` | modified — 120 lessons, correct runtime metadata |
| `test/python_content_test.dart` | new — integrity + AC4/R9 preservation (9) |
| `test/python_content_render_test.dart` | new — both page data sources (3) |
| `lib/services/example_code_store.dart` | **unchanged** (refresh-only decision) |

Not committed; other-language files and native runtime untouched.

## Counts and runtime verification

| Metric | Result |
|---|---|
| Tutorials / examples (emitted) | **120 / 120** |
| Embedded lessons | **116** verified on real MicroPython `1.24.1 (ecfdd5d)` |
| CPython lessons (117–120) | **4**, labeled `需要外部 CPython 环境`, verified on CPython 3.13.3 |
| `dart run tool/verify_python_content.dart` | embedded **116/116**, CPython **4/4**, asset mismatch **0** |
| Independent review re-run (real DLL) | **116 tutorial + 116 example = 232** embedded passes, **4 + 4 = 8** CPython passes, fails **0** |
| Non-Python entries | **1500/1500** preserved (15 languages × 100) |
| Legacy bundle | 10 chapters / 120 lessons, `runtime.status=available` |

## Check commands and results

| Command | Result |
|---|---|
| `dart run tool/verify_python_content.dart` | embedded 116/116, CPython 4/4, mismatch 0 |
| `flutter test test/python_content_test.dart` | **9/9** (incl. 3 AC4/R9 preservation tests) |
| `flutter test test/python_content_render_test.dart` | **3/3** (教程/示例 page data sources render 120) |
| core content suites (repository/tutorial/import/structured/java) | all pass; combined **83/83** |
| `flutter analyze` (core `lib` + these tests) | **No issues found** |
| `flutter analyze lib test` (qfli_python app) | **No issues found** |
| `flutter test` (qfli_python app) | **57/57** |
| Reviewer `audit_content.py` (real JSON) | FAIL=**0**, 120/120, EXT=4, 40/40/40 |
| Reviewer `verify_runtime.py` (real DLL) | embedded 232/232, CPython 8/8 |

Typical-page check: `content_code_import_test.dart` renders lesson/example
catalog+detail+dialog at 320px and 1280px with 2x text (all pass);
`python_content_render_test.dart` confirms both page data sources serve the
Python curriculum.

## Remaining limitations

- 4 lessons (117–120) genuinely require an external CPython environment and are
  labeled as such; they are **not** claimed to run embedded.
- 3 exercise answers (094/106/120) are prose verification/concept answers, not
  code — accepted by the reviewer.
- `explain` length for 011/018/049 is below 60 **CJK-only** chars (185/185/157
  total chars); substantive and closed as a metric difference, not a defect.
- The embedded runtime is a MicroPython subset (e.g. no `os`/`dataclasses`/
  `datetime`/`functools`/`itertools`; string step-slicing unsupported). These
  differences are documented in-lesson and in `research/runtime-boundary.md`.

## Independent review result

`research/review-final.md` (pi-python-review, **Verdict: PASS — no blocking
items**): tutorials/examples **120/120**; pairing all `python-tutorial-NNN-lesson`;
structural `audit_content.py` **FAIL=0**, EXT=4; `verify_runtime.py` on the real
DLL **116 tutorial + 116 example = 232 embedded passes**, **4 + 4 = 8 CPython
passes**, **0 fails**; `scan_nondeterminism.py` **0 nondeterministic samples**
(6 runs each); task suite **9/9**; other languages **1500/1500** (100 each);
levels 40/40/40. The full chain was run **4 consecutive times** with identical
results. AC4/R9 **CLOSED** via the 3 preservation tests.

Closing round: 074 (nondeterministic `ticks_ms` output, F-6) was fixed by the
advanced author and the assets regenerated; the reviewer re-ran it — lesson +
example each **150/150** runs deterministic, matching the declaration. Defects
F-1…F-7 all confirmed fixed. **No remaining blocking items; no open todos.**

Maintenance contract recorded in
`.trellis/spec/frontend/content-code-import.md` §7.

## Process note

During integration an out-of-bound write accidentally replaced
`python_topics_advanced.dart` with an empty placeholder before the split was
confirmed; it was disclosed immediately, that file is owned by pi-python-advanced
who restored it, and the integrator only imports it. No other owner's file was
overwritten.

## Git file sets and suggested commit messages (NOT committed)

Full, reviewed file lists and suggested messages are in
`research/commit-plan.md`. Summary:

- **qfli_studio_core**: `assets/content/{tutorials,examples}.json` (Python segment),
  `assets/tutorials/python.json`, `tool/python_content/` (module + runner),
  `tool/generate_python_content.dart`, `tool/verify_python_content.dart`,
  `test/python_content_test.dart`, `test/python_content_render_test.dart`.
  Message: `feat(python): replace placeholder Python content with 120 verified lessons + examples`.
- **qfli_python**: `.trellis/spec/frontend/content-code-import.md` and
  `.trellis/tasks/10-12-python-practical-curriculum/`.
  Message: `docs(python): record Python curriculum maintenance contract and task records`.

Explicitly excluded: `lib/services/example_code_store.dart` (unchanged),
`lib/pages/home_page.dart`, `lib/services/studio_profile.dart`, and the
pre-existing OHOS/icon/native dirty changes in the Python repo. Do not
`git add -A`.
