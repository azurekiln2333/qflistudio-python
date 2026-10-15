# Independent semantic review checklist (120 lessons)

The scripts in this directory (`audit_content.py`, `verify_runtime.py`) prove
**structure, counts, runnability and honesty of labels**. They cannot judge
whether a lesson *teaches its named concept*, whether the explanation is
*correct*, or whether content is *filler*. This file is the manual/LLM review
rubric for that part. Review one chapter at a time; record findings with the ids
below and attach a file+line location.

## Method

For each pair `NNN` read, in order:
1. `tutorials.json` -> `python-tutorial-NNN` lesson (`objective`, `explain`,
   `code`, `output`, exercises).
2. `examples.json` -> `python-example-NNN` (`code`, `expectedOutput`).

Then answer every question below. Any "no" is a finding.

## C1 — Concept match (per pair)

- C1.1 Does the lesson title/concept list match what the code actually
  demonstrates? (e.g. a lesson titled `字典进阶：计数与分组` must *count* or
  *group*, not merely print a dict.) **id: S-C1**
- C1.2 Is the concept distinct from the neighboring lessons, or is it the same
  idea re-skinned? (compare NNN with NNN-1 and NNN+1). **id: S-C2**
- C1.3 Does `explain` describe *this* program's mechanics, or is it generic
  prose that would fit any lesson? **id: S-C3**
- C1.4 Do the pitfalls name a *real* mistake a learner would hit for this
  concept (not a generic "注意缩进")? **id: S-C4**

## C2 — Knowledge correctness

- C2.1 Is every claim in `explain` factually correct for Python? Flag
  over-generalizations ("Python 中字符串不可变所以…") that are wrong. **id: S-K1**
- C2.2 Are embedded lessons free of CPython-only APIs presented as working
  (`os`, `datetime`, `dataclasses`, `functools`, `itertools`, `enum`, `typing`,
  `abc`, `contextlib`, `match`, `{**a}`, `dir()` beyond verified subset)?
  Cross-check with `research/runtime-boundary.md`. **id: S-K2**
- C2.3 Is the declared `output` exactly what a correct run produces, including
  ordering that depends on dict/set iteration (which is insertion-ordered in
  this MicroPython but must be deterministic)? **id: S-K3**
- C2.4 Do the exercise `answer`s actually solve the `prompt` and would they run?
  Spot-run at least the advanced chapters. **id: S-K4**

## C3 — Substantiveness (no padding)

- C3.1 Is `explain` substantive Chinese prose (>~60 CJK chars) that adds
  information beyond restating the code? **id: S-Q1**
- C3.2 Is the code a complete program (imports + definitions + observable
  output), not a fragment or a stub? **id: S-Q2**
- C3.3 No near-duplicates: are any two lessons' code bodies structurally the
  same algorithm with renamed variables? (scripts catch exact dupes; this
  catches near-dupes). **id: S-Q3**
- C3.4 Are titles/summaries distinct and specific, with no "综合：… (2)" filler?
  **id: S-Q4**

## C4 — Examples & linking

- C4.1 Is the example genuinely the runnable companion of the lesson (same
  concept, different concrete task), not a byte-copy of the lesson code?
  **id: S-E1**
- C4.2 Does the example's `expectedOutput` reflect its own code? **id: S-E2**
- C4.3 Is `sourceLessonId` pointing at the lesson of its own number? (script
  checks this). **id: S-E3**

## C5 — Runtime labeling honesty

- C5.1 Exactly 4 pairs are EXT, matching the outline (117–120)? Any other pair
  that needs CPython but is labeled embedded is a **severe** finding. **id: S-R1**
- C5.2 Do EXT lessons say `需要外部 CPython 环境` in the lesson, and does the
  example clearly separate embedded-verified from CPython? **id: S-R2**
- C5.3 Does the legacy `assets/tutorials/python.json` now state the real
  MicroPython backend instead of the stale "planned / 纯 Dart 子集解释器"
  claim? **id: S-R3**

## C6 — UI / import regression (spot check, phone width)

- C6.1 Tutorial 教程 tab renders real content for a beginner/mid/advanced
  sample; no mojibake; line breaks in `code` preserved. **id: S-U1**
- C6.2 示例代码 tab copy action copies the **displayed** (possibly edited) code
  with real newlines (per `content-code-import.md`). **id: S-U2**
- C6.3 Import into a project produces a real file with real newlines and opens
  it. **id: S-U3**

## C7 — User-data preservation (store)

- C7.1 Read the actual `_migrateOnLoad` diff: did the implementation avoid a
  `type == 'python'` purge? A Python-type purge would delete user data →
  **severe**. **id: S-D1**
- C7.2 Do the added tests actually mix obsolete built-in Python records +
  a user-created Python record + an other-language record and assert survival
  and idempotence? **id: S-D2**

## Severity mapping

- **Severe**: wrong knowledge taught; CPython-only content claimed embedded;
  user records deleted; missing/placeholder content counted as done.
- **Moderate**: concept/code mismatch; duplicate/near-duplicate lesson;
  example ≠ companion; wrong declared output.
- **Minor**: weak pitfall, terse objective, formatting.
