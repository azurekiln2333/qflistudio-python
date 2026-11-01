"""Synthetic verification for run_python_host.py; no real child process starts.

Uses `run_owned` / `collect_inputs` / `bind_libraries` doubles to prove:

- a confirmed-but-failing controls phase stops the run with zero Flutter calls
  and no later phase;
- an unconfirmed controls phase keeps HOLD_UNRELEASED and starts no Flutter;
- a phase whose root is terminal but whose handles stay open is not confirmed,
  so no later phase starts;
- a synthetic control report is rejected while a same-grant real PASS report is
  accepted and opens the merged focused suite;
- the four focused suites are one `flutter test --no-pub --concurrency=1`
  command, and `--include-named-workspace` joins that same command;
- `--include-consumer-tests` adds the two bound consumer suites to that same
  command and binds them through the suite-identity mechanism, while the default
  (focused, plus named when requested) stays free of them;
- drift of **each** consumer suite individually refuses PASS while the confirmed
  cleanup still releases;
- a missing bound DLL refuses the run before any command is composed, for both
  the default DLL and an environment override;
- a focused-suite or bound-DLL change between the before and after capture fails
  verification while the real confirmed cleanup still publishes RELEASE;
- the double itself refuses an unrecognized command shape and an exhausted
  scripted-report list instead of silently returning a success;
- non-finite, non-positive or over-budget second values and non-`build` output
  paths are rejected before any command is composed.

Every check uses an always-on `require`, never a bare `assert`, so `python -O`
cannot turn this file into a vacuous pass; `main` refuses an optimized
interpreter outright. `main` also refuses a non-Windows host, because the host
wrapper is Windows only and the negative argument checks would otherwise pass
for the wrong reason (the platform guard firing first).

Module seams (`load_owned_helper`, `load_audit_inputs`, `bind_libraries`,
`owned_identities`, `suite_identities`, `DEFAULT_LIBRARY`) are reset to the real
implementations before every check, so no earlier double leaks into a later
check. Import and every check below only read source files, hash small temporary
files and build dictionaries. No Dart, Flutter, analyzer, native, SDK, WSL, HAP
or device process is started.
"""
from __future__ import annotations

import argparse
import contextlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import uuid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
sys.dont_write_bytecode = True

SEAMS = ("load_owned_helper", "load_audit_inputs", "bind_libraries",
         "owned_identities", "suite_identities")


class VerificationError(Exception):
    """Raised by `require`; never compiled out, unlike a bare `assert`."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise VerificationError(message)


def load_runner():
    spec = importlib.util.spec_from_file_location(
        "_verify_run_python_host", HERE / "run_python_host.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    module._originals = {name: getattr(module, name) for name in SEAMS}
    module._default_library = module.DEFAULT_LIBRARY
    return module


def _reset(module) -> None:
    """Restore the real seams so a prior double cannot satisfy a later check."""
    for name, value in module._originals.items():
        setattr(module, name, value)
    module.DEFAULT_LIBRARY = module._default_library


def _classify(module, command: list[str]) -> str:
    """Recognize exactly one owned-process, merged-flutter or analyze shape."""
    if len(command) >= 2 and command[1] == "test/python_owned_process_control_test.py":
        if "--grant" in command and "--output" in command:
            return "owned-process-controls"
        raise VerificationError(f"malformed control command: {command}")
    if command[:4] == ["flutter", "test", "--no-pub", "--concurrency=1"]:
        allowed = (set(module.FOCUSED_SUITES)
                   | {module.NAMED_WORKSPACE_SUITE}
                   | set(module.CONSUMER_SUITES))
        suites = command[4:]
        if suites and all(suite in allowed for suite in suites):
            return "focused-suites"
        raise VerificationError(f"unexpected flutter suites: {command}")
    if command[:2] == ["dart", "analyze"]:
        scope = command[2:]
        if scope and all(item.endswith(".dart") for item in scope):
            return "scope-analysis"
        raise VerificationError(f"unexpected analyze scope: {command}")
    raise VerificationError(f"unrecognized owned command shape: {command}")


class _FakeHelper:
    """Recognizes each command shape and returns one scripted report per call.

    A command that is not an exact owned-process control, merged
    `flutter test --no-pub --concurrency=1` or scoped `dart analyze` raises, and
    an exhausted report list raises. Neither an unexpected extra command nor a
    missing scripted result can silently return a success.
    """

    def __init__(self, module, reports):
        self.module = module
        self.reports = list(reports)
        self.calls: list[list[str]] = []
        self.shapes: list[str] = []

    def run_owned(self, command, **_kwargs):
        call = [str(item) for item in command]
        self.calls.append(call)
        shape = _classify(self.module, call)
        self.shapes.append(shape)
        if not self.reports:
            raise VerificationError(
                f"exhausted scripted reports for {shape}: {call}")
        return self.reports.pop(0)


class _FakeInputs:
    """Stable audit-input digests so synthetic runs do not hash the real tree."""

    def collect_inputs(self, _root, _core):
        return ({"lib/a.dart": "product-hash"},
                {"lib/services/debug_session.dart": "shared-hash"})


class _Drift:
    """Returns one identity set first, then a changed one for the after pass."""

    def __init__(self, *keys):
        self.keys = keys
        self.calls = 0

    def __call__(self, *_args, **_kwargs):
        self.calls += 1
        suffix = "-before" if self.calls == 1 else "-drift"
        return {key: {"bytes": 1, "sha256": key + suffix} for key in self.keys}


def _phase_report(exit_code: int, cleanup: bool = True,
                  handles_closed: bool = True, terminal: bool = True,
                  job_processes: int = 0) -> dict:
    return {
        "state": "FINISHED",
        "release": "RELEASE" if cleanup else "HOLD_UNRELEASED",
        "cleanupConfirmed": cleanup,
        "handlesRetained": not cleanup,
        "exitCode": exit_code,
        "result": "SUCCESS" if exit_code == 0 else "FAILED",
        "timedOut": False,
        "process": {"exitCode": exit_code, "terminal": terminal,
                    "jobActiveProcesses": job_processes,
                    "handlesClosed": handles_closed},
    }


def _ok(count: int) -> list[dict]:
    """Exactly one scripted success report per expected phase call."""
    return [_phase_report(0) for _ in range(count)]


def _namespace(module, output: Path, **overrides) -> argparse.Namespace:
    values = dict(
        grant="VERIFYGRANT", next_owner="verify-author", root=ROOT, output=output,
        plan_seconds=180.0, cleanup_seconds=10.0, control_seconds=60.0,
        min_phase_seconds=5.0, control_only=False, controls_report=None,
        include_named_workspace=False, include_consumer_tests=False,
        scope=module.DEFAULT_SCOPE,
        flutter="flutter", dart="dart", python=sys.executable, outer_handle=None,
    )
    values.update(overrides)
    namespace = argparse.Namespace(**values)
    namespace.work_seconds = max(1.0, namespace.plan_seconds - namespace.cleanup_seconds)
    return namespace


@contextlib.contextmanager
def _workspace():
    base = ROOT / "build" / f"_verify_run_host_{uuid.uuid4().hex}"
    base.mkdir(parents=True, exist_ok=False)
    try:
        yield base, base / "evidence"
    finally:
        shutil.rmtree(base, ignore_errors=True)


def _install(module, helper) -> None:
    """Install every double a run touches, so no real helper is ever loaded."""
    _reset(module)
    module.load_owned_helper = lambda root, helper=helper: helper
    module.load_audit_inputs = lambda root: _FakeInputs()
    module.bind_libraries = lambda root: {"default": {"bytes": 1, "sha256": "lib"}}
    module.owned_identities = lambda root: {"owned": {"sha256": "owned"}}
    module.suite_identities = lambda root, args: {"suite": {"sha256": "suite"}}


def _read(output: Path) -> dict:
    return json.loads((output / "report.json").read_text(encoding="utf-8"))


def _flutter_calls(helper: _FakeHelper) -> list[list[str]]:
    return [call for call in helper.calls if call and call[0] == "flutter"]


def check_control_failure_stops_before_flutter(module) -> None:
    with _workspace() as (base, output):
        helper = _FakeHelper(module, [_phase_report(1)])
        _install(module, helper)
        code = module.run(_namespace(module, output))
        report = _read(output)
        require(len(helper.calls) == 1, f"later phase started: {helper.calls}")
        require(not _flutter_calls(helper), "Flutter started after failing controls")
        require(code != 0 and report["result"] != "PASS", report["result"])
        require(report["release"] == "RELEASE", report["release"])
        require(any("Controls exited nonzero" in item for item in report["errors"]),
                report["errors"])


def check_control_hold_never_releases(module) -> None:
    with _workspace() as (base, output):
        helper = _FakeHelper(module, [_phase_report(1, cleanup=False)])
        _install(module, helper)
        code = module.run(_namespace(module, output))
        report = _read(output)
        require(not _flutter_calls(helper),
                "Flutter started without confirmed cleanup")
        require(code != 0 and report["release"] == "HOLD_UNRELEASED",
                report["release"])


def check_open_handles_never_confirm(module) -> None:
    with _workspace() as (base, output):
        helper = _FakeHelper(module, [_phase_report(0, handles_closed=False)])
        _install(module, helper)
        code = module.run(_namespace(module, output))
        report = _read(output)
        require(not _flutter_calls(helper), "Flutter started with open handles")
        controls = report["phases"][0]
        require(controls["handlesClosed"] is False, controls)
        require(controls["confirmed"] is False, controls)
        require(code != 0 and report["release"] == "HOLD_UNRELEASED",
                report["release"])


def check_synthetic_controls_report_rejected(module) -> None:
    with _workspace() as (base, output):
        evidence = base / "controls.json"
        evidence.write_text(json.dumps({
            "grant": "VERIFYGRANT", "result": "SYNTHETIC_PASS",
            "cases": [], "syntheticCases": [{}], "errors": [],
        }), encoding="utf-8")
        helper = _FakeHelper(module, [_phase_report(0)])
        _install(module, helper)
        code = module.run(_namespace(module, output, controls_report=evidence))
        report = _read(output)
        require(len(helper.calls) == 1,
                "Flutter started on a synthetic control report")
        require(code != 0, code)
        require(any("real PASS controls report" in item for item in report["errors"]),
                report["errors"])


def check_real_controls_report_opens_merged_suite(module) -> None:
    with _workspace() as (base, output):
        evidence = base / "controls.json"
        evidence.write_text(json.dumps({
            "grant": "VERIFYGRANT", "result": "PASS",
            "cases": [{"name": "normal"}], "syntheticCases": [], "errors": [],
        }), encoding="utf-8")
        helper = _FakeHelper(module, _ok(3))
        _install(module, helper)
        code = module.run(_namespace(module, output, controls_report=evidence))
        report = _read(output)
        flutter = _flutter_calls(helper)
        require(len(flutter) == 1, f"focused suites were not merged: {helper.calls}")
        command = flutter[0]
        require(command[1:4] == ["test", "--no-pub", "--concurrency=1"], command)
        for suite in module.FOCUSED_SUITES:
            require(suite in command, f"missing suite {suite}: {command}")
        require(module.NAMED_WORKSPACE_SUITE not in command, command)
        require(code == 0, report)
        require(report["result"] == "PASS", report["result"])
        require(report["boundSuites"] == list(module.FOCUSED_SUITES),
                report["boundSuites"])


def check_named_workspace_joins_same_call(module) -> None:
    with _workspace() as (base, output):
        helper = _FakeHelper(module, _ok(3))
        _install(module, helper)
        module.suite_identities = (lambda root, args:
                                   {name: {"sha256": "suite"}
                                    for name in module.suite_relative(args)})
        code = module.run(_namespace(module, output, include_named_workspace=True,
                                     control_only=False))
        report = _read(output)
        flutter = _flutter_calls(helper)
        require(len(flutter) == 1,
                f"named workspace opened a second call: {helper.calls}")
        require(module.NAMED_WORKSPACE_SUITE in flutter[0], flutter[0])
        require(module.NAMED_WORKSPACE_SUITE in report["boundSuites"],
                report["boundSuites"])
        require(code == 0, report)


def check_consumer_tests_join_same_call(module) -> None:
    """Both consumer suites execute in the one merged call and are bound."""
    with _workspace() as (base, output):
        helper = _FakeHelper(module, _ok(3))
        _install(module, helper)
        module.suite_identities = (lambda root, args:
                                   {name: {"sha256": "suite"}
                                    for name in module.suite_relative(args)})
        code = module.run(_namespace(module, output, include_consumer_tests=True))
        report = _read(output)
        flutter = _flutter_calls(helper)
        require(len(flutter) == 1,
                f"consumer tests opened a second call: {helper.calls}")
        command = flutter[0]
        require(command[1:4] == ["test", "--no-pub", "--concurrency=1"], command)
        for suite in module.FOCUSED_SUITES:
            require(suite in command, f"missing focused suite {suite}: {command}")
        for suite in module.CONSUMER_SUITES:
            require(suite in command, f"missing consumer suite {suite}: {command}")
            require(suite in report["boundSuites"],
                    f"consumer suite not bound: {suite}: {report['boundSuites']}")
            require(suite in report["suiteIdentitiesBefore"],
                    f"consumer suite not hashed: {suite}")
            require(suite in report["suiteIdentitiesAfter"],
                    f"consumer suite not re-hashed: {suite}")
        require(module.NAMED_WORKSPACE_SUITE not in command, command)
        require(report["boundConsumers"] == list(module.CONSUMER_SUITES),
                report["boundConsumers"])
        require(report["boundSuites"] == (list(module.FOCUSED_SUITES)
                                          + list(module.CONSUMER_SUITES)),
                report["boundSuites"])
        require(code == 0, report)
        require(report["result"] == "PASS", report["result"])


def check_consumer_tests_default_off(module) -> None:
    """Default semantics: consumers neither run nor get claimed as bound.

    This is exact evidence, not merely absence from the command line. The report
    must carry an empty `boundConsumers`, `boundSuites` must equal the default
    tuple exactly, and no consumer name may appear in either suite-identity
    capture. A blanket `boundConsumers` list would falsely advertise a consumer
    suite that never executed and was never hashed.
    """
    expected = module.FOCUSED_SUITES + (module.NAMED_WORKSPACE_SUITE,)
    probe = _namespace(module, Path("unused-evidence"),
                       include_named_workspace=True)
    require(tuple(module.suite_relative(probe)) == expected,
            f"default suite set changed: {module.suite_relative(probe)}")
    for suite in module.CONSUMER_SUITES:
        require(suite not in expected,
                f"a consumer suite joined the default bound set: {suite}")
    with _workspace() as (base, output):
        helper = _FakeHelper(module, _ok(3))
        _install(module, helper)
        module.suite_identities = (lambda root, args:
                                   {name: {"sha256": "suite"}
                                    for name in module.suite_relative(args)})
        code = module.run(_namespace(module, output, include_named_workspace=True))
        report = _read(output)
        flutter = _flutter_calls(helper)
        require(len(flutter) == 1, helper.calls)
        require(module.NAMED_WORKSPACE_SUITE in flutter[0], flutter[0])
        require(report["boundConsumers"] == [],
                "boundConsumers claims a consumer suite without the flag: "
                f"{report['boundConsumers']}")
        require(report["boundSuites"] == list(expected), report["boundSuites"])
        for suite in module.CONSUMER_SUITES:
            require(suite not in flutter[0],
                    f"a consumer suite ran without the flag: {suite}")
            require(suite not in report["boundSuites"], report["boundSuites"])
            require(suite not in report["suiteIdentitiesBefore"],
                    f"consumer hashed without the flag: {suite}")
            require(suite not in report["suiteIdentitiesAfter"],
                    f"consumer re-hashed without the flag: {suite}")
        require(code == 0, report)
        require(report["result"] == "PASS", report["result"])


def check_consumer_suite_drift_fails_but_releases(module) -> None:
    """Drift of EACH consumer suite individually refuses PASS but releases."""
    for consumer in module.CONSUMER_SUITES:
        with _workspace() as (base, output):
            helper = _FakeHelper(module, _ok(3))
            _install(module, helper)
            module.suite_identities = _Drift(consumer)
            code = module.run(_namespace(module, output,
                                         include_consumer_tests=True))
            report = _read(output)
            require(report["release"] == "RELEASE", report["release"])
            require(code != 0 and report["result"] != "PASS",
                    (consumer, report["result"]))
            require(consumer in (report["suiteDrift"] or []),
                    (consumer, report["suiteDrift"]))
            require(not report.get("libraryDrift"), report.get("libraryDrift"))


def check_missing_library_refuses_before_flutter(module) -> None:
    with tempfile.TemporaryDirectory() as temporary:
        missing = Path(temporary) / "absent.dll"
        with _workspace() as (base, output):
            helper = _FakeHelper(module, [_phase_report(0)])
            # Keep the real `bind_libraries`; only the process seams are doubled.
            _reset(module)
            module.load_owned_helper = lambda root, helper=helper: helper
            module.load_audit_inputs = lambda root: _FakeInputs()

            # The default DLL itself must always be bound.
            module.DEFAULT_LIBRARY = "native/build/windows/_verify_absent.dll"
            try:
                module.run(_namespace(module, output))
            except ValueError:
                pass
            else:
                raise VerificationError("A missing default DLL did not refuse the run")
            finally:
                module.DEFAULT_LIBRARY = module._default_library
            require(not helper.calls, "Flutter started despite a missing default DLL")
            require(not output.exists(), "Evidence was created despite a missing DLL")

            # An environment override path must exist too.
            original_env = os.environ.get("QFLI_PY_DEBUG_TEST_LIBRARY")
            os.environ["QFLI_PY_DEBUG_TEST_LIBRARY"] = str(missing)
            try:
                module.run(_namespace(module, output))
            except ValueError:
                pass
            else:
                raise VerificationError("A missing override DLL did not refuse the run")
            finally:
                if original_env is None:
                    os.environ.pop("QFLI_PY_DEBUG_TEST_LIBRARY", None)
                else:
                    os.environ["QFLI_PY_DEBUG_TEST_LIBRARY"] = original_env
            require(not helper.calls, "Flutter started despite a missing override DLL")
            require(not output.exists(), "Evidence was created despite a missing DLL")


def check_suite_drift_fails_but_releases(module) -> None:
    with _workspace() as (base, output):
        helper = _FakeHelper(module, _ok(3))
        _install(module, helper)
        module.suite_identities = _Drift(*module.FOCUSED_SUITES)
        code = module.run(_namespace(module, output))
        report = _read(output)
        require(report["release"] == "RELEASE", report["release"])
        require(code != 0 and report["result"] != "PASS", report["result"])
        require(report["suiteDrift"], report)
        require(any(name in report["suiteDrift"] for name in module.FOCUSED_SUITES),
                report["suiteDrift"])
        require(not report.get("libraryDrift"), report.get("libraryDrift"))


def check_library_drift_fails_but_releases(module) -> None:
    with _workspace() as (base, output):
        helper = _FakeHelper(module, _ok(3))
        _install(module, helper)
        module.bind_libraries = _Drift("default")
        code = module.run(_namespace(module, output))
        report = _read(output)
        require(report["release"] == "RELEASE", report["release"])
        require(code != 0 and report["result"] != "PASS", report["result"])
        require(report["libraryDrift"], report)
        require(not report.get("suiteDrift"), report.get("suiteDrift"))


def check_fake_helper_refuses_unknown_and_exhausted(module) -> None:
    """The double itself must refuse, so no extra call can silently succeed."""
    probe = _FakeHelper(module, [_phase_report(0)])
    try:
        probe.run_owned(["python", "test/some_other_test.py"])
    except VerificationError:
        pass
    else:
        raise VerificationError("unknown command shape returned a report")

    probe = _FakeHelper(module, [])
    try:
        probe.run_owned(["flutter", "test", "--no-pub", "--concurrency=1",
                         *module.FOCUSED_SUITES])
    except VerificationError:
        pass
    else:
        raise VerificationError("exhausted scripted reports returned a success")

    accepted = _FakeHelper(module, [_phase_report(0)])
    report = accepted.run_owned(["python",
                                 "test/python_owned_process_control_test.py",
                                 "--grant", "G", "--output", "o"])
    require(report.get("exitCode") == 0, report)
    require(accepted.shapes == ["owned-process-controls"], accepted.shapes)

    for bad in (
        ["flutter", "test", "--concurrency=1", *module.FOCUSED_SUITES],
        ["flutter", "test", "--no-pub", "--concurrency=1",
         "test/unknown_test.dart"],
        ["dart", "analyze"],
        ["dart", "analyze", "tool/not_dart.txt"],
        ["python", "test/python_owned_process_control_test.py", "--grant", "G"],
    ):
        malformed = _FakeHelper(module, [_phase_report(0)])
        try:
            malformed.run_owned(bad)
        except VerificationError:
            continue
        raise VerificationError(f"malformed command was accepted: {bad}")


def check_second_values_and_output_rejected(module) -> None:
    with tempfile.TemporaryDirectory() as temporary:
        bad_output = Path(temporary) / "evidence"
        rejected_seconds = (
            ["--plan-seconds", "181"],
            ["--plan-seconds", "200"],
            ["--plan-seconds", "nan"],
            ["--plan-seconds", "inf"],
            ["--cleanup-seconds", "0"],
            ["--cleanup-seconds", "-1"],
            ["--cleanup-seconds", "inf"],
            ["--control-seconds", "nan"],
            ["--min-phase-seconds", "0"],
        )
        with _workspace() as (base, output):
            helper = _FakeHelper(module, [])
            _install(module, helper)
            for extra in rejected_seconds:
                argv = ["--grant", "G", "--next-owner", "N",
                        "--output", str(output), *extra]
                try:
                    module.main(argv)
                except SystemExit as exit_code:
                    require(exit_code.code not in (0, None), f"not rejected: {argv}")
                else:
                    raise VerificationError(f"Argument was not rejected: {argv}")
            require(not output.exists(),
                    "Rejected arguments still composed an output")
            # A valid plan with an output outside <root>/build must be rejected.
            try:
                module.main(["--grant", "G", "--next-owner", "N",
                             "--output", str(bad_output)])
            except SystemExit as exit_code:
                require(exit_code.code not in (0, None), "non-build output accepted")
            else:
                raise VerificationError("Output outside <root>/build was accepted")
            require(not bad_output.exists(), "non-build output was created")
            require(not helper.calls, "a rejected argument started a phase")


def main() -> int:
    if sys.flags.optimize != 0 or not __debug__:
        print("OPTIMIZED_INTERPRETER_REJECTED: run without -O/-OO so every "
              "check stays active", file=sys.stderr, flush=True)
        return 2
    if os.name != "nt":
        print("NON_WINDOWS_HOST_REJECTED: run_python_host.py is Windows only; "
              "checks here would pass vacuously for the wrong reason",
              file=sys.stderr, flush=True)
        return 2
    module = load_runner()
    checks = (
        check_control_failure_stops_before_flutter,
        check_control_hold_never_releases,
        check_open_handles_never_confirm,
        check_synthetic_controls_report_rejected,
        check_real_controls_report_opens_merged_suite,
        check_named_workspace_joins_same_call,
        check_consumer_tests_join_same_call,
        check_consumer_tests_default_off,
        check_consumer_suite_drift_fails_but_releases,
        check_missing_library_refuses_before_flutter,
        check_suite_drift_fails_but_releases,
        check_library_drift_fails_but_releases,
        check_fake_helper_refuses_unknown_and_exhausted,
        check_second_values_and_output_rejected,
    )
    for check in checks:
        check(module)
        print(f"SYNTHETIC_PASS {check.__name__}", flush=True)
    print("SYNTHETIC_VERIFY_PASS no real process was started", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())