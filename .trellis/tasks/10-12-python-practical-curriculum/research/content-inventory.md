# Content inventory, source of truth, and runtime constraints

Read-only research for task `10-12-python-practical-curriculum`. No product code
was edited. All facts below were verified against the working tree and the real
embedded runtime.

## 1. Two content systems exist

There are **two independent bundled content systems** in the shared package
`qfli_studio_core`; the Python app consumes both. They must not be confused.

### A. Aggregate catalog (the source of truth for the two offline pages)

- Files:
  - `qfli_studio_core/assets/content/tutorials.json` (1,600 entries, 100 per
    language; top-level `{schemaVersion, kind, updatedAt, entries:[...]}`).
  - `qfli_studio_core/assets/content/examples.json` (1,600 entries; same shape).
- Reader chain (what the pages actually render):
  - `lib/pages/local_content_pages.dart` -> `LocalTutorialsTab` (教程 tab) and
    `ExampleCodeTab` (示例代码 tab).
  - `lib/content/asset_content_repository.dart` -> loads the two aggregate
    assets.
  - `lib/content/local_content_adapter.dart` -> maps typed entries into the
    legacy page models (`Tutorial` / `ExampleCode`).
  - `lib/content/content_repository.dart` -> `ContentCatalog.fromJson` parsing.
  - `lib/content/content_validator.dart` -> `releaseMinimumPerType = 100`.
- Python portion today: ids `python-tutorial-001..100` and
  `python-example-001..100`, exactly **100 + 100**, one lesson per tutorial
  entry, `sourceLessonId` pairing `python-example-NNN` -> `python-tutorial-NNN-lesson`.
- Quality today: **machine-generated padding**. Every entry's lesson `code` is
  the same weighted-sum program with a different constant and a generic
  title/summary; `python-tutorial-001` and `python-tutorial-002` differ only in
  their literals. This is placeholder content and is the primary thing to
  replace.

### B. Legacy per-language tutorial bundle

- Files: `qfli_studio_core/assets/tutorials/<lang>.json` for
  `c, cpp, web, python, java, dart, lua`.
- Reader: `lib/services/tutorial_service.dart` (`TutorialService.bundledLanguages`
  includes `python`) using `Tutorial`/`TutorialChapter`/`TutorialLesson`
  (`lib/models/tutorial.dart`).
- Python file today: `assets/tutorials/python.json` — **5 chapters, ~13 lessons**,
  hand-written but short and partially stale (its `runtime.status` is
  `"planned"`, engine text says "纯 Dart 子集解释器（开发中）", which is **wrong**:
  the app now ships the native MicroPython 1.24.1 backend). Content quality is
  good per-lesson but the coverage and the runtime metadata are outdated.
- Note: `qfli_studio_core/build/unit_test_assets/assets/tutorials/python.json`
  is a build copy; regenerate by rebuilding test assets, never hand-edit.

### C. Java precedent (same class of work, already done)

`qfli_java/.trellis/tasks/10-09-java-tutorial-rewrite/` already replaced the
Java aggregate entries via a reviewed Dart content module + generator +
real-toolchain verifier, plus a scoped `ExampleCodeStore` migration. Its shape
is the template to mirror for Python:

- `tool/java_content/java_topics.dart` (authored data, no `dart:io`),
- `tool/generate_java_content.dart` (drop+insert into the aggregate assets,
  preserve other languages),
- `tool/verify_java_content.dart` (compile/run every sample, per-id report),
- `ExampleCodeStore.contentVersion` bump + `_migrateOnLoad` purges obsolete
  built-in records while preserving other languages and user records.

## 2. Store / migration

`lib/services/example_code_store.dart`:

- `contentVersion = 2` today; `_migrateOnLoad` purges records whose
  `type == 'java'` when a persisted document is older than `contentVersion`.
- Migration is keyed by **content type**, not language-string matching; the Java
  purge is hard-coded to `_isJavaType`. Python needs an equivalent scoped purge:
  on load, if `storedVersion < contentVersion`, drop records whose type is
  `python` (old generated ids are reused, so the real risk is stale *user-saved*
  copies of the old code). Bump `contentVersion` again so both Java and Python
  purges run once.
- User overlay records are persisted to `<app storage>/examples.json`; user
  projects/sources/other languages must survive.

## 3. Runtime boundary — the decisive constraint

The app does **not** run CPython. It runs embedded **MicroPython 1.24.1
(ecfdd5d)**, compiled at ROM level `EXTRA_FEATURES`, from
`native/port/mpconfigport.h` (and its duplicate
`native/micropython_embed/port/mpconfigport.h`). Empirical probing is required,
because MicroPython's stdlib is a *subset* of CPython and silently differs.

### Empirically verified (Windows FFI DLL, `native/build/windows/qfli_py_ffi.dll`)

Probe method: `ctypes` -> `qfli_py_run_into(...)` on the real shipped DLL,
`qfli_py_version()` = `1.24.1 (ecfdd5d)`. Results (code/output/error):

**Available modules** (import succeeds): `math`, `cmath`, `json`, `re`
(partial), `random`, `time`, `heapq`, `collections`, `struct`, `binascii`,
`io`, `sys`, `gc`, `micropython`, `array`, `errno`, and the `u*` aliases
(`utime`, `ustruct`, `ubinascii`, `uheapq`, `ucollections`).

**NOT available** (ImportError): `os`, `dataclasses`, `datetime`, `bisect`,
`contextlib`, `functools`, `itertools`, `enum`, `typing`, `abc`, `zlib`,
`socket`, `subprocess`, `threading`, `hashlib`, `select`, `uctypes`, `asyncio`,
`deflate`, `framebuf`.

**Language features**

- Works: f-strings (incl. `f'{3.14159:.2f}'`, `f'{3:03d}'`, `'{:>5}'.format`),
  walrus `:=` (incl. in comprehensions), generators, decorators (with
  `functools.wraps`-free custom wrappers), context-manager classes
  (`__enter__`/`__exit__`), iterator protocol (`__iter__`/`__next__`),
  `@property`, `@staticmethod`/`@classmethod`, `super()`, `__slots__`, exception
  handling with `finally`, `divmod`, tuple unpacking with star
  (`a, *b = ...`), dict literals, `sorted(key=...)`, `map`/`lambda`,
  `class`-based everything.
- **Does NOT work**: `match` statement (`SyntaxError`), dict merge/unpack
  `{**a, 'b': 2}` and `[*d]` in some forms (`SyntaxError: *x must be assignment
  target`), `from typing import ...`, dataclasses, `abc`.
- `re` is **not CPython `re`**: `re.sub` and `re.compile` work; `re.findall`,
  `re.match`, `re.search` raise (`AttributeError`/`TypeError`). Tutorials must
  use the MicroPython `re` subset or the `re` module page must state the subset.
- `math` is partial: `math.gcd` is missing; `math.pi`, `math.sqrt`,
  `math.pow`, `math.floor` work.
- `collections.deque` exists but constructor kwargs differ
  (`deque([1,2])` OK; some forms raise). `time.time()` missing;
  `time.sleep_ms()` works; `time.localtime()/gmtime()/mktime()` enabled by port
  config.
- `gc.collect()` returns `None` (not an int) — `gc.collect() >= 0` raises.
- `sys.exit(0)`/`sys.exit()` -> exit 0; `sys.exit(3)` -> exit 3 no traceback;
  `sys.exit('reason')` -> exit 1, reason in error stream; uncaught exception ->
  exit 1 with traceback in `error`.
- `input()` reads from the finite stdin buffer (fed from project `input.txt`);
  `input().split()` + `int()` works; EOF raises `EOFError`.
- `open('notes.txt','w')`/`'r'` work inside the project; `compile_only`
  (`checkSyntax`) produces no output and no side effects.
- `sys.argv[0]` is the absolute entry path; `sys.platform` is `win32`/`android`/
  `ohos`/`darwin`/`linux` per host.

### Consequences for content authoring (hard rules)

- Every runnable sample must use only the verified-available subset above.
- **Every** sample must be executed against the real embedded runtime before it
  ships (host FFI DLL on Windows, or Android/OHOS device), and its declared
  `output` diffed. Availability cannot be inferred from CPython docs.
- Advanced/CPython-only topics (dataclasses, typing, contextlib, functools,
  itertools, enum, abc, os, datetime, threading, asyncio, sockets, typing,
  match, dict-merge) may be **taught**, but must be explicitly marked as
  requiring an external CPython environment and **must not** be presented as
  running in the bundled runtime. If they carry a runnable example, the example
  must be verifiable in the environment they claim (documented separately), not
  faked as embedded output.

## 4. Verification tooling available on this host

- Python 3.13 at `D:\ProgramFiles\Python\Python313\python.exe` (can drive the
  DLL via ctypes for a real-runtime verifier).
- Windows FFI DLL: `native/build/windows/qfli_py_ffi.dll` (MicroPython 1.24.1).
- Android arm64/x86_64 `.so` present under `native/build/cmake-*` but not
  runnable on host.
- **No** `gcc`/`clang`/`cmake` on host PATH, so `native/tests/run_host.sh`
  (C smoke) cannot be rebuilt here without a toolchain; the prebuilt DLL is the
  host execution path.
- `flutter`/`dart` available via `D:\ProgramFiles\flutter_ohos\bin`.

## 5. Existing tests and validation surfaces

- `lib/content/content_validator.dart` enforces per-type counts when
  `enforceReleaseMinimum` is set; default `releaseMinimumPerType = 100`. Since
  Python already has exactly 100/100, a rewrite must keep **>= 100** of each.
- `test/` in core has content/tutorial/import suites
  (`content_code_import_test.dart`, `content_repository_test.dart`,
  `tutorial_test.dart`, `structured_content_test.dart`).
- The Python app repo (`qfli_python`) has its own `test/` suite and
  `flutter analyze`/`flutter test` gates (see
  `.trellis/spec/frontend/python-workflow.md`).
- `content-code-import.md` spec requires the two pages' display/copy/import
  behavior and real line breaks be preserved; a rewrite must not regress them.
