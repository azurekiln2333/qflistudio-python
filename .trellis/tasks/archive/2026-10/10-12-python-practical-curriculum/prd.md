# Replace placeholder Python tutorials with 120 practical lessons

## Goal

Replace the machine-generated placeholder Python tutorial/example content in the
shared `qfli_studio_core` catalog with **120 distinct, progressive, substantive
Chinese lessons** (beginner → advanced/mastery) and **120 runnable companion
examples**, wired into the existing app, verified against the **real embedded
MicroPython runtime**, with a scoped content migration so existing installs stop
showing the old padding.

## Background

- The Python app's two offline pages render from the shared aggregate catalog:
  - 教程 tab -> `LocalTutorialsTab` -> `LocalContentAdapter.loadTutorial` ->
    `AssetContentRepository` -> `assets/content/tutorials.json`.
  - 示例代码 tab -> `ExampleCodeTab` -> `loadExamples` -> `examples.json`.
  - A legacy per-language bundle `assets/tutorials/python.json` is also loaded
    by `TutorialService` (used by tests/other surfaces) and is short/stale
    (says the runtime is "planned"/pure-Dart, which is wrong).
- **Writable-root constraint**: the writable root for this task is
  `qfli_python` only. The content actually shipped by the app lives in the
  sibling package `qfli_studio_core/assets/`, which the AI must not write to
  without explicit approval. See `research/writable-root-and-content-source.md`
  for the confirmed facts: there is **no** app-level asset override or
  `StudioProfile` content hook, and the repository requests the package-prefixed
  asset key first, so an app-local `assets/content/*.json` cannot shadow it.
- Current Python content is placeholder padding: 100 tutorial + 100 example
  entries whose lesson code is the same weighted-sum program with different
  constants; titles are generic and do not teach distinct concepts.
- The runtime is **not CPython**: it is embedded MicroPython `1.24.1 (ecfdd5d)`,
  ROM level `EXTRA_FEATURES`. Its stdlib is a subset; e.g. `os`, `dataclasses`,
  `datetime`, `itertools`, `functools`, `contextlib`, `enum`, `typing`, `abc`,
  `match`, dict-merge are unavailable or unsupported. See
  `research/runtime-boundary.md` for the empirically verified boundary.

## Requirements

- **R1 Count and identity**: exactly **120** Python tutorial entries and **120**
  Python example entries in the aggregate catalog, paired 1:1 by stable id
  (`python-tutorial-NNN` <-> `python-example-NNN`,
  `sourceLessonId: python-tutorial-NNN-lesson`). Unique ids and titles. No
  clone/template padding, no TODO/ellipsis/pseudocode, no repeated trivial
  `print`. Exactly one "第一个程序 / Hello World" introduction.
- **R2 Runnable examples, honestly scoped**: the set is **120 tutorial + 120
example pairs** total. Each example is a complete program that executes **in a
truly runnable environment** and produces its declared `expectedOutput`, and is
verified by running it there; embedded and CPython examples are **counted
separately**. As many pairs as possible are **embedded-runnable** and verified
on the bundled MicroPython runtime; the CPython-extension lessons carry an
explicit "需要外部 CPython 环境" label and are verified in CPython, never counted
as embedded. No network, no external services, no external files beyond the
project's `input.txt`.
- **R3 Honest runtime labeling**: lesson/example count is reported as two
explicit subtotals — embedded-verified vs CPython-external. Topics that are
CPython-only are labeled as requiring an external CPython environment and are
NOT presented as passing in the bundled runtime. Their example code, if present,
is verified in CPython and clearly separated; embedded-verified output is never
faked.
- **R4 Lesson quality**: each lesson has a one-line objective, prerequisites
  where useful, accurate and substantive Chinese explanation, a complete
  runnable code sample, expected output/observable behavior, key code
  commentary, common pitfalls, and verifiable exercises (prompt/hint/answer).
- **R5 Replace outdated content**: remove all old built-in Python tutorial/
  example padding feeding these pages, including the stale legacy
  `assets/tutorials/python.json` metadata. Add a scoped refresh/migration that
  drops obsolete **built-in** Python records without touching user projects,
  sources, user-created examples, or other languages (see R9).
- **R9 Preserve user data (provenance-safe refresh — decided)**: the tutorial/
example store carries no per-record "built-in vs user" provenance. The decision
is **refresh-only**: re-seed built-in defaults from the new catalog and keep
**all** `_custom` user records. No cleanup/deletion flow is added; records are
never removed by type or by any heuristic. A test must prove user-created Python
records and other-language records all survive.
- **R10 Writable-root / approval boundary**: the implementation must fit the
  writable root = `qfli_python`. If shipping real content requires writing the
  shared package, the exact minimal external file list and the reason must be
  listed and left **pending explicit approval**; nothing outside the approved
  list is written.
- **R6 Coverage**: the ordered set covers, at minimum: language basics, data
  structures, functions, modules, exceptions, file I/O, OOP, iterators/
  generators, decorators, algorithms, testing/debugging, engineering practice,
  and integrated projects; plus an explicitly-labeled CPython-ecosystem section.
- **R7 Compatibility**: preserve the existing tutorial/example navigation and
  import behavior and the real line breaks in display/copy/import. Tutorials are
  Chinese by default and follow the existing i18n contract; do not invent new
  localization keys.
- **R8 Scope**: Python content + the content generator/verifier + the scoped
  migration + focused tests. Shared-core edits limited to what the content
  pipeline and migration require. No navigation redesign, no other-language
  content.

## Acceptance Criteria

- [ ] **AC1** Exactly 120 tutorial + 120 Python example entries in the aggregate
  catalog, stable 1:1 pairing, unique ids/titles, no placeholders or
  near-duplicates; a beginner->advanced progression is evident in order.
- [ ] **AC2** All 120 example programs (and every lesson `code`) execute in their
declared environment and produce their declared output; a per-id result report
(code/output/error) is captured. Counts are reported as two subtotals:
**embedded-verified** (target: as close to all 120 as the verified runtime
boundary allows) and **CPython-external** (the explicitly-labeled EXT lessons).
No example is counted in the embedded subtotal unless it actually ran on the
embedded runtime; EXT examples are never presented as embedded.
- [ ] **AC3** Each lesson has objective, prerequisites, substantive explanation,
  complete code, expected output, pitfalls, and exercises in useful Chinese;
  concepts are distinct per topic.
- [ ] **AC4** Old generated built-in Python records are replaced, using the
  provenance-safe refresh scheme in `design.md`. No user-created example, user
  project/source, or other-language record is ever deleted (verified by a test
  that mixes obsolete built-in records with user records and asserts the user
  records survive).
- [ ] **AC7** The solution respects the writable root: any required write to the
  shared `qfli_studio_core` package is enumerated as a minimal external file
  list with reasons and is explicitly approved before writing.
- [ ] **AC5** Automated checks enforce: exact 120/120 counts, unique lesson/
  example ids, no duplicate code bodies/titles, 1:1 id pairing and link
  integrity, non-trivial code (multi-line, not a bare `print`), real line
  breaks, and successful asset loading; the app's existing navigation/import
  tests still pass.
- [ ] **AC6** `flutter analyze` and `flutter test` pass in the Python app and the
  shared package; representative beginner/intermediate/advanced tutorial and
  example pages render at phone width with real content and are inspected.

## Out of scope

- CPython runtime, pip, native `.so`/`.mpy` toolchain work, other languages,
  non-content navigation changes.

## Notes

- Authoring is done in a reviewed Dart content module under
  `qfli_studio_core/tool/python_content/` (data only, no `dart:io`), emitted to
  the JSON assets by a generator, and verified by a real-runtime verifier, so the
  pipeline is reproducible and all 120 examples are executed as part of
  verification.
