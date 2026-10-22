"""Read-only curriculum audit; all outputs and runtime work stay in research/."""
import ast
import collections
import ctypes
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import subprocess
import sys
import tempfile

sys.stdout.reconfigure(encoding="utf-8")
sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
APP = HERE.parents[3]
CORE = APP.parent / "qfli_studio_core"
WORK = HERE / "python-content-temp"
WORK.mkdir(exist_ok=True)
os.environ["TMP"] = os.environ["TEMP"] = str(WORK)
tempfile.tempdir = str(WORK)

def load(path):
    return json.loads(path.read_text(encoding="utf-8"))

def identity(path):
    return {"path": str(path), "bytes": path.stat().st_size,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}

def duplicates(items, key):
    values = collections.defaultdict(list)
    for item in items:
        values[key(item)].append(item["id"])
    return [ids for ids in values.values() if len(ids) > 1]

authored = load(HERE / "python-content-authored.json")
tutorial_path = CORE / "assets/content/tutorials.json"
example_path = CORE / "assets/content/examples.json"
legacy_path = CORE / "assets/tutorials/python.json"
tutorial_doc, example_doc, legacy = map(load, (tutorial_path, example_path, legacy_path))
tutorials = [e for e in tutorial_doc["entries"] if e["language"] == "python"]
examples = [e for e in example_doc["entries"] if e["language"] == "python"]
tmap = {e["id"]: e for e in tutorials}
emap = {e["id"]: e for e in examples}
legacy_lessons = {l["id"]: l for c in legacy["chapters"] for l in c["lessons"]}
mismatches = []
for topic in authored:
    t = tmap.get(topic["tutorialId"], {})
    e = emap.get(topic["exampleId"], {})
    lessons = t.get("lessons", [])
    l = lessons[0] if len(lessons) == 1 else {}
    old = legacy_lessons.get(topic["tutorialId"], {})
    for field in ("code", "output", "objective", "explain", "prerequisites", "pitfalls"):
        if l.get(field) != topic[field]:
            mismatches.append([topic["id"], "authored/tutorial", field])
    if e.get("code") != topic["code"] or e.get("expectedOutput") != topic["output"]:
        mismatches.append([topic["id"], "authored/example", "code/output"])
    if old.get("code") != topic["code"] or old.get("output") != topic["output"]:
        mismatches.append([topic["id"], "authored/legacy", "code/output"])
    if e.get("sourceLessonId") != topic["tutorialId"] + "-lesson":
        mismatches.append([topic["id"], "example", "sourceLessonId"])
    if e.get("inputFixtures", {}).get("stdin") != topic["input"] and (e.get("inputFixtures", {}).get("stdin") or topic["input"]):
        mismatches.append([topic["id"], "authored/example", "stdin"])
    if l.get("exercises") != topic["tasks"]:
        mismatches.append([topic["id"], "authored/tutorial", "exercises"])

dll = APP / "native/build/windows/qfli_py_ffi.dll"
helper_path = CORE / "tool/python_content/run_embedded.py"
helper = runpy.run_path(str(helper_path), run_name="qfli_research_helper")
lib = helper["load"](str(dll))
run = helper["run"]
Result = helper["QfliPyRunResult"]
native_results = []
tutorial_results = []
answer_results = []
with tempfile.TemporaryDirectory(prefix="main_", dir=WORK) as project:
    for e in examples:
        with tempfile.TemporaryDirectory(prefix=e["id"] + "_", dir=WORK) as snippet_project:
            code_exit, out, err = run(lib, snippet_project, e["code"], e.get("inputFixtures", {}).get("stdin", ""))
        expected = e.get("expectedOutput", "")
        native_results.append({"id": e["id"], "exitCode": code_exit, "output": out,
            "error": err, "exactOutput": out == expected,
            "normalizedOutput": out.replace("\r\n", "\n").rstrip() == expected.replace("\r\n", "\n").rstrip(),
            "declaredRuntime": "cpython" if "需要外部 CPython 环境" in e["concepts"] else "embedded"})
    # Tutorials have no input fixture in their shipped lesson schema. Execute
    # every raw lesson as exposed by the current tutorial import flow.
    for tutorial in tutorials:
        for lesson in tutorial["lessons"]:
            with tempfile.TemporaryDirectory(prefix=lesson["id"] + "_", dir=WORK) as snippet_project:
                code_exit, out, err = run(lib, snippet_project, lesson["code"], "")
            tutorial_results.append({"id": lesson["id"], "exitCode": code_exit,
                "output": out, "error": err, "exactOutput": out == lesson["output"]})
    for topic in authored:
        for index, task in enumerate(topic["tasks"], 1):
            code = task["answer"]
            result = Result()
            lib.qfli_py_run_into(ctypes.byref(result), code.encode(), b"", 8192,
                project.encode(), (str(Path(project) / "answer.py")).encode(), 1)
            try:
                answer_results.append({"topic": topic["id"], "exercise": index,
                    "prompt": task["prompt"], "answer": code,
                    "compileExit": result.exit_code,
                    "compileError": result.error.decode("utf-8", "replace") if result.error else ""})
            finally:
                lib.qfli_py_result_free(ctypes.byref(result))

cpython = []
for e in examples:
    if "需要外部 CPython 环境" not in e["concepts"]:
        continue
    proc = subprocess.run([sys.executable, "-c", e["code"]], capture_output=True,
        text=True, encoding="utf-8", timeout=15, cwd=WORK,
        env={**os.environ, "PYTHONIOENCODING": "utf-8"})
    cpython.append({"id": e["id"], "exitCode": proc.returncode,
        "output": proc.stdout, "error": proc.stderr,
        "exactOutput": proc.stdout == e["expectedOutput"],
        "normalizedOutput": proc.stdout.replace("\r\n", "\n").rstrip() == e["expectedOutput"].replace("\r\n", "\n").rstrip()})

imports = {}
for e in examples:
    names = []
    try:
        tree = ast.parse(e["code"])
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                names.extend(a.name for a in node.names)
            elif isinstance(node, ast.ImportFrom):
                names.append(node.module)
    except SyntaxError as exc:
        names.append("CPython AST: " + str(exc))
    imports[e["id"]] = sorted(set(names))

report = {
    "date": "2026-10-22", "scope": "Host DLL only; no OHOS execution claim",
    "assets": [identity(p) for p in (tutorial_path, example_path, legacy_path)],
    "nativeLibrary": identity(dll), "helper": identity(helper_path),
    "nativeVersion": lib.qfli_py_version().decode(), "cpythonVersion": sys.version,
    "tutorialCount": len(tutorials), "exampleCount": len(examples),
    "legacyLessonCount": len(legacy_lessons), "legacyExampleCount": len(legacy["examples"]),
    "aggregateTotalCounts": [len(tutorial_doc["entries"]), len(example_doc["entries"])],
    "languageCountsTutorials": dict(collections.Counter(e["language"] for e in tutorial_doc["entries"])),
    "languageCountsExamples": dict(collections.Counter(e["language"] for e in example_doc["entries"])),
    "authoredCount": len(authored), "declaredRuntimeCounts": dict(collections.Counter(t["runtime"] for t in authored)),
    "duplicateExampleIds": duplicates(examples, lambda e:e["id"]),
    "duplicateExampleTitles": duplicates(examples, lambda e:e["title"]),
    "duplicateExampleCode": duplicates(examples, lambda e:e["code"]),
    "placeholderMainIds": [e["id"] for e in examples if len(e["code"].strip().splitlines()) < 2 or "weighted=" in e["code"]],
    "authoredAssetMismatches": mismatches, "imports": imports,
    "nativeResults": native_results, "tutorialNativeResults": tutorial_results,
    "cpythonResults": cpython,
    "exerciseAnswerCount": len(answer_results),
    "exerciseAnswerCompilePassed": sum(r["compileExit"] == 0 for r in answer_results),
    "exerciseAnswerCompileResults": answer_results,
}
(HERE / "python-content-audit.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({k:v for k,v in report.items() if k not in ("nativeResults", "tutorialNativeResults", "cpythonResults", "exerciseAnswerCompileResults", "imports")}, ensure_ascii=False, indent=2))
print("Native failures:", [(r["id"], r["exitCode"], r["error"]) for r in native_results if r["exitCode"] != 0 or not r["normalizedOutput"]])
print("CPython:", [(r["id"], r["exitCode"], r["normalizedOutput"]) for r in cpython])
print("Tutorial raw failures:", [(r["id"], r["exitCode"], r["error"]) for r in tutorial_results if r["exitCode"] != 0 or not r["exactOutput"]])
print("Exercise compile failures:", [(r["topic"], r["exercise"]) for r in answer_results if r["compileExit"] != 0])
