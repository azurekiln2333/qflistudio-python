"""Bounded Python host window; execute only under a NEW named grant.

Wraps the reviewer-owned focused Dart/analysis checks in the shared Windows
owned-process helper (`tool/python_owned_process.py`). Import starts no process,
writes no file and calls no Windows API.

Plan: at most 180 seconds. In-run controls always run first; a supplied
`--controls-report` must match the same grant and be a real (non-synthetic)
PASS. Then one merged `flutter test --no-pub --concurrency=1` call runs the four
focused debugger / native / audit / content suites (plus the named-workspace
suite when requested, plus the two consumer suites when
`--include-consumer-tests` is requested), followed by the owned-scope
`dart analyze`.

Every phase is one `run_owned` command: it returns only after the exact root is
terminal, the private Job is empty and its handles are closed. If cleanup cannot
be confirmed, `run_owned` stays in HOLD_UNRELEASED and retains the exact handles;
this wrapper never starts a later phase in that state.

Source binding is not limited to the audit tool. The wrapper hashes every
executed focused suite (and the named-workspace and consumer suites when
requested), the owned
tool/test files, and the frozen native binaries it depends on before and after
the run. The default DLL is always bound because the audit and default backend
load it; `QFLI_PY_DEBUG_TEST_LIBRARY` and `QFLI_PYTHON_TEST_LIBRARY` add their
actual paths. Every bound library path must exist; a missing binary refuses the
run before any command is composed instead of letting a Dart skip turn green.
Bound libraries are frozen prebuilt binaries. This run never builds, refreshes
or claims them as products of the current native sources.

Evidence must live under `<root>/build`. `--grant` and `--next-owner` are
mandatory. `--control-only` runs only the real owned-process controls under a
short plan. No runtime, HAP, device or signing result is claimed here.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import sys
import time
from datetime import datetime, timezone

FOCUSED_SUITES = (
    "test/python_debugger_test.dart",
    "test/python_debugger_native_test.dart",
    "test/python_debugger_audit_test.dart",
    "test/python_content_audit_test.dart",
)
NAMED_WORKSPACE_SUITE = "test/python_named_workspace_test.dart"
# Consumer-facing suites. Additive only, and bound through the same
# suite-identity mechanism as the focused and named-workspace suites.
# `--include-consumer-tests` can only add these two exact files to the one
# merged call; there is no arbitrary suite or command injection here.
CONSUMER_SUITES = (
    "test/python_tools_page_test.dart",
    "test/python_highlighting_test.dart",
)
DEFAULT_SCOPE = (
    "tool/python_debugger_ohos_audit.dart",
    "test/python_debugger_audit_test.dart",
)
OWNED_IDENTITIES = (
    "tool/python_owned_process.py",
    "tool/python_debugger_ohos_audit.dart",
    "test/python_debugger_audit_test.dart",
    "test/python_owned_process_control_test.py",
    ".trellis/tasks/10-22-python-offline-debugger/research/fixtures/run_python_host.py",
    ".trellis/tasks/10-22-python-offline-debugger/research/fixtures/verify_run_python_host.py",
)
# Frozen prebuilt native binaries. This run binds them, it does not build them.
DEFAULT_LIBRARY = "native/build/windows/qfli_py_ffi.dll"
LIBRARY_ENV_OVERRIDES = (
    ("QFLI_PY_DEBUG_TEST_LIBRARY", "debug-override"),
    ("QFLI_PYTHON_TEST_LIBRARY", "python-override"),
)
LIBRARY_CHAIN_NOTE = (
    "Frozen prebuilt binary bound by this run; not built, refreshed or owned by "
    "the current native sources."
)


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def atomic_report(path: Path, value: dict) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n",
                         encoding="utf-8")
    os.replace(temporary, path)


def changed(before: dict, after: dict) -> list[str]:
    return sorted(name for name in before.keys() | after.keys()
                  if before.get(name) != after.get(name))


def input_summary(product: dict, shared: dict) -> dict:
    return {"product": product, "shared": shared,
            "productCount": len(product), "sharedCount": len(shared)}


def digest(path: Path) -> dict:
    data = path.read_bytes()
    return {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def identities(root: Path, relative: tuple[str, ...]) -> dict:
    result = {}
    for name in relative:
        path = (root / name).resolve(strict=True)
        result[name] = digest(path)
    return result


def _load_module(root: Path, relative: str, name: str, attribute: str):
    path = (root / relative).resolve(strict=True)
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    previous_path, previous_bytecode = sys.path[:], sys.dont_write_bytecode
    try:
        sys.path.insert(0, str(path.parent))
        sys.dont_write_bytecode = True
        spec.loader.exec_module(module)
    finally:
        sys.path[:] = previous_path
        sys.dont_write_bytecode = previous_bytecode
    if not hasattr(module, attribute):
        raise RuntimeError(f"{relative} does not expose {attribute}")
    return module


def load_owned_helper(root: Path):
    """Import the shared helper without running its CLI or any control."""
    return _load_module(root, "tool/python_owned_process.py",
                        "_qfli_python_owned_process", "run_owned")


def load_audit_inputs(root: Path):
    """Import the shared audit-input collector without running a build."""
    return _load_module(root, "tool/python_audit_inputs.py",
                        "_qfli_python_audit_inputs", "collect_inputs")


def suite_relative(args) -> tuple[str, ...]:
    """The bound suite set: focused, then named, then the additive consumers."""
    suites = list(FOCUSED_SUITES)
    if args.include_named_workspace:
        suites.append(NAMED_WORKSPACE_SUITE)
    if args.include_consumer_tests:
        suites.extend(CONSUMER_SUITES)
    return tuple(suites)


def owned_identities(root: Path) -> dict:
    return identities(root, OWNED_IDENTITIES)


def suite_identities(root: Path, args) -> dict:
    return identities(root, suite_relative(args))


def bound_library_paths(root: Path) -> list[dict]:
    """Resolve every bound binary; a missing or non-file path refuses the run.

    The default DLL is always bound because the audit suite and the default
    backend load it. Each environment override adds its actual path. Nothing is
    built here; the paths must already exist as frozen binaries.
    """
    entries = [{"role": "default", "envVar": None,
                "requested": str(root / DEFAULT_LIBRARY)}]
    for env_name, role in LIBRARY_ENV_OVERRIDES:
        raw = os.environ.get(env_name)
        if raw:
            requested = Path(raw)
            if not requested.is_absolute():
                requested = root / requested
            entries.append({"role": role, "envVar": env_name,
                            "requested": str(requested)})
    resolved = []
    for entry in entries:
        try:
            path = Path(entry["requested"]).resolve(strict=True)
        except FileNotFoundError:
            raise ValueError(
                f"Bound {entry['role']} library must exist: {entry['requested']}")
        if not path.is_file():
            raise ValueError(
                f"Bound {entry['role']} library is not a file: {path}")
        resolved.append({"role": entry["role"], "envVar": entry["envVar"],
                         "path": str(path)})
    return resolved


def bind_libraries(root: Path) -> dict:
    """Absolute path + SHA256 for every bound frozen binary, before and after."""
    result = {}
    for entry in bound_library_paths(root):
        result[entry["envVar"] or "default"] = {
            "role": entry["role"],
            "path": entry["path"],
            "note": LIBRARY_CHAIN_NOTE,
            **digest(Path(entry["path"])),
        }
    return result


def run_phase(helper, args, root: Path, output: Path, name: str,
              command: list[str], timeout_seconds: float) -> dict:
    phase = {"name": name, "command": command, "startedAt": now(),
             "timeoutSeconds": round(timeout_seconds, 3)}
    log = output / f"{name}.combined.log"
    report_path = output / f"{name}.report.json"
    try:
        report = helper.run_owned(
            command,
            timeout_seconds=timeout_seconds,
            cleanup_seconds=args.cleanup_seconds,
            cwd=root,
            log_path=log,
            report_path=report_path,
        )
        phase["runOwnedReport"] = str(report_path)
        phase["state"] = report.get("state")
        phase["release"] = report.get("release")
        phase["cleanupConfirmed"] = report.get("cleanupConfirmed")
        phase["timedOut"] = report.get("timedOut")
        phase["exitCode"] = report.get("exitCode")
        phase["result"] = report.get("result")
        process = report.get("process") or {}
        phase["rootExit"] = process.get("exitCode")
        phase["rootTerminal"] = process.get("terminal")
        phase["jobActiveProcesses"] = process.get("jobActiveProcesses")
        phase["handlesClosed"] = process.get("handlesClosed")
        phase["handlesRetained"] = report.get("handlesRetained")
    except BaseException as error:
        phase["error"] = f"{type(error).__name__}: {error}"
        phase["release"] = "HOLD_UNRELEASED"
        phase["cleanupConfirmed"] = False
    phase["finishedAt"] = now()
    confirmed = (phase.get("cleanupConfirmed") is True and
                 phase.get("release") == "RELEASE" and
                 phase.get("state") == "FINISHED" and
                 phase.get("handlesRetained") is False and
                 phase.get("rootTerminal") is True and
                 phase.get("jobActiveProcesses") == 0 and
                 phase.get("handlesClosed") is True)
    phase["confirmed"] = confirmed
    phase["passed"] = bool(confirmed and phase.get("exitCode") == 0)
    return phase


def run_controls(helper, args, root: Path, output: Path, started: float) -> dict:
    phase = run_phase(
        helper, args, root, output, "owned-process-controls",
        [args.python, "test/python_owned_process_control_test.py",
         "--grant", args.grant.strip(), "--output", str(output / "controls")],
        min(args.control_seconds, args.work_seconds),
    )
    phase["elapsedSeconds"] = round(time.monotonic() - started, 3)
    return phase


def focused_command(args) -> list[str]:
    """One merged call over the bound suite set, in suite_relative order."""
    return [args.flutter, "test", "--no-pub", "--concurrency=1",
            *suite_relative(args)]


def scope_command(args) -> list[str]:
    return [args.dart, "analyze", *[str(item) for item in args.scope]]


def run(args) -> int:
    started = time.monotonic()
    root = args.root.resolve(strict=True)
    output = args.output.resolve()
    if not output.is_relative_to(root / "build"):
        raise ValueError("Evidence output must live under <root>/build")
    # Bind frozen binaries and source identities before any evidence or command.
    # A missing DLL or suite refuses the run instead of relying on a Dart skip.
    libraries_before = bind_libraries(root)
    owned_before = owned_identities(root)
    suites_before = suite_identities(root, args)
    output.mkdir(parents=True, exist_ok=False)
    helper = load_owned_helper(root)
    report = {
        "schemaVersion": 1, "mode": "CONTROL_ONLY" if args.control_only else "HOST",
        "grant": args.grant.strip(), "nextOwner": args.next_owner.strip(),
        "outerToolHandle": args.outer_handle, "wrapperPid": os.getpid(),
        "root": str(root), "planSeconds": args.plan_seconds,
        "workSeconds": args.work_seconds, "cleanupSeconds": args.cleanup_seconds,
        "startedAt": now(), "phases": [], "errors": [],
        "scope": [str(item) for item in args.scope],
        "runner": "tool/python_owned_process.py run_owned per phase",
        "focusedCommand": "one merged flutter test --no-pub --concurrency=1",
        "boundSuites": list(suite_relative(args)),
        "boundConsumers": (list(CONSUMER_SUITES)
                            if args.include_consumer_tests else []),
        "boundLibraries": list(libraries_before.keys()),
        "libraryChainNote": LIBRARY_CHAIN_NOTE,
        "publication": {"state": "NOT_ATTEMPTED",
                        "reason": "Parent polls/publishes this exact evidence"},
        "claims": "Focused host checks only; no native build, HAP, signing, WSL or device gate",
    }
    audit_inputs = None
    product_before = shared_before = None
    try:
        report["ownedIdentitiesBefore"] = owned_before
        report["suiteIdentitiesBefore"] = suites_before
        report["libraryIdentitiesBefore"] = libraries_before
        try:
            audit_inputs = load_audit_inputs(root)
            core = (root.parent / "qfli_studio_core").resolve(strict=True)
            product_before, shared_before = audit_inputs.collect_inputs(root, core)
            report["auditInputsBefore"] = input_summary(product_before, shared_before)
        except BaseException as error:
            report["errors"].append(
                f"Audit input capture: {type(error).__name__}: {error}")
        work_deadline = started + args.work_seconds

        def remaining() -> float:
            return work_deadline - time.monotonic()

        controls = run_controls(helper, args, root, output, started)
        report["phases"].append(controls)
        if not controls.get("confirmed"):
            raise RuntimeError("Controls did not confirm exact cleanup; HOLD")
        if not controls.get("passed"):
            raise RuntimeError("Controls exited nonzero; no later phase started")
        if args.control_only:
            report["releaseScope"] = "CONTROL_PROCESSES_ONLY"
        elif args.controls_report is not None:
            evidence = json.loads(
                args.controls_report.resolve(strict=True).read_text("utf-8"))
            if (evidence.get("grant") != args.grant.strip() or
                    evidence.get("result") != "PASS" or
                    not evidence.get("cases")):
                raise ValueError(
                    "A same-grant real PASS controls report is required; "
                    "synthetic results are rejected")
            report["controlsEvidence"] = str(args.controls_report)
        if not args.control_only:
            seconds = remaining()
            if seconds < args.min_phase_seconds:
                report["phases"].append({
                    "name": "focused-suites", "startedAt": now(),
                    "result": "SKIPPED",
                    "reason": "Insufficient remaining plan budget",
                    "remainingSeconds": round(seconds, 3),
                    "confirmed": False, "release": "HOLD_UNRELEASED"})
                report["errors"].append("focused-suites: insufficient remaining budget")
            else:
                phase = run_phase(helper, args, root, output, "focused-suites",
                                  focused_command(args), seconds)
                report["phases"].append(phase)
                if not phase.get("confirmed"):
                    report["errors"].append(
                        "focused-suites: cleanup not confirmed; HOLD")
            scope_seconds = remaining()
            if scope_seconds >= args.min_phase_seconds and not report["errors"]:
                phase = run_phase(helper, args, root, output, "scope-analysis",
                                  scope_command(args), scope_seconds)
                report["phases"].append(phase)
                if not phase.get("confirmed"):
                    report["errors"].append(
                        "scope-analysis: cleanup not confirmed; HOLD")
    except BaseException as error:
        report["errors"].append(f"{type(error).__name__}: {error}")
    finally:
        try:
            owned_after = owned_identities(root)
            report["ownedIdentitiesAfter"] = owned_after
            report["ownedDrift"] = owned_before != owned_after
        except BaseException as error:
            report["errors"].append(
                f"Final owned identity capture: {type(error).__name__}: {error}")
        try:
            suites_after = suite_identities(root, args)
            report["suiteIdentitiesAfter"] = suites_after
            report["suiteDrift"] = changed(suites_before, suites_after)
        except BaseException as error:
            report["errors"].append(
                f"Final suite identity capture: {type(error).__name__}: {error}")
        try:
            libraries_after = bind_libraries(root)
            report["libraryIdentitiesAfter"] = libraries_after
            report["libraryDrift"] = changed(libraries_before, libraries_after)
        except BaseException as error:
            report["errors"].append(
                f"Final library binding capture: {type(error).__name__}: {error}")
        try:
            if audit_inputs is not None and product_before is not None:
                core = (root.parent / "qfli_studio_core").resolve(strict=True)
                product_after, shared_after = audit_inputs.collect_inputs(root, core)
                report["auditInputsAfter"] = input_summary(product_after, shared_after)
                report["auditInputDrift"] = {
                    "product": changed(product_before, product_after),
                    "shared": changed(shared_before, shared_after)}
        except BaseException as error:
            report["errors"].append(
                f"Final input capture: {type(error).__name__}: {error}")
        all_confirmed = bool(report["phases"]) and all(
            phase.get("confirmed") and phase.get("release") == "RELEASE"
            and phase.get("handlesRetained") is False
            for phase in report["phases"] if phase.get("result") != "SKIPPED")
        report["release"] = "RELEASE" if all_confirmed else "HOLD_UNRELEASED"
        report["finishedAt"] = now()
        report["elapsedSeconds"] = round(time.monotonic() - started, 3)
        report["withinPlanSeconds"] = report["elapsedSeconds"] <= args.plan_seconds
        executed = [p for p in report["phases"] if p.get("result") != "SKIPPED"]
        skipped = [p for p in report["phases"] if p.get("result") == "SKIPPED"]
        drift = report.get("auditInputDrift") or {}
        drift_changed = any(drift.get(key) for key in ("product", "shared"))
        passed = (all_confirmed and report["withinPlanSeconds"] and not skipped and
                  bool(executed) and all(p.get("passed") for p in executed) and
                  not report["errors"] and not report.get("ownedDrift") and
                  not report.get("suiteDrift") and not report.get("libraryDrift") and
                  not drift_changed)
        report["result"] = "PASS" if passed else "FAIL_OR_INCONCLUSIVE"
        atomic_report(output / "report.json", report)
        lines = [f"{report['release']} {report['grant']}; "
                 f"next owner {report['nextOwner']}.",
                 f"Result {report['result']}; elapsed={report['elapsedSeconds']}s; "
                 f"withinPlan={report['withinPlanSeconds']}."]
        for phase in report["phases"]:
            lines.append(
                f"{phase['name']}: confirmed={phase.get('confirmed')} "
                f"release={phase.get('release')} exit={phase.get('exitCode')} "
                f"timedOut={phase.get('timedOut')} "
                f"handlesClosed={phase.get('handlesClosed')} "
                f"cleanupConfirmed={phase.get('cleanupConfirmed')}")
        lines.append("Every phase ran through tool/python_owned_process.py run_owned."
                     if not args.control_only else
                     "CONTROL_ONLY release covers its own processes only.")
        lines.append(f"Bound libraries: {', '.join(report['boundLibraries'])}; "
                     "frozen prebuilt binaries, not built by this run.")
        lines.append("No native build, HAP, signature, WSL or device acceptance is claimed.")
        lines.append("Publication NOT_ATTEMPTED; parent must publish this exact evidence.")
        (output / "release-message.md").write_text("\n".join(lines) + "\n",
                                                   encoding="utf-8")
        print("\n".join(lines), flush=True)
    return 0 if report["result"] == "PASS" else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, fromfile_prefix_chars="@")
    parser.add_argument("--grant", required=True,
                        help="NEW named grant; never a REPLACE_ placeholder")
    parser.add_argument("--next-owner", required=True)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[5])
    parser.add_argument("--output", type=Path, required=True,
                        help="New evidence directory under <root>/build")
    parser.add_argument("--plan-seconds", type=float, default=180.0)
    parser.add_argument("--cleanup-seconds", type=float, default=10.0)
    # The real control suite worst case is about 40.3s; keep a margin.
    parser.add_argument("--control-seconds", type=float, default=60.0)
    parser.add_argument("--min-phase-seconds", type=float, default=5.0)
    parser.add_argument("--control-only", action="store_true")
    parser.add_argument("--controls-report", type=Path)
    parser.add_argument("--include-named-workspace", action="store_true")
    parser.add_argument("--include-consumer-tests", action="store_true",
                        help="Add the two bound consumer suites (tools page, "
                             "highlighting) to the same merged call")
    parser.add_argument("--scope", action="append")
    parser.add_argument("--flutter", default="flutter")
    parser.add_argument("--dart", default="dart")
    parser.add_argument("--python", default=sys.executable)
    parser.add_argument("--outer-handle")
    args = parser.parse_args(argv)
    args.scope = tuple(args.scope) if args.scope else DEFAULT_SCOPE
    if os.name != "nt":
        parser.error("Windows only")
    if (not args.grant.strip() or not args.next_owner.strip() or
            args.grant.startswith("REPLACE_") or args.next_owner.startswith("REPLACE_")):
        parser.error("A NEW nonempty named grant and explicit next owner are required")

    def finite_positive(name: str, value: float) -> None:
        if not math.isfinite(value) or value <= 0:
            parser.error(f"{name} must be finite and positive")

    finite_positive("--plan-seconds", args.plan_seconds)
    if args.plan_seconds > 180:
        parser.error("--plan-seconds must not exceed 180 (bounded host window)")
    finite_positive("--cleanup-seconds", args.cleanup_seconds)
    finite_positive("--control-seconds", args.control_seconds)
    finite_positive("--min-phase-seconds", args.min_phase_seconds)
    args.work_seconds = max(1.0, args.plan_seconds - args.cleanup_seconds)
    if args.control_only and args.controls_report is not None:
        parser.error("CONTROL_ONLY does not accept a prior controls report")
    try:
        return run(args)
    except ValueError as error:
        parser.error(str(error))


if __name__ == "__main__":
    raise SystemExit(main())