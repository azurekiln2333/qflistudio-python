#!/usr/bin/env python3
"""Measure ordinary execution with tracing compiled on but no callback active.

Both libraries execute the same source through their unchanged legacy run ABI.
These host measurements are descriptive and do not assert performance identity.
"""

import argparse
import hashlib
import json
from pathlib import Path
import statistics
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tool"))
from verify_python_modules import Vm

CALLS = """def leaf(x):
    return (x*3+1)%997
def parent(x):
    return leaf(x)+leaf(x+1)
def drive():
    total=0
    for n in range(15000):
        total+=parent(n)
    return total
print(drive())
"""
ALLOCATIONS = """import gc
def leaf(x):
    return x+1
def parent(x):
    return leaf(x)
gc.collect()
gc.disable()
before=gc.mem_alloc()
for i in range(2000):
    parent(i)
after=gc.mem_alloc()
gc.enable()
print(before,after-before)
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("current", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    options = parser.parse_args()
    paths = {"baseline": options.baseline.resolve(), "current": options.current.resolve()}
    vms = {name: Vm(path) for name, path in paths.items()}
    timings = {name: [] for name in paths}
    outcomes = {}
    with tempfile.TemporaryDirectory(prefix="qfli-debug-cost-") as directory:
        root = Path(directory)
        entry = root / "main.py"
        for iteration in range(11):
            for name, vm in vms.items():
                started = time.perf_counter()
                outcome = vm.run(CALLS, root, entry)
                elapsed = time.perf_counter() - started
                assert outcome["exitCode"] == 0 and outcome["error"] is None, outcome
                outcomes[name] = outcome
                if iteration >= 2:
                    timings[name].append(elapsed)
        assert outcomes["baseline"] == outcomes["current"], outcomes
        allocations = {name: vm.run(ALLOCATIONS, root, entry) for name, vm in vms.items()}
        for outcome in allocations.values():
            assert outcome["exitCode"] == 0 and outcome["error"] is None, outcome
            assert int(outcome["output"].split()[1]) < 1024, outcome
    report = {
        "schema": 1, "kind": "real-native-ordinary-run-cost", "device": False,
        "workloadSha256": hashlib.sha256(CALLS.encode()).hexdigest(),
        "allocationWorkloadSha256": hashlib.sha256(ALLOCATIONS.encode()).hexdigest(),
        "samplesPerLibrary": 9, "warmupsPerLibrary": 2,
        "libraries": {},
    }
    for name, path in paths.items():
        report["libraries"][name] = {
            "path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "bytes": path.stat().st_size, "version": vms[name].version,
            "elapsedSeconds": timings[name], "medianSeconds": statistics.median(timings[name]),
            "output": outcomes[name]["output"], "allocations": allocations[name],
        }
    report["currentToBaselineMedianRatio"] = statistics.median(timings["current"]) / statistics.median(timings["baseline"])
    report["notes"] = (
        "No debug session or trace callback is active. Both libraries preserve output. "
        "Compiler/raw-code/frame fields and VM branches remain; no zero-cost or device performance claim. "
        "Allocation output gives initial retained VM bytes followed by incremental bytes across 4000 nested calls."
    )
    options.report.parent.mkdir(parents=True, exist_ok=True)
    options.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"medianRatio": report["currentToBaselineMedianRatio"],
                      "allocations": {name: outcome["output"].strip() for name, outcome in allocations.items()},
                      "bytes": {name: path.stat().st_size for name, path in paths.items()}}))


if __name__ == "__main__":
    main()
