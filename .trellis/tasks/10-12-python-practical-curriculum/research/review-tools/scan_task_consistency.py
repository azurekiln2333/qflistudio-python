"""Heuristic prompt<->answer consistency scanner for all Python topics.

Flags tasks where the answer looks unrelated to the prompt: the prompt names a
specific identifier/method (e.g. `discount_by_category`) that does not appear in
the answer, or vice-versa. This cannot replace human review; it surfaces
candidates (like the known 116 Cart task).
"""
import re, sys
from pathlib import Path
sys.path.insert(0, r"D:\MyNewProjects\qfli_python\.trellis\tasks\10-12-python-practical-curriculum\research\review-tools")
import extract_and_run as E
sys.stdout.reconfigure(encoding="utf-8")

STAGED = Path(r"D:\MyNewProjects\qfli_python\.trellis\tasks\10-12-python-practical-curriculum\research\advanced\python_topics_advanced.dart")
CORE = Path(r"D:\MyNewProjects\qfli_studio_core\tool\python_content")

topics = {}
for f in [STAGED] + sorted(CORE.glob("*.dart")):
    if not f.exists() or f.name == "python_topic.dart":
        continue
    for b in E.split_topics(f.read_text(encoding="utf-8")):
        t = E.parse_topic(b)
        if t and t["id"] not in topics:
            t["file"] = f.name
            topics[t["id"]] = t

print("topics:", len(topics), "->", sorted(topics))

ident = re.compile(r"[A-Za-z_][A-Za-z0-9_]{3,}")
flags = []
for tid in sorted(topics):
    t = topics[tid]
    for i, task in enumerate(t["tasks"]):
        prompt, hint, ans = task["prompt"], task["hint"], task["answer"]
        # identifiers the prompt explicitly requests
        p_ids = set(ident.findall(prompt)) - {"print", "self"}
        a_ids = set(ident.findall(ans))
        # ignore common words
        stop = {"self", "print", "return", "def", "class", "rate", "value", "list",
                "true", "false", "none", "str", "int", "float"}
        p_sig = {x for x in p_ids if x not in stop}
        # if prompt names a snake_case method/attr not present in answer -> candidate
        missing = {x for x in p_sig if ("_" in x or x[0].islower()) and x not in ans}
        # Only flag when prompt looks like it names an API (snake_case token)
        api_tokens = {x for x in p_sig if "_" in x}
        if api_tokens and not (api_tokens & a_ids):
            flags.append((tid, i, sorted(api_tokens), prompt[:50], ans.replace("\n", " ")[:70]))

print("\n=== candidates: prompt names an API token absent from answer ===")
for x in flags:
    print(x)
print(f"\nflags={len(flags)}")
