import json, ctypes, os, re, sys, tempfile
from pathlib import Path
sys.stdout.reconfigure(encoding="utf-8")
core = Path(r"D:\MyNewProjects\qfli_studio_core")
tut = json.loads((core / "assets/content/tutorials.json").read_text(encoding="utf-8"))
ex = json.loads((core / "assets/content/examples.json").read_text(encoding="utf-8"))
tp = {e["id"]: e for e in tut["entries"] if e.get("language") == "python"}
xp = {e["id"]: e for e in ex["entries"] if e.get("language") == "python"}

dll = os.path.abspath(r"D:\MyNewProjects\qfli_python\native\build\windows\qfli_py_ffi.dll")
lib = ctypes.CDLL(dll)
class R(ctypes.Structure):
    _fields_ = [("exit_code", ctypes.c_int), ("output", ctypes.c_char_p),
                ("error", ctypes.c_char_p), ("truncated", ctypes.c_int)]
lib.qfli_py_run_into.argtypes = [ctypes.POINTER(R), ctypes.c_char_p, ctypes.c_char_p,
                                 ctypes.c_int, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
lib.qfli_py_result_free.argtypes = [ctypes.POINTER(R)]
proj = tempfile.mkdtemp()

def run(src, stdin=""):
    # Fresh project dir per run: lessons that read/write project files (e.g.
    # todos.json) must be evaluated in an isolated project, as the real app does.
    proj = tempfile.mkdtemp(prefix="qfli_nd_")
    r = R()
    lib.qfli_py_run_into(ctypes.byref(r), src.encode(), stdin.encode(), 8192, proj.encode(),
                         os.path.join(proj, "m.py").encode(), 0)
    o = r.output.decode("utf-8", "replace") if r.output else ""
    e = r.error.decode("utf-8", "replace") if r.error else ""
    lib.qfli_py_result_free(ctypes.byref(r))
    return r.exit_code, o, e

# Heuristic: run every embedded sample 3x and report any whose stdout varies.
nondet = []
for n in range(1, 121):
    tid, eid = f"python-tutorial-{n:03d}", f"python-example-{n:03d}"
    t, x = tp.get(tid), xp.get(eid)
    if not t or not x:
        continue
    if t.get("level") and "需要外部 CPython 环境" in " ".join(t["lessons"][0].get("prerequisites") or []) + t["lessons"][0]["explain"]:
        continue
    stdin = (x.get("inputFixtures") or {}).get("stdin", "")
    for kind, code in (("lesson", t["lessons"][0]["code"]), ("example", x["code"])):
        outs = set()
        for _ in range(6):
            rc, o, e = run(code, stdin)
            outs.add((rc, o.rstrip("\n")))
        if len(outs) > 1:
            nondet.append((tid if kind == "lesson" else eid, kind, [o for _, o in outs]))

print("nondeterministic samples:", len(nondet))
for x in nondet:
    print(x[0], x[1], "=>", [repr(v.splitlines()[0] if v else "") for v in x[2]])
