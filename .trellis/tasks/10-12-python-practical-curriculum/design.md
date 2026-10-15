# Design: Python tutorial/example rewrite (120 lessons)

## Source of truth and generation

Hand-editing the 3.5 MB aggregate JSON for 240 records is unreviewable.
Mirror the Java precedent (`qfli_studio_core/tool/java_content/*`):

- Author the 120 topics in a **Dart content module** under
  `qfli_studio_core/tool/python_content/` (data only; no `dart:io` in the data
  file). Each topic is a record:
  `id, level, title, summary, concepts, objective, prerequisites, explain, code,
  output, pitfalls, tasks, runtime` where `runtime` is `embedded` or `cpython`.
- A generator `tool/generate_python_content.dart` emits:
  - `assets/content/tutorials.json` (Python entries replaced; other languages
    preserved byte-for-byte by targeted load-drop-insert),
  - `assets/content/examples.json` (Python entries replaced; others preserved),
  - `assets/tutorials/python.json` (legacy bundle regenerated; runtime metadata
    corrected to the real MicroPython backend).
- A verifier `tool/verify_python_content.dart`:
  - cross-checks authored topics against emitted records (counts, ids, 1:1
    pairing, duplicate code/title detection, non-triviality),
  - executes **every** `runtime: embedded` sample against the real embedded
    runtime and diffs stdout against `output`, writing
    `research/python-content-verification.json` with the real version string and
    per-id results,
  - for `runtime: cpython` samples, executes them in CPython and records the
    environment; it never credits the embedded runtime for them,
  - fails on any mismatch.

The generator loads the existing JSON, drops all `language == "python"` entries,
inserts the newly authored entries, and preserves everything else and the
top-level metadata. Deterministic output (stable ordering, stable formatting).

## Real-runtime verification path (critical)

The embedded runtime is MicroPython `1.24.1 (ecfdd5d)`, **not** CPython. On this
host the runnable instance is `native/build/windows/qfli_py_ffi.dll` via
`qfli_py_run_into` (verified). The verifier drives it through a small Python
harness (ctypes) because the shipped artifact is a real DLL; where a device is
required, the run reports the platform used. The verifier MUST NOT fall back to
CPython for `runtime: embedded` samples — a CPython pass does not prove embedded
compatibility (imports like `functools`/`itertools`/`dataclasses` differ).

Boundary facts that gate authoring (see `research/runtime-boundary.md`):

- Available: `math` (partial), `json`, `re` (partial), `random`, `time`
  (partial), `heapq`, `collections`, `struct`, `binascii`, `io`, `sys`, `gc`,
  `micropython`, `array`, `errno`, `u*` aliases.
- Unavailable: `os`, `dataclasses`, `datetime`, `bisect`, `contextlib`,
  `functools`, `itertools`, `enum`, `typing`, `abc`, `zlib`, `socket`,
  `subprocess`, `threading`, `hashlib`, `asyncio`.
- No `match` statement, no dict-merge unpack, no `from typing import`.

## Content plan (120 topics, ordered)

Stable ids `python-tutorial-001..120`; example N paired to tutorial N. Full
table in `research/curriculum-outline.md`. Progression:

- 001–016 fundamentals (print, types, operators, strings, f-strings, bool,
  conversions, input, branches, loops, nested loops, patterns).
- 017–028 containers (list, methods, comprehensions, tuple, dict, sets, string
  ops, sorting/key, enumerate/zip, slicing, word-count).
- 029–040 functions (def/return, args, *args/**kwargs, scope, recursion,
  lambda/higher-order, closures, decorators, generators).
- 041–052 modules/exceptions/files (`import`, packages, try/except/finally,
  custom exceptions, file IO, json, stdlib overview, mini to-do).
- 053–068 OOP (classes, properties, inheritance, polymorphism, dunder methods,
  operator overloading, `__slots__`, composition, dataclass-by-hand, projects).
- 069–080 iterators/generators/functional (iterator protocol, custom iterables,
  `send`, exception design, context managers, decorator/instrumentation,
  functional pipelines).
- 081–096 algorithms/data structures (complexity, search, sorts, heap,
  linked list, stack/queue, hashing, BST, graph DFS/BFS, DP, greedy, backtracking,
  maze).
- 097–108 testing/debugging/engineering (assertions, hand-rolled test harness,
  boundary tests, debugging, error-handling practice, modularity, config,
  validation, logging, performance, style).
- 109–115 integrated projects (ledger, grade analysis, text adventure, matrix,
  regex log analysis, numeric simulation, JSON data modeling).
- 116–120 paradigms + CPython ecosystem (typing/dataclasses, os/datetime,
  threading/asyncio) — the CPython-only ones are `runtime: cpython` and labeled.

## Runtime labeling contract

Each lesson/example carries `runtime: embedded | cpython` in the authoring
module; the generator records it (e.g. example `concepts` include a marker and
the lesson `prerequisites`/`explain` state "需要外部 CPython 环境" for EXT). The
verifier asserts: every `embedded` sample passes on the embedded runtime; every
`cpython` sample is labeled and is NOT counted in the embedded-pass total. The
final report states the two subtotals explicitly (embedded-verified vs
CPython-external). Target: as many of the 120 pairs as the verified boundary
allows are embedded-runnable; the planned split is **116 embedded / 4 CPython**
(see `research/curriculum-outline.md`).

## Refresh (provenance-safe — decision final: refresh-only)

`lib/services/example_code_store.dart` carries **no per-record built-in
provenance** (`ExampleCode` has only `id, type, title, summary, code, output,
sourceLessonId`), and the existing migration purges by `type`. A Python purge
keyed on `type == python` would delete user-created/imported Python examples, so
it is rejected.

**Decision (final): refresh-only, no deletion.**

1. Always re-seed built-in defaults from the new bundled catalog. Old built-in
   Python padding disappears from the UI because it is no longer a default;
   no persisted record is touched.
2. Keep **all** `_custom` user records unconditionally. No cleanup/removal flow
   is added and no record is deleted for any reason (not by type, not by
   heuristic, not by content comparison). User overrides for surviving ids still
   win; user records for obsolete ids are kept as user data.
3. Do not add a provenance marker or any obsolete-record purge. `contentVersion`
   semantics stay as-is for existing behavior; the Python refresh relies only on
   re-seeding defaults.

Tests must prove: obsolete built-in Python records no longer appear as defaults;
a user-created Python record and an other-language record both survive; re-run
is a no-op. See `research/writable-root-and-content-source.md` §3.

## Boundaries

- **Writable root = `qfli_python`.** There is no app-level asset override and no
  `StudioProfile` content hook, and the repository reads the package-prefixed
  asset key first, so the content cannot ship from `qfli_python` alone (see
  `research/writable-root-and-content-source.md`).
- Required write outside the root, **pending explicit approval**: the minimal
  external file list in `research/writable-root-and-content-source.md` §2 —
  The Python portions of `assets/content/{tutorials,examples}.json`,
  `assets/tutorials/python.json`, the new `tool/python_content/*` + generator +
  verifier, the `example_code_store.dart` refresh, and focused core tests.
- **Constraint**: these are shared artifacts consumed by every language app.
  Edits are limited to Python content + the refresh and must preserve all other
  languages byte-for-byte. Re-read the other-language entries and re-assert
  their counts/ids unchanged immediately before and after running the generator
  (which rewrites the aggregate files in place); do not rely on coordination
  that has not been explicitly recorded.
- Alternative (not chosen without approval): add a content-repository hook to
  `StudioProfile` + `home_page.dart` and supply it from `qfli_python`.
- Not touched: navigation, other-language content, CPython/native runtime,
  SQL/MySQL.

## Tradeoffs and risks

- **Aggregate-asset interference**: the generator rewrites two large shared
  files; a bug could corrupt other languages. Mitigation: load-drop-insert, a
  generator diff guard that asserts non-Python entries are unchanged, and
  cross-language counts stay 100/100.
- **Runtime drift**: the embedded boundary was probed on the Windows DLL; Android/
  OHOS must match (same port config, duplicated `mpconfigport.h`). The verifier
  records the platform; a device run is preferred where available.
- **CPython leakage**: the biggest quality risk is teaching CPython idioms that
  silently fail embedded. Mitigation: the `runtime` flag plus real-runtime
  execution of all embedded samples.
- **120 hand-authored programs is large**: the module keeps content reviewable;
  the verifier guarantees runnability.
