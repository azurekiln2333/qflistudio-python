import json, re, collections, sys

CORE = r"D:/MyNewProjects/qfli_studio_core"
tut = json.load(open(CORE + "/assets/content/tutorials.json", encoding="utf-8"))["entries"]
exa = json.load(open(CORE + "/assets/content/examples.json", encoding="utf-8"))["entries"]

tut_py = [e for e in tut if e["language"] == "python"]
exa_py = [e for e in exa if e["language"] == "python"]

print("=== COUNTS ===")
print("tutorials python:", len(tut_py), " examples python:", len(exa_py))

# --- ids ---
tids = [e["id"] for e in tut_py]
eids = [e["id"] for e in exa_py]
print("unique tutorial ids:", len(set(tids)), "unique example ids:", len(set(eids)))

# placeholder keyword scan
PLACEHOLDER = [
    "TODO", "FIXME", "XXX", "placeholder", "占位", "待补充", "待完善", "敬请期待",
    "coming soon", "lorem ipsum", "示例代码", "example code here", "pass  # ", "TBD",
    "此处填写", "略", "省略", "..."]

# quick placeholder scan on titles/summaries/code
def scan(field, rows, key):
    hits = []
    for r in rows:
        v = r.get(key) or ""
        for p in ["TODO", "FIXME", "占位", "待补充", "待完善", "敬请期待", "lorem", "TBD", "此处填写"]:
            if p.lower() in v.lower():
                hits.append((r["id"], p, v[:80]))
    return hits

print("=== PLACEHOLDER SCAN (title/summary) ===")
for f, rows in (("tutorial", tut_py), ("example", exa_py)):
    h = scan(f, rows, "title") + scan(f, rows, "summary")
    print(f, "hits:", len(h))
    for x in h[:20]: print("   ", x)

print("=== CODE PLACEHOLDER SCAN ===")
codehits = []
for r in tut_py:
    lessons = r.get("lessons") or []
    for ls in lessons:
        c = ls.get("code") or ""
        for p in ["TODO", "FIXME", "占位", "待补充", "lorem", "TBD", "此处填写"]:
            if p.lower() in c.lower():
                codehits.append((ls.get("id"), p))
for r in exa_py:
    c = r.get("code") or ""
    for p in ["TODO", "FIXME", "占位", "待补充", "lorem", "TBD", "此处填写"]:
        if p.lower() in c.lower():
            codehits.append((r["id"], p))
print("code placeholder hits:", len(codehits), codehits[:20])

# --- empty content checks ---
empty_titles = [r["id"] for r in tut_py if not (r.get("title") or "").strip()]
print("=== EMPTY TITLES ===", len(empty_titles), empty_titles[:20])

# duplicates by title
tdup = [k for k,v in collections.Counter(r.get("title") for r in tut_py).items() if v>1]
edup = [k for k,v in collections.Counter(r.get("title") for r in exa_py).items() if v>1]
print("=== DUPLICATE TITLES ===")
print("tutorial dup titles:", len(tdup), tdup[:10])
print("example dup titles:", len(edup), edup[:10])

# duplicate code
codes_t = collections.Counter()
for r in tut_py:
    for ls in (r.get("lessons") or []):
        codes_t[(ls.get("code") or "").strip()] += 1
codes_e = collections.Counter((r.get("code") or "").strip() for r in exa_py)
print("=== DUPLICATE CODE ===")
print("dup tutorial lesson codes:", sum(1 for v in codes_t.values() if v>1))
print("dup example codes:", sum(1 for v in codes_e.values() if v>1))
cringe = [c[:40] for c,v in codes_t.items() if v>1][:5]
print("  samples:", cringe)

# --- 1:1 pairing ---
print("=== 1:1 PAIRING ===")
tidset = set(tids)
missing = []
bad_link = []
for e in exa_py:
    sl = e.get("sourceLessonId")
    if not sl:
        missing.append(e["id"]); continue
    # sourceLessonId like python-tutorial-NNN-lesson
    base = sl[:-len("-lesson")] if sl.endswith("-lesson") else sl
    if base not in tidset:
        bad_link.append((e["id"], sl))
print("examples missing sourceLessonId:", len(missing), missing[:10])
print("examples with dangling sourceLessonId:", len(bad_link), bad_link[:10])

# each tutorial has >=1 lesson
none_lessons = [r["id"] for r in tut_py if not (r.get("lessons") or [])]
print("tutorials with no lessons:", len(none_lessons), none_lessons[:10])

# --- runtime distribution ---
runtimes = collections.Counter()
for e in exa_py:
    meta = e.get("runtime") or {}
    runtimes[str(meta.get("kind") or meta.get("status") or e.get("runtimeKind"))] += 1
print("=== RUNTIME ===", runtimes)

# --- levels / progressive ordering ---
lvl = collections.Counter(str(e.get("level")) for e in tut_py)
print("=== LEVELS ===", lvl)

# order by index
print("=== ORDER SAMPLE ===")
for e in tut_py[:5]: print("  ", e["id"], e.get("level"), e.get("title"))
print("  ...")
for e in tut_py[-5:]: print("  ", e["id"], e.get("level"), e.get("title"))

# CONCEPT labels for CPython
cp = [e["id"] for e in exa_py if "cpython" in json.dumps(e, ensure_ascii=False).lower()]
print("=== CPYTHON-MENTIONING EXAMPLES ===", len(cp), cp[:10])
