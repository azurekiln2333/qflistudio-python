import json, sys
from pathlib import Path
sys.stdout.reconfigure(encoding="utf-8")
core = Path(r"D:\MyNewProjects\qfli_studio_core")
tut = json.loads((core / "assets/content/tutorials.json").read_text(encoding="utf-8"))
ex = json.loads((core / "assets/content/examples.json").read_text(encoding="utf-8"))
tp = [e for e in tut["entries"] if e.get("language") == "python"]
xp = [e for e in ex["entries"] if e.get("language") == "python"]
print("py tut", len(tp), "py ex", len(xp))
t0 = tp[0]
print("tut[0] id:", t0["id"], "level:", t0.get("level"))
print("tut[0] lesson ids:", [l.get("id") for l in t0.get("lessons", [])])
print("tut[0] lesson keys:", sorted(t0.get("lessons", [{}])[0].keys()))
print("tut[0] top keys:", sorted(t0.keys()))
print("tut[0] exercises at top?", "exercises" in t0, "| in lesson?", "exercises" in t0["lessons"][0])
print("ex[0] id:", xp[0]["id"], "sourceLessonId:", xp[0].get("sourceLessonId"))
print("ex[0] keys:", sorted(xp[0].keys()))
# link check
lesson_ids = set()
for t in tp:
    for l in t.get("lessons", []):
        lesson_ids.add(l.get("id"))
print("distinct lesson ids:", len(lesson_ids), "sample:", sorted(lesson_ids)[:3])
bad = [(x["id"], x.get("sourceLessonId")) for x in xp if x.get("sourceLessonId") not in lesson_ids]
print("examples whose sourceLessonId is NOT a lesson id:", len(bad))
print("first few:", bad[:3])
