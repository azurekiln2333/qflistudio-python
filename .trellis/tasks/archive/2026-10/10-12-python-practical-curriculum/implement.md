# Implementation plan: Python tutorial/example rewrite (120 lessons)

## Status

Implementation complete and verified; independent review **PASS** (no blocking
items). Acceptance summary: `research/final-summary.md`. Verification totals:
`research/python-content-verification.json`; reviewer verdict:
`research/review-final.md`; commit plan: `research/commit-plan.md`. Refresh-only
decision: no change to `example_code_store.dart`. Not committed by this task;
other languages preserved 1500/1500. Ready for main-session acceptance.

## Prerequisites / ordering

1. **Approval gate (blocking)**: the content lives in shared
   `qfli_studio_core`, outside the writable root. Confirm approval of the
   minimal external file list in
   `research/writable-root-and-content-source.md` §2 (or approval of the
   alternative core content-repository hook) before writing anything outside
   `qfli_python`. Nothing outside the approved list is written.
2. The pipeline edits aggregate assets shared by all language apps. Re-read the
   other-language entries and re-assert their counts/ids are unchanged
   immediately before and after running the generator (which rewrites the
   aggregate files in place). Do not assume any coordination beyond what is
   explicitly recorded.
3. The verifier needs the embedded runtime on the host
   (`native/build/windows/qfli_py_ffi.dll`) or a device. If neither is available,
   record the blocker explicitly instead of claiming verification.

## Ordered work

- [x] 1. Confirm sources/caches and runtime constraints (done:
  `research/content-inventory.md`, `research/runtime-boundary.md`). Re-probe the
  embedded runtime once more right before authoring so the boundary is current.
- [x] 2. Author the 120-topic Python content module under
  `qfli_studio_core/tool/python_content/python_topics.dart` (data only), grouped
  by the PRD progression; each topic carries `runtime: embedded|cpython`.
- [x] 3. Write `tool/generate_python_content.dart`: load existing aggregate JSON,
  drop `language == "python"` entries, insert the new ones, preserve other
  languages and metadata, regenerate `assets/tutorials/python.json` with correct
  runtime metadata. Deterministic.
- [x] 4. Write `tool/verify_python_content.dart`: cross-check authored vs emitted
  records; execute all `embedded` samples against the real embedded runtime and
  diff stdout; execute `cpython` samples in CPython and label them; emit
  `research/python-content-verification.json`. Fail on any mismatch.
- [x] 5. Run generator then verifier; confirm 120/120, all embedded samples
  pass, EXT samples labeled, other-language entries unchanged.
- [x] 6. Refresh-only store behavior: no change to `ExampleCodeStore` (re-seed
  defaults; keep all `_custom` records; add no deletion/cleanup flow). AC4/R9
  preservation tests added in `test/python_content_test.dart`.
- [x] 7. Focused tests: content integrity (counts, unique ids/titles/code,
  1:1 pairing, non-triviality, real line breaks), refresh/preservation, asset
  loading, and the existing navigation/import suites.
- [x] 8. Analyzer + tests: `flutter analyze` and `flutter test` in the Python app
  and in the shared package (content/tutorial/import suites).
- [x] 9. Render smoke via `test/python_content_render_test.dart` (both page data
  sources render 120 lessons / 120 examples).
- [x] 10. Write records: final report with verification totals and the platform
  used; update the task's check notes. See `research/final-summary.md`,
  `research/implementation-report.md`, `research/python-content-verification.json`,
  the independent `research/review-final.md` (PASS), and `research/commit-plan.md`.

## Validation commands

- Generator: `dart run tool/generate_python_content.dart`
- Verifier: `dart run tool/verify_python_content.dart` (uses the embedded DLL on
  host; records the platform)
- Analyzer: `dart analyze` / `flutter analyze` on changed files.
- Tests: `flutter test` for the new Python content suite + `content_repository_test.dart`,
  `tutorial_test.dart`, `content_code_import_test.dart` in core; `flutter test`
  and `flutter analyze` in `qfli_python`.
- Migration: a focused `example_code_store` preservation/refresh test
  (obsolete built-in records replaced; user + other-language records survive).
## Automated content checks (may be a test or part of the verifier)

- Exact 120 tutorial + 120 example Python entries.
- Unique lesson ids, example ids, titles (and no duplicate code bodies).
- 1:1 id pairing and `sourceLessonId` link integrity.
- Non-trivial code: multi-line, not a bare single `print`, not the old
  weighted-sum signature.
- Real line breaks preserved in `code`/`output`.
- Every `embedded` sample passes on the embedded runtime with declared output.
- Every `cpython` sample is labeled and verified in CPython, not counted as
  embedded.
- Asset loading succeeds and pages render (widget smoke at phone width).
- Existing app regression suites still pass.

## Rollback

- Keep a copy of the pre-change Python entries from
  `assets/content/*.json` and `assets/tutorials/python.json` under
  `research/baseline/` before generating. Revert only this task's hunks.

## Risks

- Aggregate-asset corruption of other languages -> generator diff guard +
  unchanged cross-language counts.
- CPython idioms leaking into embedded samples -> `runtime` flag + real-runtime
  execution of all embedded samples.
- Embedded runtime unavailable on host -> record blocker, do not claim pass.
