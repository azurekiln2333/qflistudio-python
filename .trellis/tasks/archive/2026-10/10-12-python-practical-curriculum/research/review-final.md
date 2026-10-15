# Final independent review — 120 Python practical lessons

Reviewer: independent `trellis-check` pi. Scope: this file + `review-tools/*`.
No product/content/generator files were modified by this reviewer; nothing committed.

## Verdict: PASS — no blocking items

Independent verification of the **regenerated real assets** (not Dart source):

| Check | Result | Evidence |
|---|---|---|
| Tutorials / examples | **120 / 120** | `assets/content/{tutorials,examples}.json` |
| 1:1 pairing + `sourceLessonId` | all `python-tutorial-NNN-lesson` | pairing check |
| Structural audit (`review-tools/audit_content.py`) | **FAIL=0**, EXT=4 | emitted JSON |
| Embedded runtime (`review-tools/verify_runtime.py`) | **232/232 pass**, 0 fail | real DLL `MicroPython 1.24.1 (ecfdd5d)` |
| CPython runtime (EXT 117–120) | **8/8 pass** | CPython 3.13 |
| Determinism (`review-tools/scan_nondeterminism.py`) | **0 nondeterministic samples** | 6 runs each |
| Task test suite | **9/9 pass** | `flutter test test/python_content_test.dart` |
| App suite | pass | `flutter test test/python_app_test.dart` |
| Other languages preserved | **1500/1500** (100 each) | count check |
| Level order | 40 beginner / 40 intermediate / 40 advanced | count check |

Verification was run 4 consecutive times end-to-end with identical results
(232/232 embedded, 8/8 CPython, 0 fails).

## Severe defects found during review and confirmed fixed

| id | issue | fix evidence |
|---|---|---|
| F-1 | On-disk assets were **stale** vs generator: `sourceLessonId` lacked `-lesson`, so the task's own test failed (`Expected: python-tutorial-001-lesson Actual: python-tutorial-001`). | Regenerated; all 120 now `-lesson`; test 9/9. |
| F-2 | 004/027 taught `s[::-1]` for **strings**, but embedded raises `NotImplementedError: only slices with step=1` (list step-slice works). | 004 answer `"".join(reversed(s))`; 027 explain/pitfall state the built-in limitation and give the正解. |
| F-3 | 116 task answer was **答非所问** (`discount_by_category` answered with flat `discounted(rate)`). | Now real per-category discount; runs to `32.0` on DLL. |
| F-4 | 061 pitfall over-generalized reflection: claimed `>` raises for `__lt__`-only on CPython. | Per-environment wording verified (CPython `>` uses reflected `__lt__`; embedded does not); `__hash__`/mutable-key pitfall added; `__le__`/`__gt__` task added. |
| F-5 | 075 `wrapper.__name__ = ...` raised `AttributeError: 'closure' object has no attribute '__name__'`; 076 printed `wrapper` not `flaky`; 080 pipeline yielded `[]`. | 075 -> `Memoized` callable object; 076 declared output honestly `wrapper`; 080 corrected. |
| F-6 | 074 printed a measured `耗时(ms)` value into declared output -> **flaky** (`=0`/`=1`). | Rewritten to `timing ok: True` / `elapsed is set: True`; **150/150 runs deterministic**, matches declared. |
| F-7 | 066/084 answers were prose, not code; 076 name mismatch; 077 did not define the requested function; 113 over-claimed `re` support. | All corrected and verified runnable; `re` wording fixed to `sub/compile/match/search`. |

## Runtime boundary facts verified on the real DLL (author guidance confirmed)

`str.isalnum`/`zfill` absent; function `__doc__` absent and function attrs not
settable; `json.dumps` rejects `ensure_ascii`/`indent`/`sort_keys`; class
`__annotations__` absent; `collections.deque` requires `maxlen`; `math.gcd`/
`hypot` absent; dict is **not** insertion-ordered; `repr()` of a container
escapes non-ASCII (`'\uXXXX'`) while `%`/`str.join` do not; string step-slices
are unsupported (list step-slices work); `exec(str)`, `time.ticks_ms/ticks_diff`,
`re.sub/compile/match/search` work.

## AC4 / R9 (user-data preservation) — CLOSED

`test/python_content_test.dart` adds 3 preservation tests (suite 9/9):
a `contentVersion: 0` document mixing a user-created Python record with an
other-language record -> both survive, new built-ins appear, persisted file
keeps the user records; a user override of a built-in id still wins; a second
load is a byte-identical no-op. `example_code_store.dart` is unchanged
(refresh-only), so no record is ever deleted.

## Residual (non-blocking, accepted)

- 3 exercise answers are prose rather than code (094 brute-force verification,
  106 add-a-counter, 120 conceptual GIL/asyncio question) — legitimate.
- `explain` short ones (011/018/049) are CJK-char-count only; total-char length
  is >= 60 and the prose is substantive and correct.

## Reviewer tooling (own scope)

`review-tools/audit_content.py`, `review-tools/verify_runtime.py`,
`review-tools/scan_nondeterminism.py`, `review-tools/extract_and_run.py`,
`review-tools/SEMANTIC_REVIEW.md`, plus snapshots under
`research/review-snapshots/` and machine-readable results
`research/review-*-runtime.json`.
