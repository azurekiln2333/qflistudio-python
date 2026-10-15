# wA:p8 — live Python curriculum audit (120 lessons + 120 examples)

Owner: pi worker `wA:p8` (Python curriculum full audit, task
`.trellis/tasks/10-15-python-release-readiness`).
Repository under test: `D:/MyNewProjects/qfli_python` (pwd + git root verified
equal). Shared core: `D:/MyNewProjects/qfli_studio_core` (clean at `ad17f35`).
No commit performed — coordinator serializes commits.

## 1. Environment / provenance

| Item | Value |
|---|---|
| App pwd + `git rev-parse --show-toplevel` | `D:/MyNewProjects/qfli_python` (equal) |
| App branch | `release/python-storefront-20261015` |
| Core HEAD | `ad17f35` `fix(home): restore project scope tabs in language apps` |
| Core content assets HEAD | `504925a` `feat(content): emit the authored Python curriculum into shipped assets` |
| Core working tree | clean (`git status --porcelain` = 0 lines) |
| Real embedded DLL | `D:/MyNewProjects/qfli_python/native/build/windows/qfli_py_ffi.dll` (713342 bytes) |
| DLL self-reported version | `1.24.1 (ecfdd5d)` via `qfli_py_version()` |
| Host CPython | `Python 3.13.3` |

The DLL is the real embedded MicroPython FFI, loaded via `ctypes.CDLL` and the
app's own `PythonFfiBackend`. No stub/empty implementation is used anywhere in
this audit.

## 2. Runtime verification (actually executed, not referenced)

Command (from `qfli_studio_core`):

```
dart run tool/verify_python_content.dart "D:/MyNewProjects/qfli_python/native/build/windows/qfli_py_ffi.dll" python
```

Observed output:

```
Python:    python
Embedded:  D:\MyNewProjects\qfli_python\native\build\windows\qfli_py_ffi.dll
CPython:   Python 3.13.3
MicroPython: 1.24.1 (ecfdd5d)
Embedded: 116 passed, 0 failed of 116.
CPython:  4 passed, 0 failed of 4.
Asset mismatches: 0.
Report: .../10-12-python-practical-curriculum/research/python-content-verification.json
```

- **116/116 embedded** samples executed on the real MicroPython DLL; declared
  `output` matched real stdout exactly.
- **4/4 CPython** samples (lessons 117–120) executed separately in CPython
  3.13.3 and reported separately — never counted as embedded.
- **0 asset mismatches**: authored sources, aggregate tutorials/examples and the
  legacy `assets/tutorials/python.json` agree on code/output/objective/pitfalls/
  prerequisites/sourceLessonId.

The regenerated report (`research/python-content-verification.json`,
`generatedAt 2026-10-15T10:04:19Z`) records the same 116/4/0 with the real DLL
path and both runtime versions.

## 3. Live content audit (independent script, live JSON)

Script: `research/audit_live_content.py` (this task). Parses the shipped
aggregates directly (no reliance on prior reports).

| Check | Result |
|---|---|
| Python tutorials / examples | **120 / 120** |
| Unique tutorial ids / example ids | 120 / 120 |
| ids contiguous 1..120, ordered beginner→intermediate→advanced | yes (`1..120`, 40/40/40) |
| 1:1 pairing (`sourceLessonId == python-tutorial-NNN-lesson`) | 0 missing, 0 dangling |
| Every tutorial has ≥1 lesson (exactly 1) | yes |
| Duplicate titles | 0 tutorial, 0 example |
| Duplicate code bodies | 0 tutorial, 0 example |
| Empty titles / short (<8 char) fields | 0 |
| Tiny example code (<10 chars) | 0 |
| CPython references | exactly examples 117–120; none elsewhere |
| Placeholder scan (word-boundary: TODO/FIXME/TBD/占位/待补充/…) | **0 real hits** |

Placeholder scan notes (false positives, verified by reading the content):

- `python-tutorial-052` matched `TODO` case-insensitively inside the string
  literal `"todos.json"` (a todo-list lesson). Not a placeholder.
- `python-tutorial-089` matched `占位` inside the pitfall prose
  “删元素后用 None 占位不当，链断了导致查不到后面的元素。” (teaching note about
  misusing `None` as a placeholder in a hash chain). Not a placeholder.

Both lessons contain complete multi-line code with a declared output that the
real runtime reproduces.

## 4. Non-Python preservation

Live aggregate counts (both `assets/content/tutorials.json` and
`assets/content/examples.json`):

- Python: **120**
- Non-Python: **1500** = 15 languages × 100
  (`c, cpp, css, dart, go, html, java, javascript, json, lua, markdown, rust,
  shell, sql, typescript`).
- Core working tree is clean and `git diff HEAD` against the content assets is
  empty → **no aggregate-JSON regeneration is needed and none was performed**;
  other languages' segments were untouched by this audit.

`ExampleCodeStore` is unchanged; the refresh is refresh-only (preserve every
persisted record, no purge by `type`/`language`). User `_custom` records are
retained (proven by the preservation tests below).

## 5. Dart / Flutter tests (actually executed)

| Command | Result |
|---|---|
| `flutter test test/python_content_test.dart` (core) | **9/9** — counts, unique ids/1:1 pairing, unique titles/non-duplicate code/multi-line, required lesson fields + non-empty exercise answers, example≡tutorial code/output + runtime label, real newlines, 3× user-data preservation |
| `flutter test test/python_content_render_test.dart` (core) | **3/3** — 教程 page source renders 120, 示例 page source renders 120, legacy bundle 120 + `runtime.status=available` |
| `flutter test test/content_code_import_test.dart` (core) | **36/36** — import filenames, overwrite/cancel, project registration/entry, editor tab selection, 320/1280px with 2x text, bounded scroll |
| `flutter test test` (app `qfli_python`) | **57/57** |
| `flutter test test/python_lifecycle_test.dart` (app) | **11/11 real MicroPython** — ran against the present DLL (skip condition `File(library).existsSync()==false` is not met, so nothing was skipped); covers cancellation, stop before native completion, artifacts after deleting source, invalid bytecode recovery, project boundaries |

The structural render/import tests confirm the tutorial and example offline page
entry points serve the live 120-lesson/120-example curriculum, and the import
flow (edit → custom name → real snippet project → selected editor tab) still
works against it.

## 6. Old curriculum task (10-12) delivery disposition

`10-12-python-practical-curriculum` is entirely untracked (97 files) and its
pipeline outputs are already committed to the core (`504925a`); its task.json is
still `in_progress` though the work is materially done and re-verified above.

**Keep / commit (durable deliverables)** — per `research/commit-plan.md`:

- Task root: `task.json`, `prd.md`, `design.md`, `implement.md`,
  `implement.jsonl`, `check.jsonl`
- `research/final-summary.md`, `research/implementation-report.md`,
  `research/commit-plan.md`, `research/content-inventory.md`,
  `research/runtime-boundary.md`, `research/curriculum-outline.md`,
  `research/writable-root-and-content-source.md`, `research/approval-record.md`,
  `research/python-content-verification.json`, `research/review-final.md`,
  `research/review-report.md`
- `research/review-tools/{audit_content.py, verify_runtime.py,
  scan_nondeterminism.py, extract_and_run.py, SEMANTIC_REVIEW.md}`

**Keep in workspace but do NOT commit (temp/recovery material)**:

- `research/baseline/` (pre-change asset copies — recovery only)
- `research/advanced/` (author staging/delivery material incl. `__pycache__`)
- `research/review-snapshots/` (old asset snapshots)
- `research/probe-features.py`, `research/probe-modules.py` (one-off probes)
- `research/review-msg-*.txt` (inter-agent messages)
- `research/review-batch{1,2,3}-runtime.json`, `research/review-regress.json`,
  `research/review-audit-final.json`, `research/review-final-runtime.json`
  (repeated run logs / machine-absolute paths; human verdict is `review-final.md`)
- `research/review-tools/*.json`, `research/review-tools/__pycache__/`
- `.trellis/spec/frontend/content-code-import.md` §7 edit (gitignored; keep in
  workspace, never `git add -f`)

Do not `git add -A` in either repo; other workers hold concurrent changes.

## 7. Conclusion

No placeholder content, no duplication, no pairing gap, no structural defect and
no asset drift remain in the live Python curriculum. Structure, 1:1 pairing,
import flow, declared output and runtime labeling all verify against the real
embedded MicroPython DLL and real CPython. **No source change was required by
this audit**; the previously completed 116 embedded + 4 explicitly-labeled
CPython content is retained intact. No aggregate JSON was regenerated.

## 8. Blocking items

None. No blocker was found, so no blocker is recorded. Commit serialization and
final cross-language integration remain the coordinator's responsibility.
