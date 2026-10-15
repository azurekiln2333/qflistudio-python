#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Independent re-execution of every Python sample on the REAL embedded runtime.

Owned by the independent trellis-check reviewer. It does NOT use the
implementation's Dart verifier and does NOT trust
`research/python-content-verification.json`. It:

  1. Reads the emitted aggregate catalog (tutorials.json + examples.json).
  2. Re-runs every EMBEDDED lesson `code` and example `code` against the real
     bundled MicroPython DLL (ctypes -> qfli_py_run_into).
  3. Diffs stdout against the declared `output` / `expectedOutput`.
  4. For EXT (CPython-only) lessons, re-runs them in the local CPython and
     checks the declared output there, and asserts they are NOT counted as
     embedded.
  5. Emits a machine-readable per-id report + a human summary.

Runtime ABI (see .trellis/spec/backend/native-python-runtime.md):

    qfli_py_run_into(Res*, source, stdin, heap_kb, project_dir, entry_file,
                     compile_only)
    qfli_py_result_free(Res*)

    Res = {int exit_code; char* output; char* error; int truncated}

Usage:
    python .../review-tools/verify_runtime.py
    python .../review-tools/verify_runtime.py --dll <path> --json-out out.json
"""

from __future__ import annotations

import argparse
import ctypes
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

CORE_DEFAULT = Path(r"D:\MyNewProjects\qfli_studio_core")
DLL_DEFAULT = Path(r"D:\MyNewProjects\qfli_python\native\build\windows\qfli_py_ffi.dll")
CPY_CANDIDATES = [
    r"D:\ProgramFiles\Python\Python313\python.exe",
    sys.executable,
]

EXT_MARK = "需要外部 CPython 环境"


class Res(ctypes.Structure):
    _fields_ = [
        ("exit_code", ctypes.c_int),
        ("output", ctypes.c_char_p),
        ("error", ctypes.c_char_p),
        ("truncated", ctypes.c_int),
    ]


class Embedded:
    """Thin, self-contained driver for the real qfli_py FFI DLL."""

    def __init__(self, dll: Path) -> None:
        self.lib = ctypes.CDLL(str(dll))
        self.lib.qfli_py_run_into.argtypes = [
            ctypes.POINTER(Res),
            ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int,
            ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int,
        ]
        self.lib.qfli_py_result_free.argtypes = [ctypes.POINTER(Res)]
        if hasattr(self.lib, "qfli_py_version"):
            self.lib.qfli_py_version.restype = ctypes.c_char_p
            self.version = self.lib.qfli_py_version().decode("utf-8", "replace")
        else:
            self.version = "unknown"

    def run(self, source: str, stdin: str = "", project: str | None = None):
        # Default to a fresh project dir per run so lessons that read/write
        # project files (e.g. todos.json, notes.txt) are isolated, exactly as
        # the real app runs them.
        proj = project or tempfile.mkdtemp(prefix="qfli_audit_")
        entry = os.path.join(proj, "main.py")
        r = Res()
        self.lib.qfli_py_run_into(
            ctypes.byref(r),
            source.encode("utf-8"),
            stdin.encode("utf-8"),
            8192,
            proj.encode("utf-8"),
            entry.encode("utf-8"),
            0,
        )
        out = r.output.decode("utf-8", "replace") if r.output else ""
        err = r.error.decode("utf-8", "replace") if r.error else ""
        code, trunc = r.exit_code, bool(r.truncated)
        self.lib.qfli_py_result_free(ctypes.byref(r))
        return code, out, err, trunc


def norm(text: str) -> str:
    return (text or "").replace("\r\n", "\n").rstrip("\n")


def find_cpython() -> str | None:
    for c in CPY_CANDIDATES:
        if c and Path(c).exists():
            return c
    return None


def run_cpython(exe: str, source: str, stdin_text: str):
    with tempfile.TemporaryDirectory() as d:
        f = Path(d) / "main.py"
        f.write_text(source, encoding="utf-8")
        try:
            p = subprocess.run(
                [exe, str(f)],
                input=stdin_text or "",
                capture_output=True,
                text=True,
                encoding="utf-8",
                timeout=30,
            )
        except subprocess.TimeoutExpired:
            return 124, "", "timeout"
    return p.returncode, p.stdout, p.stderr


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--core", default=str(CORE_DEFAULT))
    ap.add_argument("--dll", default=str(DLL_DEFAULT))
    ap.add_argument("--json-out", default=None)
    ap.add_argument("--only", default=None, help="comma ids e.g. 001,002")
    args = ap.parse_args()

    core = Path(args.core)
    dll = Path(args.dll)
    if not dll.exists():
        print(json.dumps({"id": "B-00", "severity": "BLOCKER",
                          "msg": f"embedded DLL not found: {dll}"}, ensure_ascii=False))
        return 2

    tut_doc = json.loads((core / "assets/content/tutorials.json").read_text(encoding="utf-8"))
    ex_doc = json.loads((core / "assets/content/examples.json").read_text(encoding="utf-8"))
    tut = {e["id"]: e for e in tut_doc["entries"] if e.get("language") == "python"}
    ex = {e["id"]: e for e in ex_doc["entries"] if e.get("language") == "python"}

    emb = Embedded(dll)
    cpy = find_cpython()
    only = set(args.only.split(",")) if args.only else None

    results = []
    fails = []
    embedded_pass = 0
    embedded_total = 0
    cpy_pass = 0
    cpy_total = 0

    for n in range(1, 121):
        tid, eid = f"python-tutorial-{n:03d}", f"python-example-{n:03d}"
        if only and f"{n:03d}" not in only:
            continue
        t, e = tut.get(tid), ex.get(eid)
        if not t or not e:
            continue
        lesson = (t.get("lessons") or [{}])[0]
        blob = " ".join(str(x) for x in (
            lesson.get("explain", ""),
            " ".join(lesson.get("concepts") or []),
            " ".join(t.get("prerequisites") or []),
        ))
        is_ext = EXT_MARK in blob

        # Prefer the example's declared input fixture if present.
        stdin_text = ""
        fx = e.get("inputFixtures") or {}
        if isinstance(fx, dict) and isinstance(fx.get("stdin"), str):
            stdin_text = fx["stdin"]

        lcode = (lesson.get("code") or "").strip()
        lout = norm(lesson.get("output") or "")
        ecode = (e.get("code") or "").strip()
        eout = norm(e.get("expectedOutput") or "")

        for kind, code, want in (("lesson", lcode, lout), ("example", ecode, eout)):
            if not code:
                fails.append({"id": "B-01", "severity": "FAIL",
                              "loc": f"{tid if kind=='lesson' else eid}/{kind}",
                              "msg": "empty code"})
                continue
            if is_ext:
                cpy_total += 1
                if cpy is None:
                    results.append({"id": eid, "kind": kind, "env": "cpython",
                                    "status": "skipped-no-cpython"})
                    continue
                rc, out, err = run_cpython(cpy, code, stdin_text)
                ok = (rc == 0) and (norm(out) == want)
                if ok:
                    cpy_pass += 1
                else:
                    fails.append({
                        "id": "B-02", "severity": "FAIL",
                        "loc": f"{tid if kind=='lesson' else eid}/{kind}",
                        "msg": f"CPython run mismatch rc={rc}",
                        "want": want[:300], "got": norm(out)[:300],
                        "err": (err or "").splitlines()[-1][:200] if err else "",
                    })
                results.append({"id": eid, "kind": kind, "env": "cpython",
                                "rc": rc, "ok": ok})
            else:
                embedded_total += 1
                rc, out, err, trunc = emb.run(code, stdin_text)
                ok = (rc == 0) and (norm(out) == want)
                if ok:
                    embedded_pass += 1
                else:
                    fails.append({
                        "id": "B-03", "severity": "FAIL",
                        "loc": f"{tid if kind=='lesson' else eid}/{kind}",
                        "msg": f"embedded run mismatch rc={rc} truncated={trunc}",
                        "want": want[:300], "got": norm(out)[:300],
                        "err": (err or "").splitlines()[-1][:200] if err else "",
                    })
                results.append({"id": eid, "kind": kind, "env": "embedded",
                                "rc": rc, "ok": ok, "version": emb.version})

    # Honesty gate: if the implementation claims 116 embedded but fewer pass,
    # that is a hard fail.
    summary = {
        "embedded_version": emb.version,
        "embedded_pass": embedded_pass,
        "embedded_total": embedded_total,
        "cpython_pass": cpy_pass,
        "cpython_total": cpy_total,
        "fails": len(fails),
    }
    for f in fails:
        print(json.dumps(f, ensure_ascii=False))
    print("=" * 72)
    print(json.dumps(summary, ensure_ascii=False))
    if args.json_out:
        Path(args.json_out).write_text(
            json.dumps({"summary": summary, "results": results, "fails": fails},
                       ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
