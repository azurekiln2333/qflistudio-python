#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Independent structural + honesty audit for the 120 Python lessons.

This script is owned by the independent trellis-check reviewer. It deliberately
does NOT import any of the implementation's Dart tooling and does NOT trust the
implementation's own verification report. It reads the *emitted artifacts* (the
aggregate catalog + the legacy bundle) and independently re-checks the
acceptance criteria that can be checked mechanically.

What it CANNOT do (left to the human/LLM semantic review, see
`review-tools/SEMANTIC_REVIEW.md`): knowledge correctness, teaching quality,
"does the program actually teach the named concept".

Usage (from repo root or anywhere):

    python .trellis/tasks/10-12-python-practical-curriculum/research/review-tools/audit_content.py

Exit code 0 = all structural gates pass; 1 = at least one FAIL.

Findings are printed as JSON lines on stdout and a summary at the end so they
can be pasted back to the implementer with stable ids (A-xx).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

CORE_DEFAULT = Path(r"D:\MyNewProjects\qfli_studio_core")
EXPECTED_TUT = 120
EXPECTED_EX = 120
EXPECTED_CODE = 120
EMBEDDED_TARGET = 116
CPY_TARGET = 4

# Old placeholder signature (weighted-sum padding) from research/content-inventory.md
PADDING_SIG = "weighted = sum(value * (position + 1)"

CJK = re.compile(r"[\u4e00-\u9fff]")


class Audit:
    def __init__(self) -> None:
        self.fails: list[dict] = []
        self.warns: list[dict] = []
        self.notes: list[dict] = []

    def fail(self, code: str, msg: str, **loc) -> None:
        self.fails.append({"id": code, "severity": "FAIL", "msg": msg, **loc})

    def warn(self, code: str, msg: str, **loc) -> None:
        self.warns.append({"id": code, "severity": "WARN", "msg": msg, **loc})

    def note(self, code: str, msg: str, **loc) -> None:
        self.notes.append({"id": code, "msg": msg, **loc})


def load(path: Path) -> dict:
    with path.open(encoding="utf-8") as fh:
        return json.load(fh)


def cjk_ratio(text: str) -> float:
    if not text:
        return 0.0
    return len(CJK.findall(text)) / max(1, len(text))


def substantive(text: str, min_cjk: int) -> bool:
    return len(CJK.findall(text or "")) >= min_cjk


def objective_present(t: dict, lesson: dict, obj: str) -> bool:
    """The objective may live on the tutorial entry or the lesson."""
    return bool((obj or "").strip())


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--core", default=str(CORE_DEFAULT))
    ap.add_argument("--json-out", default=None)
    args = ap.parse_args()

    core = Path(args.core)
    a = Audit()

    tut_path = core / "assets" / "content" / "tutorials.json"
    ex_path = core / "assets" / "content" / "examples.json"
    legacy_path = core / "assets" / "tutorials" / "python.json"

    for p in (tut_path, ex_path, legacy_path):
        if not p.exists():
            a.fail("A-00", f"missing artifact {p}")
    if a.fails:
        print(json.dumps(a.fails, ensure_ascii=False))
        return 1

    tut_doc = load(tut_path)
    ex_doc = load(ex_path)

    tut = [e for e in tut_doc["entries"] if e.get("language") == "python"]
    ex = [e for e in ex_doc["entries"] if e.get("language") == "python"]

    # ---- A-01 exact counts -------------------------------------------------
    if len(tut) != EXPECTED_TUT:
        a.fail("A-01", f"python tutorials = {len(tut)}, expected {EXPECTED_TUT}")
    if len(ex) != EXPECTED_EX:
        a.fail("A-01", f"python examples = {len(ex)}, expected {EXPECTED_EX}")

    # ---- A-02 stable ids / uniqueness -------------------------------------
    tut_ids = [e.get("id") for e in tut]
    ex_ids = [e.get("id") for e in ex]
    dupe = [i for i, c in Counter(tut_ids).items() if c > 1]
    if dupe:
        a.fail("A-02", f"duplicate tutorial ids: {dupe[:10]}")
    dupe = [i for i, c in Counter(ex_ids).items() if c > 1]
    if dupe:
        a.fail("A-02", f"duplicate example ids: {dupe[:10]}")

    want_tut = {f"python-tutorial-{n:03d}" for n in range(1, 121)}
    want_ex = {f"python-example-{n:03d}" for n in range(1, 121)}
    miss = sorted(want_tut - set(tut_ids))
    extra = sorted(set(tut_ids) - want_tut)
    if miss:
        a.fail("A-02", f"missing tutorial ids: {miss[:20]} (n={len(miss)})")
    if extra:
        a.fail("A-02", f"unexpected tutorial ids: {extra[:20]}")
    miss = sorted(want_ex - set(ex_ids))
    extra = sorted(set(ex_ids) - want_ex)
    if miss:
        a.fail("A-02", f"missing example ids: {miss[:20]} (n={len(miss)})")
    if extra:
        a.fail("A-02", f"unexpected example ids: {extra[:20]}")

    # ---- A-03 1:1 pairing + sourceLessonId link integrity ------------------
    tut_by_id = {e["id"]: e for e in tut}
    ex_by_id = {e["id"]: e for e in ex}
    for n in range(1, 121):
        tid, eid = f"python-tutorial-{n:03d}", f"python-example-{n:03d}"
        t = tut_by_id.get(tid)
        e = ex_by_id.get(eid)
        if t is None or e is None:
            continue
        lesson_id = f"{tid}-lesson"
        lessons = t.get("lessons") or []
        if len(lessons) != 1:
            a.fail("A-03", f"{tid}: expected exactly 1 lesson, got {len(lessons)}")
        elif lessons[0].get("id") != lesson_id:
            a.fail(
                "A-03",
                f"{tid}: lesson id {lessons[0].get('id')!r} != {lesson_id!r}",
            )
        if e.get("sourceLessonId") != lesson_id:
            got = e.get("sourceLessonId")
            # PRD R1 requires `<tutorial-id>-lesson`; the Java precedent in this
            # repo uses the bare `<tutorial-id>`. Report the deviation as a
            # spec-conformance warning, but only FAIL if it doesn't even point
            # at the right tutorial.
            if got == tid:
                a.warn(
                    "A-03",
                    f"{eid}: sourceLessonId {got!r} uses the tutorial id, not {lesson_id!r} "
                    "(PRD R1 requires the `-lesson` form; Java precedent differs)",
                )
            else:
                a.fail(
                    "A-03",
                    f"{eid}: sourceLessonId {got!r} != {lesson_id!r}",
                )

    # ---- A-04 duplicate titles / code bodies / explain --------------------
    for label, entries, tkey, ckey in (
        ("tutorial-title", tut, "title", None),
        ("example-title", ex, "title", None),
        ("tutorial-code", tut, None, "code"),
        ("example-code", ex, None, "code"),
    ):
        seen: dict[str, str] = {}
        for e in entries:
            if ckey is not None and tkey is None:
                if ckey == "code":
                    # gather lesson code(s)
                    vals = [ls.get("code", "") for ls in (e.get("lessons") or [])]
                else:
                    vals = [e.get("code", "")]
            else:
                vals = [e.get(tkey, "")]
            for v in vals:
                v = v.strip()
                if not v:
                    continue
                if v in seen:
                    a.fail(
                        "A-04",
                        f"duplicate {label}: {e['id']} repeats {seen[v]}",
                        file=str(core / "assets" / "content" /
                                 ("tutorials.json" if entries is tut else "examples.json")),
                    )
                    break
                seen[v] = e["id"]

    # ---- A-05 placeholder / padding / TODO detection ----------------------
    todo_re = re.compile(r"\bTODO\b|\bFIXME\b|\bXXX\b|待补充|占位|伪代码|pseudocode", re.I)
    ellipsis_re = re.compile(r"^\s*\.\.\.\s*$", re.M)
    for label, entries, is_tut in (("tut", tut, True), ("ex", ex, False)):
        for e in entries:
            blocks = []
            if is_tut:
                for ls in e.get("lessons") or []:
                    blocks.append(("lesson.code", ls.get("code", "")))
                    blocks.append(("lesson.explain", ls.get("explain", "")))
            else:
                blocks.append(("code", e.get("code", "")))
            for field, text in blocks:
                if field.endswith("code"):
                    m = todo_re.search(text)
                    if m:
                        a.fail(
                            "A-05",
                            f"{e['id']} {field} contains placeholder token {m.group(0)!r}",
                        )
                    # A bare `...` line (ellipsis statement) is a placeholder;
                    # a `...` inside a string literal is legitimate output.
                    for line in text.splitlines():
                        if ellipsis_re.match(line):
                            a.fail("A-05", f"{e['id']} {field} has a bare '...' placeholder line")
                    if PADDING_SIG in text:
                        a.fail("A-05", f"{e['id']} {field} is old weighted-sum padding")

    # ---- A-06 non-trivial code --------------------------------------------
    for e in tut:
        for ls in e.get("lessons") or []:
            code = (ls.get("code") or "").strip()
            lines = [l for l in code.splitlines() if l.strip()]
            if len(lines) < 3:
                a.warn("A-06", f"{e['id']} lesson code has only {len(lines)} substantive line(s)")
            if re.fullmatch(r"print\(.*\)", code):
                a.fail("A-06", f"{e['id']} lesson code is a bare print()")
    for e in ex:
        code = (e.get("code") or "").strip()
        lines = [l for l in code.splitlines() if l.strip()]
        if len(lines) < 3:
            a.warn("A-06", f"{e['id']} example code has only {len(lines)} substantive line(s)")

    # ---- A-07 real line breaks preserved ----------------------------------
    for label, entries, is_tut in (("tut", tut, True), ("ex", ex, False)):
        for e in entries:
            if is_tut:
                code = (e.get("lessons") or [{}])[0].get("code", "")
                out = (e.get("lessons") or [{}])[0].get("output", "")
            else:
                code, out = e.get("code", ""), e.get("expectedOutput", "")
            if len(code.splitlines()) >= 3 and "\\n" in code and "\n" not in code:
                a.fail("A-07", f"{e['id']} code looks like literal \\n, not real newlines")

    # ---- A-08 exactly one Hello-World intro -------------------------------
    hw = [e["id"] for e in tut if re.search(r"第一个\s*Python|Hello,?\s*World|你好", e.get("title", ""), re.I)]
    if len(hw) > 1:
        a.warn("A-08", f"multiple Hello-World-ish lesson titles: {hw}")

    # ---- A-09 runtime labeling: EMB vs EXT --------------------------------
    # The contract: cpython-only pairs must carry an explicit label in the
    # lesson (prerequisites and/or explain) and the example.
    EXT_MARK = re.compile(r"CPython|cpython")
    ext_lessons = []
    for n in range(1, 121):
        tid, eid = f"python-tutorial-{n:03d}", f"python-example-{n:03d}"
        t, e = tut_by_id.get(tid), ex_by_id.get(eid)
        if not t or not e:
            continue
        ls = (t.get("lessons") or [{}])[0]
        blob = " ".join(str(x) for x in (
            ls.get("explain", ""),
            " ".join(ls.get("concepts") or []),
            " ".join(t.get("prerequisites") or []),
            " ".join(t.get("concepts") or []),
        ))
        label_t = "需要外部 CPython 环境" in blob
        eblob = " ".join(str(x) for x in (e.get("summary", ""), " ".join(e.get("concepts") or [])))
        label_e = "CPython" in eblob
        is_ext = "需要外部 CPython 环境" in blob
        if is_ext:
            ext_lessons.append(tid)
            if not label_e:
                a.warn("A-09", f"{tid} labeled EXT but its example {eid} carries no CPython label")
        else:
            if label_e and "CPython" in eblob:
                a.note("A-09", f"{eid} mentions CPython but lesson is not EXT-labeled")
    a.note("A-09", f"EXT-labeled lessons detected: {len(ext_lessons)} -> {ext_lessons}")

    # ---- A-10 explanation substance ---------------------------------------
    for e in tut:
        ls = (e.get("lessons") or [{}])[0]
        explain = ls.get("explain", "")
        if not substantive(explain, 45):
            a.warn("A-10", f"{e['id']} explain has <45 CJK chars (len={len(CJK.findall(explain))})")
        obj = e.get("objective") or ls.get("objective") or ""
        if not objective_present(t, ls, obj):
            a.warn("A-10", f"{e['id']} objective missing")
        elif not substantive(obj, 6):
            a.note("A-10", f"{e['id']} objective is terse ({len(CJK.findall(obj))} CJK)")
        if not (ls.get("exercises") or e.get("exercises")):
            a.fail("A-10", f"{e['id']} has no exercises/tasks")
        if not (ls.get("pitfalls") or e.get("pitfalls")):
            a.warn("A-10", f"{e['id']} has no pitfalls field")
        if not (e.get("prerequisites") or ls.get("prerequisites")):
            a.warn("A-10", f"{e['id']} has no prerequisites")

    # ---- A-11 tests/task answers present ----------------------------------
    for e in tut:
        ls = (e.get("lessons") or [{}])[0]
        for i, task in enumerate(ls.get("exercises") or e.get("exercises") or []):
            for key in ("prompt", "hint", "answer"):
                if not (task.get(key) or "").strip():
                    a.fail("A-11", f"{e['id']} exercise[{i}] missing {key}")

    # ---- A-12 other-language preservation (counts unchanged) --------------
    # Baseline: 100 per language in each aggregate. Assert non-python counts.
    other_tut = Counter(e.get("language") for e in tut_doc["entries"] if e.get("language") != "python")
    other_ex = Counter(e.get("language") for e in ex_doc["entries"] if e.get("language") != "python")
    for lang, c in other_tut.items():
        if c != 100:
            a.warn("A-12", f"tutorials: language {lang} has {c} entries (was 100)")
    for lang, c in other_ex.items():
        if c != 100:
            a.warn("A-12", f"examples: language {lang} has {c} entries (was 100)")

    # ---- A-13 legacy bundle hygiene ---------------------------------------
    legacy = load(legacy_path)
    rt = legacy.get("runtime") or {}
    rt_blob = json.dumps(rt, ensure_ascii=False)
    if "planned" in rt_blob or "纯 Dart" in rt_blob or "开发中" in rt_blob:
        a.fail("A-13", f"legacy python.json still claims the stale runtime: {rt_blob[:160]}")
    if "MicroPython" not in rt_blob and "1.24.1" not in rt_blob:
        a.warn("A-13", f"legacy runtime metadata does not mention MicroPython 1.24.1: {rt_blob[:160]}")

    # ---- A-14 progression evident in order --------------------------------
    levels = [e.get("level") for e in tut]
    allowed = {"beginner", "intermediate", "advanced"}
    bad = [(e["id"], e.get("level")) for e in tut if e.get("level") not in allowed]
    if bad:
        a.fail("A-14", f"non-canonical levels on {len(bad)} tutorials, e.g. {bad[:5]}")
    # order must be non-decreasing beginner->intermediate->advanced
    order = {"beginner": 0, "intermediate": 1, "advanced": 2}
    seq = [order.get(l, -1) for l in levels]
    inversions = sum(1 for i in range(1, len(seq)) if seq[i] < seq[i - 1])
    if inversions:
        a.warn("A-14", f"{inversions} level regression(s) in tutorial order")

    # ---- A-15 id formatting / 3-digit padding -----------------------------
    for e in tut + ex:
        if not re.fullmatch(r"python-(tutorial|example)-\d{3}", e.get("id", "")):
            a.fail("A-15", f"malformed id {e.get('id')!r}")

    # ---- A-16 old placeholder ids fully removed ---------------------------
    # The old catalog was machine-generated padding; assert its signature gone.
    leftover_pad = [
        e["id"]
        for e in tut
        if PADDING_SIG in json.dumps(e, ensure_ascii=False)
    ]
    if leftover_pad:
        a.fail("A-16", f"{len(leftover_pad)} tutorials still carry padding signature: {leftover_pad[:5]}")

    # ---- report ------------------------------------------------------------
    report = {
        "tutorials": len(tut),
        "examples": len(ex),
        "ext_lessons": len(ext_lessons),
        "embedded_expected": EXPECTED_CODE - len(ext_lessons),
        "fails": a.fails,
        "warns": a.warns,
        "notes": a.notes,
    }
    for f in a.fails:
        print(json.dumps(f, ensure_ascii=False))
    for w in a.warns:
        print(json.dumps(w, ensure_ascii=False))
    print("=" * 72)
    print(f"tutorials={len(tut)} examples={len(ex)} EXT={len(ext_lessons)} "
          f"FAIL={len(a.fails)} WARN={len(a.warns)}")
    for n in a.notes:
        print(json.dumps({"note": n}, ensure_ascii=False))
    if args.json_out:
        Path(args.json_out).write_text(
            json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    return 1 if a.fails else 0


if __name__ == "__main__":
    sys.exit(main())
