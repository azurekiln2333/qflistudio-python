# Commit plan (NOT committed) — task 10-12-python-practical-curriculum

Two repositories are involved. Only the files listed below belong to this task.
Nothing has been committed. Other workers' dirty files are explicitly excluded.

## qfli_studio_core — Python content pipeline

Files (all owned by this task):

- `assets/content/tutorials.json` (modified) — Python segment replaced (120 lessons)
- `assets/content/examples.json` (modified) — Python segment replaced (120 examples)
- `assets/tutorials/python.json` (modified) — 120 lessons; corrected runtime metadata
- `tool/python_content/python_topic.dart` (new) — topic model
- `tool/python_content/python_topics.dart` (new) — aggregation 001–120
- `tool/python_content/topics_basics.dart` (new) — 001–016
- `tool/python_content/topics_containers_functions.dart` (new) — 017–040
- `tool/python_content/topics_modules_oop.dart` (new) — 041–060
- `tool/python_content/python_topics_advanced.dart` (new) — 061–120
  (authored by pi-python-advanced; committed here as part of the pipeline)
- `tool/python_content/run_embedded.py` (new) — real-DLL batch runner
- `tool/generate_python_content.dart` (new) — generator
- `tool/verify_python_content.dart` (new) — real-runtime verifier
- `test/python_content_test.dart` (new) — integrity + AC4/R9 preservation
- `test/python_content_render_test.dart` (new) — page data-source render

**Not touched** (excluded from this task): `lib/services/example_code_store.dart`
(refresh-only, unchanged), `lib/pages/home_page.dart`, `lib/services/studio_profile.dart`,
and any other shared-core file changed by other workers.

Suggested commit message:
`feat(python): replace placeholder Python content with 120 verified lessons + examples`

## qfli_python — task records

Fact check (from `git check-ignore`/`git status`): only `.trellis/spec/` is
gitignored (`/.trellis/spec/` in `.gitignore:92`). The task directory is **not**
ignored and shows as untracked (`??`), so the task records below are committable.
The spec edit is a local workspace record only — do **not** force-add it.

- `.trellis/spec/frontend/content-code-import.md` (modified) — §7 maintenance
  contract. **Gitignored**; keep in the workspace, NOT part of any commit, no
  `git add -f`.

### Stage from the task directory

Planning + manifest (task root):

- `.trellis/tasks/10-12-python-practical-curriculum/task.json`
- `.trellis/tasks/10-12-python-practical-curriculum/prd.md`
- `.trellis/tasks/10-12-python-practical-curriculum/design.md`
- `.trellis/tasks/10-12-python-practical-curriculum/implement.md`
- `.trellis/tasks/10-12-python-practical-curriculum/implement.jsonl`
- `.trellis/tasks/10-12-python-practical-curriculum/check.jsonl`

Final reports + durable research (task `research/`):

- `research/final-summary.md`
- `research/implementation-report.md`
- `research/commit-plan.md`
- `research/content-inventory.md`
- `research/runtime-boundary.md`
- `research/curriculum-outline.md`
- `research/writable-root-and-content-source.md`
- `research/approval-record.md`
- `research/python-content-verification.json`
- `research/review-final.md`
- `research/review-report.md`
- `research/review-tools/audit_content.py`
- `research/review-tools/verify_runtime.py`
- `research/review-tools/scan_nondeterminism.py`
- `research/review-tools/extract_and_run.py`
- `research/review-tools/SEMANTIC_REVIEW.md`

### Exclude from the commit target (keep in workspace, do NOT delete)

- `research/baseline/` — pre-change Python asset copies (recovery material)
- `research/advanced/` — advanced author's staging/delivery material
- `research/review-snapshots/` — old asset snapshots
- `research/probe-features.py`, `research/probe-modules.py` — one-off runtime probes
- `research/review-msg-*.txt` — inter-agent messages
- `research/review-batch{1,2,3}-runtime.json`, `research/review-regress.json`,
  `research/review-audit-final.json`, `research/review-final-runtime.json` —
  repeated run logs / machine-absolute-path data (human verdict is
  `review-final.md`; durable result is `python-content-verification.json`)
- any other generated `*.json` under `research/review-tools/`

Suggested commit message (records only; the spec is gitignored and excluded):
`docs(python): record Python curriculum task records`

## Notes

- Run `dart run tool/generate_python_content.dart` then
  `dart run tool/verify_python_content.dart` before committing (currently
  embedded 116/116, CPython 4/4, asset mismatch 0; non-Python 1500/1500).
- Do not `git add -A` in either repo; other workers have concurrent changes.
