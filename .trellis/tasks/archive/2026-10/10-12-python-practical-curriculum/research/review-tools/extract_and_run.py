#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Extract every PythonTopic from the authored Dart content files and re-run
each sample on the REAL embedded runtime (or CPython for EXT), independently.

Owned by the trellis-check reviewer. Reads *Dart source* directly so it can
audit partial/in-progress authoring before the JSON is emitted.

Usage:
    python extract_and_run.py --content <dir>            # report only
    python extract_and_run.py --content <dir> --json-out out.json
"""

from __future__ import annotations

import argparse
import ctypes
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

DLL_DEFAULT = Path(r"D:\MyNewProjects\qfli_python\native\build\windows\qfli_py_ffi.dll")
CONTENT_DEFAULT = Path(r"D:\MyNewProjects\qfli_studio_core\tool\python_content")
CPY_CANDIDATES = [r"D:\ProgramFiles\Python\Python313\python.exe"]
EXT_MARK = "需要外部 CPython 环境"


class Res(ctypes.Structure):
    _fields_ = [
        ("exit_code", ctypes.c_int),
        ("output", ctypes.c_char_p),
        ("error", ctypes.c_char_p),
        ("truncated", ctypes.c_int),
    ]


def dart_raw_string(block: str, key: str) -> str | None:
    """Return the string payload for `key:` in a PythonTopic block.

    Dart content mixes three literal styles and often concatenates adjacent
    literals across lines:
      key: r'''...'''
      key: r'a' r'b'
      key:\n  'a'\n  'b'
    Join every adjacent literal so multi-fragment blocks are reassembled.
    """
    # Find the extent of this key's value: from after `key:` until the next
    # top-level `,` that starts a sibling key (word + optional colon).
    m = re.search(rf"(?m)^[ \t]+{key}:\s*", block)
    if not m:
        m = re.search(rf"\b{key}:\s*", block)
    if not m:
        return None
    start = m.end()
    rest = block[start:]
    # Collect consecutive string literals (triple or single quoted, optional r).
    parts: list[str] = []
    i = 0
    while i < len(rest):
        # skip whitespace / newlines / commas between fragments
        ws = re.match(r"[\s,]*", rest[i:])
        i += ws.end()
        if i >= len(rest):
            break
        tm = re.match(r"(r?)'''(.*?)'''", rest[i:], re.S)
        if tm:
            raw = tm.group(1) == "r"
            parts.append(_decode(tm.group(2), raw))
            i += tm.end()
            continue
        tm = re.match(r'(r?)"""(.*?)"""', rest[i:], re.S)
        if tm:
            raw = tm.group(1) == "r"
            parts.append(_decode(tm.group(2), raw))
            i += tm.end()
            continue
        sm = re.match(r"(r?)'((?:[^'\\]|\\.)*)'", rest[i:], re.S)
        if sm:
            raw = sm.group(1) == "r"
            parts.append(_decode(sm.group(2), raw))
            i += sm.end()
            continue
        sm = re.match(r'(r?)"((?:[^"\\]|\\.)*)"', rest[i:], re.S)
        if sm:
            raw = sm.group(1) == "r"
            parts.append(_decode(sm.group(2), raw))
            i += sm.end()
            continue
        break
    if not parts:
        return None
    return "".join(parts)


def _decode(literal: str, raw: bool) -> str:
    """Decode Dart string escapes in a non-raw literal to its runtime value."""
    if raw:
        return literal
    out: list[str] = []
    i = 0
    simple = {"n": "\n", "t": "\t", "r": "\r", "'": "'", '"': '"',
              "\\": "\\", "$": "$", "0": "\0"}
    while i < len(literal):
        ch = literal[i]
        if ch == "\\" and i + 1 < len(literal):
            nxt = literal[i + 1]
            out.append(simple.get(nxt, nxt))
            i += 2
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def dart_string_list(block: str, key: str) -> list[str]:
    m = re.search(rf"\b{key}:\s*\[(.*?)\](?:,|\s*\n)", block, re.S)
    if not m:
        return []
    return re.findall(r"'((?:[^'\\]|\\.)*)'", m.group(1))


def split_topics(src: str) -> list[str]:
    """Split a content file into per-PythonTopic blocks.

    The authored files place each topic as `\n  PythonTopic(` at a fixed
    2-space indent. Splitting on that anchor is robust against parentheses or
    braces inside strings/comments (which break naive paren counting).
    """
    anchors = [m.start() for m in re.finditer(r"(?m)^  PythonTopic\(", src)]
    if not anchors:
        return []
    blocks = []
    for idx, a in enumerate(anchors):
        end = anchors[idx + 1] if idx + 1 < len(anchors) else len(src)
        blocks.append(src[a:end])
    return blocks


def parse_topic(block: str) -> dict | None:
    mid = re.search(r"\bid:\s*(\d+)", block)
    if not mid:
        return None
    code = dart_raw_string(block, "code")
    if code is None:
        return None
    out = {
        "id": int(mid.group(1)),
        "level": (re.search(r"\blevel:\s*'([^']*)'", block) or [None, ""])[1],
        "title": (re.search(r"\btitle:\s*'([^']*)'", block) or [None, ""])[1],
        "code": code,
        "output": dart_raw_string(block, "output") or "",
        "concepts": dart_string_list(block, "concepts"),
        "prerequisites": dart_string_list(block, "prerequisites"),
        "runtime_cpython": "PythonRuntime.cpython" in block,
        "explain": dart_raw_string(block, "explain") or "",
    }
    # explain often uses adjacent string literals; join them.
    ex = re.search(r"\bexplain:\s*((?:\s*r?'[^']*'\s*)+)", block, re.S)
    if ex:
        parts = re.findall(r"r?'([^']*)'", ex.group(1))
        out["explain"] = "".join(parts)
    tasks = re.findall(r"PythonTask\(\s*prompt:\s*'((?:[^'\\]|\\.)*)'.*?hint:\s*'((?:[^'\\]|\\.)*)'.*?answer:\s*'((?:[^'\\]|\\.)*)'", block, re.S)
    out["tasks"] = [
        {"prompt": _decode(p, False), "hint": _decode(h, False), "answer": _decode(a, False)}
        for p, h, a in tasks
    ]
    out["stdin"] = dart_raw_string(block, "input") or ""
    return out


def last_line(err: str) -> str:
    lines = (err or "").splitlines()
    return lines[-1][:200] if lines else ""


def norm(s: str) -> str:
    return (s or "").replace("\r\n", "\n").rstrip("\n")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--content", default=str(CONTENT_DEFAULT))
    ap.add_argument("--dll", default=str(DLL_DEFAULT))
    ap.add_argument("--json-out", default=None)
    args = ap.parse_args()

    content = Path(args.content)
    srcs = sorted(content.glob("*.dart"))
    topics: dict[int, dict] = {}
    for src in srcs:
        if src.name in ("python_topic.dart",):
            continue
        text = src.read_text(encoding="utf-8")
        for block in split_topics(text):
            t = parse_topic(block)
            if t and t["id"] not in topics:
                topics[t["id"]] = t
                t["file"] = src.name

    ids = sorted(topics)
    print(f"# parsed topics: {len(ids)} -> {ids}", file=sys.stderr)

    lib = ctypes.CDLL(str(Path(args.dll)))
    lib.qfli_py_version.restype = ctypes.c_char_p
    lib.qfli_py_run_into.argtypes = [
        ctypes.POINTER(Res), ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int,
        ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int,
    ]
    lib.qfli_py_result_free.argtypes = [ctypes.POINTER(Res)]
    version = lib.qfli_py_version().decode()
    cpy = next((c for c in CPY_CANDIDATES if Path(c).exists()), None)

    fails = []
    results = []
    with tempfile.TemporaryDirectory(prefix="qfli_review_") as proj:
        for tid in ids:
            t = topics[tid]
            code = t["code"].strip()
            want = norm(t["output"])
            ext = t["runtime_cpython"] or EXT_MARK in t["explain"]
            if ext:
                if cpy is None:
                    results.append({"id": tid, "env": "cpython", "status": "no-cpython"})
                    continue
                f = Path(proj) / f"m{tid}.py"
                f.write_text(code, encoding="utf-8")
                p = subprocess.run([cpy, str(f)], input=t.get("stdin", ""), capture_output=True,
                                   text=True, encoding="utf-8", timeout=30)
                ok = p.returncode == 0 and norm(p.stdout) == want
                results.append({"id": tid, "env": "cpython", "rc": p.returncode, "ok": ok})
                if not ok:
                    fails.append({"id": f"R-{tid:03d}", "severity": "FAIL", "env": "cpython",
                                  "file": t["file"], "title": t["title"],
                                  "want": want[:250], "got": norm(p.stdout)[:250],
                                  "err": last_line(p.stderr)})
            else:
                r = Res()
                lib.qfli_py_run_into(ctypes.byref(r), code.encode(), t.get("stdin", "").encode(), 8192,
                                     proj.encode(), str(Path(proj) / "main.py").encode(), 0)
                out = r.output.decode("utf-8", "replace") if r.output else ""
                err = r.error.decode("utf-8", "replace") if r.error else ""
                rc = r.exit_code
                lib.qfli_py_result_free(ctypes.byref(r))
                ok = rc == 0 and norm(out) == want
                results.append({"id": tid, "env": "embedded", "rc": rc, "ok": ok})
                if not ok:
                    fails.append({"id": f"R-{tid:03d}", "severity": "FAIL", "env": "embedded",
                                  "file": t["file"], "title": t["title"],
                                  "want": want[:250], "got": norm(out)[:250],
                                  "err": last_line(err)})

    print(f"# embedded runtime: {version}", file=sys.stderr)
    for f in fails:
        print(json.dumps(f, ensure_ascii=False))
    ok_n = sum(1 for r in results if r.get("ok"))
    print("=" * 72)
    print(f"parsed={len(ids)} ran={len(results)} pass={ok_n} fail={len(fails)}")
    if args.json_out:
        Path(args.json_out).write_text(json.dumps(
            {"version": version, "results": results, "fails": fails},
            ensure_ascii=False, indent=2), encoding="utf-8")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
