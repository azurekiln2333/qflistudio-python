# Independent review report — 120 Python lessons (trellis-check)

Reviewer: independent `trellis-check` pi (not the implementer).
Owned scope: this file + `research/review-tools/*`. Product/content/generator
files are read-only for this reviewer.

Status: **awaiting content ready**. Harnesses are prepared and smoke-tested
against the current (still placeholder) catalog.

## Harnesses (ready)

| Tool | What it proves | Run |
|---|---|---|
| `review-tools/audit_content.py` | counts 120/120, unique ids/titles/code, 1:1 pairing, `sourceLessonId`, no placeholder/padding, non-trivial code, real newlines, concept/text substance thresholds, EXT label presence, other-language counts, legacy runtime metadata honesty, progression order | `python .trellis/tasks/10-12-python-practical-curriculum/research/review-tools/audit_content.py` |
| `review-tools/verify_runtime.py` | independently **re-runs every sample** on the real embedded MicroPython DLL (`1.24.1 (ecfdd5d)`) and in CPython for EXT, diffing declared output; reports embedded vs CPython subtotals | `python .../review-tools/verify_runtime.py --json-out review-runtime.json` |
| `review-tools/SEMANTIC_REVIEW.md` | per-lesson manual rubric for knowledge correctness, concept↔code match, near-duplicate/padding judgment, extension label honesty, UI/import regression, user-data preservation | manual / LLM per chapter |

Both scripts deliberately do **not** import the implementation's Dart tooling
and do **not** trust `research/python-content-verification.json`.

## Smoke-test result on current (pre-implementation) content

- `audit_content.py` -> `tutorials=100 examples=100 EXT=0 FAIL=206 WARN=301`
  (correctly reports the wrong count and flags the old weighted-sum padding and
  the stale legacy runtime metadata). Harness behaves as intended.
- `verify_runtime.py --only 001,002`
  -> `embedded_version=1.24.1 (ecfdd5d) embedded_pass=4 embedded_total=4`.
  Real-runtime path works.

## Confirmed risks to hand to the implementation (from the task materials)

These are real, evidence-backed hazards the implementer must avoid; they are
already reflected in the harnesses.

1. **Legacy bundle is stale today (severe if shipped as-is).**
   `qfli_studio_core/assets/tutorials/python.json` currently has
   `runtime.status = "planned"` and engine text claiming a "纯 Dart 子集解释器（开发中）",
   which is false — the app ships native MicroPython `1.24.1`. R5/AC3 and
   `audit_content.py` A-13 require this to be corrected.
2. **`contentVersion` / provenance hazard (severe if done wrong).**
   `ExampleCodeStore` persists only `_custom`, has no per-record built-in flag,
   and the existing migration purges `type == 'java'`. A Python purge keyed on
   `type == 'python'` would delete user-created/imported Python examples. The
   approved decision is refresh-only (never delete). Any `_isPythonType` purge
   is a severe finding (S-D1).
3. **Sample size change affects the release gate.**
   `content_validator.dart` has `releaseMinimumPerType = 100`; Python going
   100 -> 120 is fine, but other languages must remain `100/100`. The generator
   must preserve non-Python entries byte-for-byte (A-12).
4. **EXT count must stay exactly 4 (117–120).** If any other pair uses a
   CPython-only module (`os`/`datetime`/`dataclasses`/`functools`/…) yet is
   labeled embedded, `verify_runtime.py` will fail it against the real DLL
   (B-03) — this is the primary honesty gate.
5. **Declared output must match real stdout exactly**, including dict/set
   ordering and float formatting. `verify_runtime.py` diffs after only
   normalizing CRLF and the trailing newline.
6. **Input-driven samples.** Lessons using `input()` (e.g. 008) must declare the
   stdin they need; `verify_runtime.py` reads `inputFixtures.stdin` when present,
   otherwise empty stdin -> `EOFError`. Coordinate the exact fixture shape.
7. **Duplicate-title/code gate is strict.** A-04 fails on any exact duplicate
   title or code body across the 120; near-duplicates are left to the semantic
   pass (S-Q3).

## Findings

Snapshot under review: `research/review-snapshots/` + live batch1 run
(`research/review-batch1-runtime.json`). Independent execution on the real DLL
`1.24.1 (ecfdd5d)`; CPython 3.13 for EXT. Content is mid-authoring, so totals
below are partial by design (only existing topics judged).

### Confirmed runtime/behavior findings (embedded-labeled, declared output wrong or unsupported API)

| id | severity | topic/file | finding | evidence |
|---|---|---|---|---|
| RV-016 | severe | 016 topics_basics | `random.seed(42); randint(1,100)` gives **29**, declared "答案是 82". Embedded RNG differs from CPython. Fix declared output to the embedded value or drop the value. | embedded stdout vs declared |
| RV-021 | moderate | 021 topics_containers_functions | dict iteration order differs: declared `name=..\nage=..\nscore=..\ncity=..`, embedded prints `city\nscore\nname\nage`. | embedded stdout |
| RV-023 | moderate | 023 topics_containers_functions | set repr order differs (`{4, 3}` vs `{3, 4}`, `{6,1,2,3,4,5}` vs `{1,2,3,4,5,6}`). | embedded stdout |
| RV-042 | severe | 042 topics_modules_oop | `print(sys.platform)` declared `True`; embedded prints `win32`. | embedded stdout |
| RV-043 | severe | 043 topics_modules_oop | `str(ZeroDivisionError)` is `divide by zero` (MicroPython), declared `division by zero` (CPython wording). | embedded stdout |
| RV-046 | severe | 046 topics_modules_oop | list-of-str `repr` escapes non-ASCII: embedded prints `['\u7b2c\u4e00\u884c', ...]`, declared raw `['第一行', ...]`. | `_probe_repr.py`: EMB `"['\\u82f9\\u679c']"` vs CPY `"['苹果']"` |
| RV-049 | moderate | 049 topics_modules_oop | `json.dumps` key order differs: declared `{"ok": true, "n": null}`, embedded `{"n": null, "ok": true}`. | embedded stdout |
| RV-050 | severe | 050 topics_modules_oop | `json.dumps(..., ensure_ascii=False, indent=2)` raises `TypeError: extra keyword arguments given` on embedded. Unsupported kwargs on an embedded-labeled lesson. | embedded stderr |
| RV-051 | severe | 051 topics_modules_oop | `random.seed(7); randint(1,6)` gives **5**, declared **1**. | embedded stdout |
| RV-052 | severe | 052 topics_modules_oop | same `json.dumps(ensure_ascii=False)` kwargs failure (comprehensive lesson). | embedded stderr |
| RV-075 | severe | 075 python_topics_advanced | `wrapper.__name__ = wrapped.__name__` raises `AttributeError: 'closure' object has no attribute '__name__'` on embedded; you cannot set `__name__` on a closure. | embedded stderr |
| RV-076 | severe | 076 python_topics_advanced | `func.__name__` on a decorated closure returns the inner name `wrapper`, not `flaky`; declared output `[INFO] call flaky(7,)` is wrong. | embedded stdout; `_probe_adv2.py` closure `__name__` = inner name |
| RV-080 | severe | 080 python_topics_advanced | pipeline yields `[]`/`sum 0.0` while declared `[('/c', 0.85)]`/`0.85`. Chained comparison itself works (probed); the composition/logic is the defect. | embedded stdout |

### Semantic / content-quality findings (from SEMANTIC_REVIEW rubric)

| id | severity | topic/file | finding |
|---|---|---|---|
| SV-061 | fixed | 061 | Reflection/pitfall corrected by author (verified: explain + pitfall now per-environment; `__le__/__gt__` task added). |
| SV-070 | moderate | 070 python_topics_advanced | Task answer is a **stub**: `def leaves(self):\n    for n in self:\n        pass` does not implement `leaves()`. `for`-iteration over `self` in the shown iterator neither yields leaves nor returns names. |
| SV-072 | moderate | 072 python_topics_advanced | Task answer key has a typo: `py 关键字 dict` ... and the merge task prompt says "用 itertools 是不可用的" then the answer uses `zip` — acceptable, but prompt wording is garbled ("py 关键字"). Review wording. |
| SV-074 | minor | 074 python_topics_advanced | pitfall typo `tticks_ms` -> should be `ticks_ms`. (074 output was already fixed to match code during authoring.) |
| SV-062/064 | note | 062/064 | 064 correctly discloses that MicroPython ignores `__slots__` (no `__dict__` removal) and its declared output matches embedded — good honesty. Keep this pattern for all runtime-divergent behavior. |

### Harness / tooling facts (for the record, not author bugs)

- **Non-ASCII in container repr is escaped on embedded** (`repr(list/dict/set)`), but not by `%`/`str.join`. Lessons that print Chinese via list/dict/set `repr` must declare the escaped form or avoid container repr (e.g. use `%`/`join`). Root probe: `review-tools/_probe_repr.py`.
- **Closure `__name__`**: embedded returns the innermost function name and rejects assignment to `__name__`; `functools.wraps` is unavailable. Any decorator lesson must not rely on `__name__` preservation. Probe: `review-tools/_probe_adv2.py`.
- **`exec(str)` works** on embedded (066 verified OK).
- **`time.ticks_ms`/`ticks_diff` work** (074 verified OK).

_(rolling; will re-run full 120 structural + runtime audit once all topics are present and stable.)_

### Batch 2/3 — 001–060 fixes re-verified + 061–120 full run

**Independent result: 120/120 embedded samples run exit 0 with byte-exact stdout**
(my own extractor `review-tools/extract_and_run.py`; embedded `1.24.1 (ecfdd5d)`;
EXT 117–120 in CPython). Harness bugs found and fixed during this batch (tooling,
not author defects): paren-count topic splitting -> line-anchored; `\n` escape
decoding for non-raw Dart literals; `output:` key matching inside a code literal
(105). The 001–060 fixes (016/023/042/043/046/049/050/051/052 and ASCII/join
rework of 017/019/025) are confirmed correct in both stdout and explanation.

**Verified runtime-boundary claims (061–120 author, all confirmed)**
`str.isalnum`/`zfill` absent; function `__doc__` absent and function attrs not
settable; `json.dumps(sort_keys=...)` and `ensure_ascii/indent` -> TypeError;
class `__annotations__` absent; `collections.deque` requires `maxlen`;
`math.gcd`/`hypot` absent; dict is **not** insertion-ordered (`{a,c,b}` for
a,b,c). One minor over-claim: `re.match` **does** work on embedded (returns a
match object), not only `sub`/`compile`.

**Confirmed fixes**
- 061 reflection/pitfall split per-environment; `__le__/__gt__` task added.
- 075 reworked to a `Memoized` callable object (no `__name__` assignment).
- 076 declared output now honestly `[INFO] call wrapper(7,)` (real wrapper name).
- 080 pipeline corrected (passes).
- 070 `leaves()` task answer is now a real implementation.
- 074 pitfall typo and 071 wording fixed.

### Open semantic findings (061–120) — task prompt↔answer consistency

| id | severity | topic/file | finding |
|---|---|---|---|
| SV-116 | moderate | 116 python_topics_advanced | **Task "为 Cart 增加 discount_by_category 方法" answer is `def discounted(self, rate): return self.total() * (1 - rate)` — a flat-rate discount, not per-category. 答非所问.** |
| SV-066 | minor | 066 python_topics_advanced | Task "给 make_dataclass 增加默认值支持" answer is prose (`支持 (name, default) 元组…`), not runnable code. |
| SV-084 | minor | 084 python_topics_advanced | Task "统计 merge_sort 总共执行多少次元素比较" answer is prose (`在 merge 中计数并沿递归返回累加即可。`), not code. |
| SV-076 | minor | 076 python_topics_advanced | Task names `validate_non_negative` but answer defines `validate_positive` (behavior correct; name mismatch). |
| SV-077 | minor | 077 python_topics_advanced | Task "构造 square_then_inc(x)" answer prints `compose(inc, square)(4)` without defining/returning `square_then_inc`. |
| SV-004 | severe | 004 topics_basics | Task answer `"hello"[::-1]` fails on embedded (str step-slice). Reported. |
| SV-027 | severe | 027 topics_basics | explain/pitfall claim `s[::-1]` is the standard reversal for strings; embedded raises NotImplementedError for **str** step slices (list works). Reported. |

_(Note: 98/100/101/104/115 flagged by the heuristic are accepted as partial-code
exercise answers — fragment answers are legitimate for "add a case"-style prompts.)_

## FINAL full-content audit (real generated JSON)

Per instructions, output/field checks now read the **actually generated assets**
(`qfli_studio_core/assets/content/{tutorials,examples}.json` +
`assets/tutorials/python.json`), not Dart source. Dart source is used only for
semantic reading.

### Independent results on the emitted JSON

| check | tool | result |
|---|---|---|
| counts 120/120, unique ids/titles/code, pairing, no padding, non-trivial code, real newlines, EXT=4 labeled | `review-tools/audit_content.py` | **FAIL=0**, 120/120, EXT=4 |
| run every lesson+example on the real embedded DLL / CPython | `review-tools/verify_runtime.py` | **embedded 232/232 pass; CPython 8/8 pass; fails=0** (`1.24.1 (ecfdd5d)`) |
| other-language preservation | count check | all 15 other languages still 100/100; only python 120 |
| legacy bundle | read | runtime now `available` / `嵌入式 MicroPython 1.24.1（原生后端）`; 120 lessons |
| extension label honesty | verify_runtime | EXT 117–120 ran in CPython 3.13, never counted embedded |

### SEVERE — generated assets are STALE vs the generator (breaks the task's own test)

- `tool/generate_python_content.dart:203` emits `sourceLessonId:
  '${t.tutorialId}-lesson'` -> `python-tutorial-NNN-lesson`.
- The on-disk `assets/content/examples.json` instead contains
  `sourceLessonId: "python-tutorial-NNN"` (bare) for **all 120** rows.
- Consequence: the task's own committed test
  `test/python_content_test.dart:44` **FAILS** — verified by running
  `flutter test test/python_content_test.dart`:
  `Expected: 'python-tutorial-001-lesson' Actual: 'python-tutorial-001'`.
- Fix: **regenerate** the assets with the current generator
  (`dart run tool/generate_python_content.dart`), confirming non-Python rows stay
  100/100, then re-run the test. (PRD R1 requires the `-lesson` form; C/Dart use
  it, Java uses the bare id.)

### MODERATE — semantic / task-answer issues (reported to owners)

| id | topic | finding | status |
|---|---|---|---|
| SV-116 | 116 | Task "为 Cart 增加 discount_by_category" answer implements a flat `discounted(rate)`, not per-category. 答非所问. | reported to advanced |
| SV-066 | 066 | Task answer is prose, not runnable code. | reported to advanced |
| SV-084 | 084 | Task answer is prose, not runnable code. | reported to advanced |
| SV-076 | 076 | Task names `validate_non_negative`; answer defines `validate_positive` (behavior OK). | reported to advanced |
| SV-077 | 077 | Task "构造 square_then_inc" answer prints a demo without defining it. | reported to advanced |
| SV-004/SV-027 | 004/027 | str step-slice `s[::-1]` is claimed/used as standard but embedded raises `NotImplementedError` (list step-slice works). | reported to terminal |
| SV-BOUND | 117–120 etc | "re 仅 sub/compile" is a slight over-claim: `re.match` also works on embedded. | reported to advanced |

### Non-defects (tooling false positives, corrected)

- `todo` matched inside the word `todos` (052) and `...` inside a string literal
  used as real output (057) — not placeholders.
- 011/018/049 `explain` are 57/59/41 CJK: substantive and correct; below an
  arbitrary 60-char threshold only.
- 116 example code/lesson code identical and outputs match (not a defect).

### Coverage gap to flag

- No focused `ExampleCodeStore` user-preservation test was added, and
  `lib/services/example_code_store.dart` is unmodified. Under the approved
  refresh-only decision the store change may be unnecessary, **but AC4/R9 still
  require a test proving user-created Python records and other-language records
  survive.** This is currently unverified -> recommend the owner add it (or
  record explicitly that the existing behavior already satisfies R9 and prove
  it with a test).

## FINAL verification (post-integration) — all owners' claims re-checked

Re-verified against the **regenerated real assets** after the final round of fixes.

| check | result |
|---|---|
| `sourceLessonId` form | now `python-tutorial-NNN-lesson` for **all 120** (stale-asset defect FIXED) |
| 004 task answer | `"".join(reversed(s))` (FIXED) |
| 027 explain+pitfall | explicitly states built-in str step-slice -> NotImplementedError and gives `"".join(reversed(s))` (FIXED) |
| 116 / 066 / 084 / 076 / 077 task answers | all fixed to real, runnable, prompt-matching answers; 116 runs to `32.0` on the DLL |
| 113 re wording | `sub/compile/match/search` usable, `findall/split` not (FIXED) |
| structural audit (`audit_content.py`) | **FAIL=0**, 120/120, EXT=4 |
| runtime (`verify_runtime.py`, real DLL) | **embedded 232/232 pass; CPython 8/8 pass; fails=0** |
| other languages | **1500/1500 preserved**, each exactly 100 |
| lesson field completeness | 0 missing across all 120; levels 40/40/40 |
| task's own test `flutter test test/python_content_test.dart` | **6/6 pass** |
| app suite `flutter test test/python_app_test.dart` | **24/24 pass** |

### Residual (minor, non-blocking)

- 3 exercise answers are prose rather than code: 094 (brute-force verification
exercise), 106 (add-a-counter exercise), 120 (conceptual GIL/asyncio question).
Each is a legitimate verification/concept exercise; accepted by the reviewer.
- `explain` length: measured **CJK-only** 011=57, 018=59, 049=41, while the
owner's ">=60" metric is **total characters** (185/185/157). All are substantive,
accurate and correct — metric difference, not a defect. Closed.

### AC4/R9 — CLOSED

`test/python_content_test.dart` now adds 3 preservation tests (verified present
and meaningful, suite **9/9 pass**):
1. persisted `contentVersion: 0` doc mixing a user-created Python record + an
   other-language record -> both survive, new built-ins appear, persisted file
   keeps the user records;
2. a user override of a built-in id still wins over the new default;
3. a second load is a byte-identical no-op.
`example_code_store.dart` is unchanged (refresh-only), which satisfies R9 by
construction — no record is ever deleted.

## FINAL STATUS: PASS (no blocking items)

| metric | value |
|---|---|
| tutorials / examples (emitted) | 120 / 120 |
| embedded re-run (lessons+examples) | **232/232 pass**, 0 fail |
| CPython re-run (EXT 117–120) | **8/8 pass** |
| structural FAIL (real JSON) | **0** |
| other languages | 1500/1500 (100 each), unchanged |
| task test suite | 9/9 pass |
| AC4/R9 user-preservation | covered by 3 tests, 9/9 pass |
| severe defects found & fixed | stale assets/sourceLessonId, 004/027 str slice, 116 (答非所问), 061 reflection, 075/076/080 |

## Verification totals (final)

| metric | value |
|---|---|
| tutorials / examples (emitted) | 120 / 120 |
| embedded re-run (lessons+examples) | **232/232 pass**, 0 fail |
| CPython re-run (EXT 117–120) | **8/8 pass** |
| structural FAIL (real JSON) | **0** |
| other languages | 1500/1500 (100 each), unchanged |
| severe defects found & fixed | stale assets / sourceLessonId, 004/027 str slice, 116 (答非所问) |
| open items | R9 user-preservation test (coverage); 3 prose exercise answers (minor) |
