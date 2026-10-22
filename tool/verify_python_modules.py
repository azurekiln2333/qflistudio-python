#!/usr/bin/env python3
"""Verify asset digests and run portable bundle behaviors on the real VM ABI.

Use --explicit-path only with a legacy DLL without automatic bundle imports;
the report labels that mode. No host CPython module is substituted in the VM.
"""

import argparse
import base64
import csv
import ctypes
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import random
import shutil
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class Result(ctypes.Structure):
    _fields_ = [("exit_code", ctypes.c_int), ("output", ctypes.c_void_p),
                ("error", ctypes.c_void_p), ("truncated", ctypes.c_int)]


class Vm:
    def __init__(self, library):
        self.library = ctypes.CDLL(str(library))
        self.library.qfli_py_run_into.argtypes = [ctypes.POINTER(Result),
            ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int,
            ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
        self.library.qfli_py_run_into.restype = None
        self.library.qfli_py_result_free.argtypes = [ctypes.POINTER(Result)]
        self.library.qfli_py_result_free.restype = None
        self.library.qfli_py_version.argtypes = []
        self.library.qfli_py_version.restype = ctypes.c_char_p
        self.version = self.library.qfli_py_version().decode("utf-8")

    def run(self, source, project, entry, compile_only=False):
        result = Result()
        self.library.qfli_py_run_into(ctypes.byref(result), source.encode("utf-8"),
            b"", 8192, str(project).encode("utf-8"), str(entry).encode("utf-8"),
            int(compile_only))
        try:
            return {"exitCode": result.exit_code,
                "output": ctypes.string_at(result.output).decode("utf-8") if result.output else "",
                "error": ctypes.string_at(result.error).decode("utf-8") if result.error else None,
                "truncated": bool(result.truncated)}
        finally:
            self.library.qfli_py_result_free(ctypes.byref(result))


def verify_manifest(assets):
    manifest_path = assets / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("formatVersion") != 1 or manifest.get("bundleVersion") != "v1":
        raise ValueError("unsupported bundle schema/version")
    declared = {}
    for file in manifest["files"]:
        relative = PurePosixPath(file["path"])
        if relative.is_absolute() or ".." in relative.parts or "\\" in file["path"]:
            raise ValueError("unsafe asset path: " + file["path"])
        if file["path"] in declared:
            raise ValueError("duplicate asset: " + file["path"])
        path = assets.joinpath(*relative.parts)
        if path.is_symlink() or not path.is_file() or digest(path) != file["sha256"]:
            raise ValueError("missing or modified asset: " + str(path))
        declared[file["path"]] = file
    actual = {p.relative_to(assets).as_posix() for p in assets.rglob("*.py")}
    if actual != set(declared):
        raise ValueError("manifest does not list exactly all executable assets")
    module_names = set()
    covered = set()
    for module in manifest["modules"]:
        if module["name"] in module_names or not module["apis"]:
            raise ValueError("duplicate or undocumented module")
        module_names.add(module["name"])
        for key in ("version", "summary", "license", "source"):
            if not module[key]:
                raise ValueError("missing module metadata: " + key)
        for file in module["files"]:
            if declared.get(file["path"]) != file:
                raise ValueError("module file differs from global asset table")
            covered.add(file["path"])
    if covered != set(declared) or len(module_names) < 10:
        raise ValueError("at least ten modules must own every executable asset")
    return manifest


def differential_source():
    """Generate deterministic expected values with host reference stdlib.

    All assertions execute inside the embedded VM, including CSV multiline
    parsing. This checks a useful selected API range, not full compatibility.
    """
    rng = random.Random(421024)
    vectors = []
    for _ in range(128):
        raw = bytes(rng.randrange(256) for _ in range(rng.randrange(65)))
        vectors.append((raw, base64.b64encode(raw),
                        base64.urlsafe_b64encode(raw), base64.b16encode(raw)))
    rows = []
    for _ in range(256):
        data = [["".join(rng.choice('ab,;"\\\n\r ') for _ in range(rng.randrange(9)))
                 for _ in range(rng.randrange(5))] for _ in range(rng.randrange(1, 5))]
        options = {"delimiter": rng.choice([",", ";"]),
            "quoting": rng.choice([csv.QUOTE_MINIMAL, csv.QUOTE_ALL, csv.QUOTE_NONE]),
            "escapechar": "\\", "doublequote": rng.choice([True, False])}
        output = io.StringIO(newline="")
        try:
            csv.writer(output, **options).writerows(data)
        except csv.Error:
            rows.append((data, options, None))
        else:
            rows.append((data, options, output.getvalue()))
    return "import base64, csv, io\n" + \
        "for raw, normal, url, hexadecimal in " + repr(vectors) + ":\n" + \
        " assert base64.b64encode(raw) == normal\n" + \
        " assert base64.b64decode(normal) == raw\n" + \
        " assert base64.urlsafe_b64encode(raw) == url\n" + \
        " assert base64.urlsafe_b64decode(url) == raw\n" + \
        " assert base64.b16encode(raw) == hexadecimal\n" + \
        " assert base64.b16decode(hexadecimal) == raw\n" + \
        "for rows, options, expected in " + repr(rows) + ":\n" + \
        " output = io.StringIO()\n" + \
        " if expected is None:\n" + \
        "  try:\n" + \
        "   csv.writer(output, **options).writerows(rows)\n" + \
        "  except csv.Error:\n" + \
        "   pass\n" + \
        "  else:\n" + \
        "   raise AssertionError('CSV reference expected an error')\n" + \
        " else:\n" + \
        "  csv.writer(output, **options).writerows(rows)\n" + \
        "  assert output.getvalue() == expected\n" + \
        "  assert list(csv.reader(io.StringIO(expected), **options)) == rows\n" + \
        "print('QFLI_DIFFERENTIAL_PASS 128 encoding vectors; 256 CSV scenarios')\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", type=Path,
        default=ROOT / "native/build/windows/qfli_py_ffi.dll")
    parser.add_argument("--assets", type=Path, default=ROOT / "assets/python_stdlib")
    parser.add_argument("--suite", type=Path, default=ROOT / "native/tests/python_stdlib_smoke.py")
    parser.add_argument("--report", type=Path, default=ROOT / "build/reports/python-stdlib.json")
    parser.add_argument("--explicit-path", action="store_true")
    options = parser.parse_args()
    assets, library = options.assets.resolve(), options.library.resolve()
    manifest = verify_manifest(assets)
    vm = Vm(library)
    report = {"schemaVersion": 1, "runtimeVersion": vm.version,
        "library": str(library), "librarySha256": digest(library),
        "manifestSha256": digest(assets / "manifest.json"),
        "suiteSha256": digest(options.suite),
        "verifierSha256": digest(Path(__file__)),
        "importMode": "explicit-test-path" if options.explicit_path else "automatic-project-bundle",
        "deviceVerified": False, "modules": [], "compile": []}
    with tempfile.TemporaryDirectory(prefix="qfli-modules-\u4e2d\u6587-") as temporary:
        project = Path(temporary)
        entry = project / "src/main.py"
        entry.parent.mkdir()
        entry.write_text("# bundle behavior fixture\n", encoding="utf-8")
        for module in manifest["modules"]:
            result = vm.run("import " + module["name"], project, entry)
            report["modules"].append({"name": module["name"],
                "baselineMissing": result["exitCode"] != 0 and
                    "ImportError" in (result["error"] or ""), "baseline": result})
        bundled = project / ".qfli/python/bundled" / manifest["bundleVersion"]
        for file in manifest["files"]:
            target = bundled / file["path"]
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(assets / file["path"], target)
            compiled = vm.run(target.read_text(encoding="utf-8"), project, target, True)
            report["compile"].append({"path": file["path"], **compiled})
        prefix = ""
        if options.explicit_path:
            prefix = "import sys\nsys.path.append(" + repr(bundled.as_posix()) + ")\n"
        suite = options.suite.read_text(encoding="utf-8")
        behavior = vm.run(prefix + suite, project, entry)
        report["behavior"] = behavior
        report["passedAssertions"] = sum(line.startswith("PASS ") for line in behavior["output"].splitlines())
        report["missingBeforeBundle"] = sum(x["baselineMissing"] for x in report["modules"])
        report["success"] = (behavior["exitCode"] == 0 and not behavior["error"] and
            not behavior["truncated"] and "QFLI_STDLIB_PASS " in behavior["output"] and
            all(x["exitCode"] == 0 for x in report["compile"]))
        generated = differential_source()
        report["differentialSourceSha256"] = hashlib.sha256(generated.encode("utf-8")).hexdigest()
        differential = vm.run(prefix + generated, project, entry)
        report["differential"] = differential
        report["success"] = report["success"] and differential["exitCode"] == 0 and \
            "QFLI_DIFFERENTIAL_PASS " in differential["output"]
        # Prove the VM resets imports, including mutations to bundled modules.
        setup = vm.run(prefix + "import bisect\nbisect._qfli_leak = 42", project, entry)
        clean = vm.run(prefix + "import bisect\nassert not hasattr(bisect, '_qfli_leak')\nprint('fresh')", project, entry)
        report["freshVm"] = {"setup": setup, "next": clean}
        report["success"] = report["success"] and setup["exitCode"] == 0 and clean["output"] == "fresh\n"
        if not options.explicit_path:
            precedence = []
            candidates = [(entry.parent, "entry"), (project, "root"),
                          (project / "lib", "lib"), (bundled, "bundle")]
            for folder, origin in candidates:
                folder.mkdir(parents=True, exist_ok=True)
                (folder / "qfli_order_fixture.py").write_text("origin = " + repr(origin) + "\n", encoding="utf-8")
            for folder, origin in candidates:
                outcome = vm.run("import qfli_order_fixture\nprint(qfli_order_fixture.origin)", project, entry)
                precedence.append({"expected": origin, **outcome})
                report["success"] = report["success"] and outcome["exitCode"] == 0 and outcome["output"] == origin + "\n"
                (folder / "qfli_order_fixture.py").unlink()
            package = project / "lib/local_package"
            package.mkdir(parents=True)
            (package / "__init__.py").write_text("from .helper import value\n", encoding="utf-8")
            helper = package / "helper.py"
            package_runs = []
            for value in (41, 42):
                helper.write_text("value = " + str(value) + "\n", encoding="utf-8")
                outcome = vm.run("import local_package\nprint(local_package.value)", project, entry)
                package_runs.append({"expected": value, **outcome})
                report["success"] = report["success"] and outcome["exitCode"] == 0 and outcome["output"] == str(value) + "\n"
            other = project / "other_project"
            other.mkdir()
            isolated = vm.run("import bisect", other, other / "main.py")
            report["success"] = report["success"] and isolated["exitCode"] != 0 and "ImportError" in (isolated["error"] or "")
            report["automaticIntegration"] = {"precedence": precedence,
                "packageRefresh": package_runs, "projectIsolation": isolated}
    options.report.parent.mkdir(parents=True, exist_ok=True)
    options.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    print(f"MicroPython {vm.version}: {report['passedAssertions']} assertions; "
          f"{report['missingBeforeBundle']} previously missing modules; {report['importMode']}")
    print("Report:", options.report)
    if not report["success"]:
        print(report["behavior"]["error"] or report["differential"]["error"] or
              "bundle verification failed", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
