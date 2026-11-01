"""Synthetic verification for run_python_granted_window.py; starts no process.

The window is now a coordinating observer: it starts `run_python_host.py` as a
separate `run_owned`-managed child and only publishes after that child root is
terminal, Job ActiveProcesses == 0 and handles are closed. Both `run_owned` and
the publisher resolver are replaced with doubles, so this file proves the
observer contract without starting a child, publishing, or running any tool.

Covered here:

- placeholder, blank, replayed and self-owned grants, plus window or child
  budgets that do not fit, are rejected before any evidence directory exists;
- a failed ACK blocks the child entirely and never publishes;
- a managed root that exited 0 with a live Job, a root that is not terminal, or
  a root whose handles were not closed never publishes a final status;
- the verification child is a separate process and never publishes itself;
- `--include-consumer-tests` is threaded to the child unchanged, while the
  default window runs without it;
- success publishes ACK, one managed child, then RELEASE, in that order;
- a failed verification, a missing child report, a phase without closure
  evidence, a source drift and an over-budget child all stay FAIL but still
  RELEASE when the managed root really closed;
- the local report release, the summary line and the global message agree, and
  the message never claims the observer itself exited.

Every check installs strict doubles before any `module.main` call. The fake
helper rejects an unrecognised command immediately and has no real fallback, so
a deliberately widened or regressed guard still performs zero real I/O. This is
the direct answer to the C607-NEG shape, where a negative branch resolved to a
real execution and the defect was only detected after the side effect.

The verifier also refuses to run on a non-Windows host: every guard under test
rejects for the platform reason there, so a PASS would be vacuous.

Every check reads source files and builds dictionaries only.
"""
from __future__ import annotations

import contextlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import time
import uuid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
sys.dont_write_bytecode = True


def load_window():
    spec = importlib.util.spec_from_file_location(
        "_verify_run_python_granted_window",
        HERE / "run_python_granted_window.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def check(condition: object, message: str) -> None:
    """Always-on verifier check; never a bare assert."""
    if not condition:
        raise AssertionError(message)


def _owned(exit_code: int = 0, cleanup: bool = True, terminal: bool = True,
           job_active: int = 0, handles_closed: bool = True,
           timed_out: bool = False, identity: bool = True) -> dict:
    """A scripted run_owned report with exact root identity evidence."""
    return {
        "state": "FINISHED",
        "release": "RELEASE" if cleanup else "HOLD_UNRELEASED",
        "cleanupConfirmed": cleanup,
        "handlesRetained": not cleanup,
        "exitCode": exit_code,
        "result": "SUCCESS" if exit_code == 0 else "FAILED",
        "timedOut": timed_out,
        "process": {
            "exitCode": exit_code,
            "terminal": terminal,
            "jobActiveProcesses": job_active,
            "handlesClosed": handles_closed,
            "pid": 4242 if identity else None,
            "creationFiletime100ns": "133000000000000000" if identity else None,
            "processHandleDecimal": "8738" if identity else None,
            "jobHandleDecimal": "4369" if identity else None,
        },
    }


def _phase(name: str, result: str = "pass", cleanup: bool = True,
           handles_closed: bool | None = None) -> dict:
    if handles_closed is None:
        handles_closed = cleanup
    return {"name": name, "result": result, "cleanupConfirmed": cleanup,
            "handlesRetained": not cleanup,
            "release": "RELEASE" if cleanup else "HOLD_UNRELEASED",
            "rootTerminal": cleanup,
            "jobActiveProcesses": 0 if cleanup else 1,
            "handlesClosed": handles_closed,
            "passed": cleanup and result == "pass"}


def _child_report(result: str = "PASS", release: str = "RELEASE", phases=None,
                  within: bool = True, owned_drift: bool = False, errors=None,
                  drift=None) -> dict:
    if phases is None:
        phases = [_phase("owned-process-controls"), _phase("focused-suites")]
    return {"result": result, "release": release, "phases": phases,
            "withinPlanSeconds": within, "ownedDrift": owned_drift,
            "errors": list(errors or []),
            "auditInputDrift": drift or {"product": [], "shared": []}}


class _FakeHelper:
    """Scripted run_owned reports; writes the child report on the child call."""

    def __init__(self, reports=None, child_report=None, child_marker=None,
                 release_delay: float = 0.0):
        self.reports = list(reports or [])
        self.calls: list[list[str]] = []
        self.child_report = child_report
        self.child_marker = child_marker
        self.release_delay = release_delay
        self.child_calls = 0

    def run_owned(self, command, **_kwargs):
        rendered = [str(item) for item in command]
        self.calls.append(rendered)
        joined = " ".join(rendered)
        if "ack-message.md" in joined:
            kind = "ack"
        elif self.child_marker and self.child_marker in joined:
            kind = "child"
        elif "release-message.md" in joined:
            kind = "release"
        else:
            # No real fallback on purpose: an unrecognised command in a
            # synthetic run is a harness defect and must surface here, before
            # anything else can happen.
            raise RuntimeError(
                f"Unrecognised command in a synthetic run: {joined}")
        if kind == "child":
            self.child_calls += 1
            if self.child_report is not None:
                target = Path(rendered[rendered.index("--output") + 1])
                target.mkdir(parents=True, exist_ok=True)
                (target / "report.json").write_text(
                    json.dumps(self.child_report), encoding="utf-8")
        if kind == "release" and self.release_delay:
            time.sleep(self.release_delay)
        if not self.reports:
            raise RuntimeError(
                f"No scripted report for the {kind} command: {joined}")
        return self.reports.pop(0)

    def publish_calls(self) -> list[list[str]]:
        return [call for call in self.calls if "channel" in call]


@contextlib.contextmanager
def _workspace():
    base = ROOT / "build" / f"_verify_granted_{uuid.uuid4().hex}"
    base.mkdir(parents=True, exist_ok=False)
    try:
        yield base, base / "evidence"
    finally:
        shutil.rmtree(base, ignore_errors=True)


def _install(module, helper) -> None:
    module.load_owned_helper = lambda root, helper=helper: helper
    module.resolve_publisher = lambda args: ["node", "trellis.js"]


def _helper(module, reports, child_report, **kwargs) -> _FakeHelper:
    return _FakeHelper(reports, child_report=child_report,
                       child_marker=str(module.INNER_PATH), **kwargs)


def _run(module, output: Path, *extra: str, grant: str = "NEWGRANT20261026"):
    return module.main(["--grant", grant, "--next-owner", "c-coordinator",
                        "--output", str(output), *extra])


def _read(output: Path) -> dict:
    return json.loads((output / "report.json").read_text(encoding="utf-8"))


def _published(output: Path, name: str) -> str:
    return (output / name).read_text(encoding="utf-8")


# The prepared, not-yet-run readiness command's window flags. Total reserve is
# 12 + 138 + 10 + 15 + 5 = 180 s; the child wall is 123 + 3*5 = 138 s and the
# child work budget is 123 - 5 = 118 s for controls, five merged suites and the
# scoped analyze.
READINESS_FLAGS = (
    "--total-seconds", "180",
    "--ack-seconds", "12",
    "--inner-seconds", "138",
    "--inner-plan-seconds", "123",
    "--child-cleanup-seconds", "5",
    "--outer-cleanup-seconds", "10",
    "--publish-seconds", "15",
    "--margin-seconds", "5",
    "--max-inner-phases", "3",
    "--control-seconds", "60",
    "--min-phase-seconds", "5",
    "--include-named-workspace",
)


def check_argument_guards(module) -> None:
    base = ROOT / "build" / f"_verify_guards_{uuid.uuid4().hex}"
    base.mkdir(parents=True, exist_ok=False)
    output = base / "evidence"
    # Install strict doubles BEFORE the first module.main. If any negative case
    # ever regresses and is accepted, the fake helper and fake publisher are
    # still the only collaborators, so the defect is reported with zero real
    # I/O (C607-NEG).
    _install(module, _helper(module, [], None))
    try:
        cases = [
            [],
            ["--next-owner", "c-coordinator"],
            ["--grant", "   ", "--next-owner", "c-coordinator"],
            ["--grant", "REPLACE_GRANT", "--next-owner", "c-coordinator"],
            ["--grant", "G1"],
            ["--grant", "G1", "--next-owner", "REPLACE_OWNER"],
            ["--grant", "G1", "--next-owner", "python-offline-1022"],
            ["--grant", "G1", "--next-owner", "c-coordinator",
             "--used-grant", "G1"],
            ["--grant", "G1", "--next-owner", "c-coordinator",
             "--total-seconds", "181"],
            ["--grant", "G1", "--next-owner", "c-coordinator",
             "--inner-seconds", "146"],
            # 12+120+10+18+5 = 165 must fit, so 160 is rejected.
            ["--grant", "G1", "--next-owner", "c-coordinator",
             "--total-seconds", "160"],
            # 105 + 3*5 = 120 fits; 106 + 15 = 121 exceeds the inner timeout.
            ["--grant", "G1", "--next-owner", "c-coordinator",
             "--inner-plan-seconds", "106"],
            ["--grant", "G1", "--next-owner", "c-coordinator",
             "--ack-seconds", "0"],
            ["--grant", "G1", "--next-owner", "c-coordinator",
             "--inner-seconds", "inf"],
            ["--grant", "G1", "--next-owner", "c-coordinator",
             "--max-inner-phases", "0"],
        ]
        for argv in cases:
            try:
                module.main([*argv, "--output", str(output)])
            except SystemExit as exit_code:
                check(exit_code.code not in (0, None), f"not rejected: {argv}")
            else:
                raise AssertionError(f"Argument was accepted: {argv}")
        check(not output.exists(), "A rejected window created evidence")
        with tempfile.TemporaryDirectory() as temporary:
            outside = Path(temporary) / "evidence"
            try:
                module.main(["--grant", "G1", "--next-owner", "c-coordinator",
                             "--output", str(outside)])
            except SystemExit as exit_code:
                check(exit_code.code not in (0, None), "non-build output accepted")
            else:
                raise AssertionError("Output outside <root>/build was accepted")
            check(not outside.exists(), "A non-build output directory was created")
    finally:
        shutil.rmtree(base, ignore_errors=True)


def check_ack_failure_blocks_child(module) -> None:
    with _workspace() as (base, output):
        helper = _helper(module, [_owned(exit_code=1)], _child_report())
        _install(module, helper)
        code = _run(module, output)
        report = _read(output)
        check(helper.child_calls == 0, "Child started after an ACK failure")
        check(len(helper.calls) == 1, f"Extra command happened: {helper.calls}")
        check(report["ack"]["delivered"] is False, report["ack"])
        check(report["verificationRoot"]["started"] is False,
              report["verificationRoot"])
        check(report["publication"]["delivered"] is False, report["publication"])
        check(report["result"] == "ACK_NOT_DELIVERED", report["result"])
        check(report["release"] == "HOLD_UNRELEASED", report["release"])
        check(code != 0, code)


def _assert_no_final_publish(module, output, helper, child_owned, label) -> None:
    with _workspace() as (base, inner_output):
        helper.reports = [_owned(), child_owned]
        helper.child_report = _child_report()
        _install(module, helper)
        code = _run(module, inner_output)
        report = _read(inner_output)
        check(helper.child_calls == 1, f"{label}: child did not run once")
        check(len(helper.publish_calls()) == 1,
              f"{label}: a final publish happened: {helper.publish_calls()}")
        check(report["verificationRoot"]["confirmed"] is False,
              f"{label}: root wrongly confirmed")
        check(report["publication"]["delivered"] is False,
              f"{label}: publication wrongly delivered")
        check(report["result"] == "HOLD_UNRELEASED", f"{label}: {report['result']}")
        check(report["release"] == "HOLD_UNRELEASED", f"{label}: {report['release']}")
        check(not (inner_output / "release-message.md").exists(),
              f"{label}: a final message file was written")
        check(code != 0, code)


def check_root_exit_zero_with_live_job_no_final_publish(module) -> None:
    helper = _FakeHelper([], child_marker=str(module.INNER_PATH))
    _assert_no_final_publish(module, None, helper,
                             _owned(exit_code=0, job_active=1),
                             "live job after root exit")


def check_root_not_terminal_no_final_publish(module) -> None:
    helper = _FakeHelper([], child_marker=str(module.INNER_PATH))
    _assert_no_final_publish(module, None, helper,
                             _owned(terminal=False),
                             "root not terminal")


def check_handles_not_closed_no_final_publish(module) -> None:
    helper = _FakeHelper([], child_marker=str(module.INNER_PATH))
    _assert_no_final_publish(module, None, helper,
                             _owned(handles_closed=False),
                             "handles not closed")


def check_missing_root_identity_no_final_publish(module) -> None:
    helper = _FakeHelper([], child_marker=str(module.INNER_PATH))
    _assert_no_final_publish(module, None, helper,
                             _owned(identity=False),
                             "missing exact root identity")


def check_child_never_publishes(module) -> None:
    with _workspace() as (base, output):
        helper = _helper(module, [_owned(), _owned(), _owned()], _child_report())
        _install(module, helper)
        _run(module, output)
        report = _read(output)
        child_calls = [call for call in helper.calls
                       if str(module.INNER_PATH) in " ".join(call)]
        check(len(child_calls) == 1, child_calls)
        child_command = " ".join(child_calls[0])
        check("channel" not in child_command and "send" not in child_command,
              f"child command would publish: {child_command}")
        check(child_command.startswith("python") or
              str(module.INNER_PATH) in child_command, child_command)
        check(report["verificationRoot"]["publication"] == "NOT_ATTEMPTED",
              report["verificationRoot"])
        check(report["mode"] == "GRANTED_WINDOW_OBSERVER", report["mode"])
        check(report["observerPid"] is not None, report)
        check(report["observerRole"].startswith("Coordinator only"), report)


def check_success_single_window(module) -> None:
    with _workspace() as (base, output):
        helper = _helper(module, [_owned(), _owned(), _owned()], _child_report())
        _install(module, helper)
        code = _run(module, output)
        report = _read(output)
        check(code == 0, f"{code}: {report['errors']}")
        check(report["result"] == "PASS", report["result"])
        check(report["release"] == "RELEASE", report["release"])
        check(report["ack"]["delivered"] is True, report["ack"])
        root = report["verificationRoot"]
        check(root["confirmed"] is True, root)
        check(root["terminal"] is True and root["jobActiveProcesses"] == 0,
              root)
        check(root["handlesClosed"] is True, root)
        check(root["rootPid"] == 4242, root)
        check(root["publication"] == "NOT_ATTEMPTED", root)
        check(report["publication"]["delivered"] is True, report["publication"])
        check(report["publication"]["claimedStatus"] == "RELEASE",
              report["publication"])
        check(report["withinTotalSeconds"] is True, report)
        check(report["ownedDrift"] is False, report.get("ownedDrift"))
        # Order: ACK, then the separate managed child, then the final release.
        check(len(helper.calls) == 3, helper.calls)
        check("ack-message.md" in " ".join(helper.calls[0]), helper.calls[0])
        check(str(module.INNER_PATH) in " ".join(helper.calls[1]),
              helper.calls[1])
        check("release-message.md" in " ".join(helper.calls[2]), helper.calls[2])
        command = helper.calls[2]
        check(command[:4] == ["node", "trellis.js", "channel", "send"], command)
        check("qfli-core-release-sync" in command, command)
        check("--scope" in command and "global" in command, command)
        check("--text-file" in command, command)
        check("--to" in command and "c-coordinator" in command, command)
        text = _published(output, "release-message.md")
        check(text.startswith("RELEASE NEWGRANT20261026"), text)
        check("verification root PID=4242" in text, text)
        check("observer PID=" in text, text)
        check("does not claim it has exited" in text, text)
        check("Job=4369" in text and "HANDLE=8738" in text, text)
        summary = _published(output, "window-summary.md")
        check(summary.startswith("RELEASE NEWGRANT20261026"), summary)
        check("result=PASS" in summary, summary)
        # Only argv[0] of each call matters: the child command carries
        # --flutter/--dart as arguments, but the double starts no real tool.
        for call in helper.calls:
            program = Path(call[0]).name.lower()
            check(program not in {"flutter", "flutter.bat", "dart", "dart.exe",
                                  "hvigor", "hdc"},
                  f"real tool was started: {call}")
        check(helper.child_calls == 1, helper.child_calls)


def _run_failed_clean(module, output, helper) -> dict:
    _install(module, helper)
    _run(module, output)
    return _read(output)


def check_failed_verification_releases(module) -> None:
    with _workspace() as (base, output):
        helper = _helper(module, [_owned(), _owned(exit_code=1), _owned()],
                         _child_report(result="FAIL_OR_INCONCLUSIVE"))
        report = _run_failed_clean(module, output, helper)
        check(report["verificationRoot"]["confirmed"] is True, report)
        check(report["inner"]["passed"] is False, report["inner"])
        check(report["result"] == "FAIL_OR_INCONCLUSIVE", report["result"])
        check(report["release"] == "RELEASE", report["release"])
        check(report["publication"]["delivered"] is True, report["publication"])
        check(report["publication"]["claimedStatus"] == "RELEASE",
              report["publication"])


def check_failed_report_matches_global_message(module) -> None:
    with _workspace() as (base, output):
        helper = _helper(module, [_owned(), _owned(exit_code=1), _owned()],
                         _child_report(result="FAIL_OR_INCONCLUSIVE"))
        report = _run_failed_clean(module, output, helper)
        text = _published(output, "release-message.md")
        check(report["release"] == "RELEASE", report["release"])
        check(text.startswith("RELEASE NEWGRANT20261026"), text)
        check("no handoff" not in text, text)
        check("FAIL_OR_INCONCLUSIVE" in text, text)
        check("not a cleanup failure" in text, text)
        check("does not claim it has exited" in text, text)
        summary = _published(output, "window-summary.md")
        check(summary.startswith("RELEASE NEWGRANT20261026"), summary)
        check("result=FAIL_OR_INCONCLUSIVE" in summary, summary)


def check_over_budget_child_fails_but_releases(module) -> None:
    with _workspace() as (base, output):
        # Child exceeded its managed timeout and was terminated by run_owned;
        # the root is still confirmed closed, so ownership is released.
        helper = _helper(module, [_owned(),
                                  _owned(exit_code=124, timed_out=True),
                                  _owned()], _child_report())
        _install(module, helper)
        _run(module, output)
        report = _read(output)
        check(report["verificationRoot"]["confirmed"] is True, report)
        check(report["verificationRoot"]["timedOut"] is True, report)
        check(report["result"] == "FAIL_OR_INCONCLUSIVE", report["result"])
        check(report["release"] == "RELEASE", report["release"])
        text = _published(output, "release-message.md")
        check(text.startswith("RELEASE NEWGRANT20261026"), text)
        check("no handoff" not in text, text)


def check_wall_clock_over_budget_fails_but_releases(module) -> None:
    with _workspace() as (base, output):
        helper = _helper(module, [_owned(), _owned(), _owned()],
                         _child_report(), release_delay=0.6)
        _install(module, helper)
        code = _run(module, output,
                    "--total-seconds", "0.5",
                    "--ack-seconds", "0.1",
                    "--publish-seconds", "0.1",
                    "--margin-seconds", "0.01",
                    "--inner-seconds", "0.1",
                    "--outer-cleanup-seconds", "0.01",
                    "--inner-plan-seconds", "0.05",
                    "--child-cleanup-seconds", "0.01",
                    "--max-inner-phases", "1")
        report = _read(output)
        check(report["withinTotalSeconds"] is False, report["withinTotalSeconds"])
        check(report["result"] == "FAIL_OR_INCONCLUSIVE", report["result"])
        check(report["publication"]["delivered"] is True, report["publication"])
        check(report["release"] == "RELEASE", report["release"])
        check(code != 0, code)


def check_missing_child_report_is_fail_but_release(module) -> None:
    with _workspace() as (base, output):
        helper = _helper(module, [_owned(), _owned(), _owned()], None)
        _install(module, helper)
        _run(module, output)
        report = _read(output)
        check(report["verificationRoot"]["confirmed"] is True, report)
        check(report["inner"]["reportPresent"] is False, report["inner"])
        check(report["inner"]["passed"] is False, report["inner"])
        check(report["result"] == "FAIL_OR_INCONCLUSIVE", report["result"])
        check(report["release"] == "RELEASE", report["release"])


def check_phase_closure_evidence_required(module) -> None:
    with _workspace() as (base, output):
        phase = _phase("focused-suites", handles_closed=False)
        phase.pop("runOwnedReport", None)
        helper = _helper(module, [_owned(), _owned(), _owned()],
                         _child_report(phases=[phase]))
        _install(module, helper)
        _run(module, output)
        report = _read(output)
        check(report["inner"]["passed"] is False, report["inner"])
        reasons = " ".join(report["inner"].get("reasons") or [])
        check("no handle-closure evidence" in reasons, reasons)
        # Managed root is confirmed, so it still releases with a FAIL result.
        check(report["result"] == "FAIL_OR_INCONCLUSIVE", report["result"])
        check(report["release"] == "RELEASE", report["release"])


def check_drift_before_publication_fails_but_releases(module) -> None:
    with _workspace() as (base, output):
        helper = _helper(module, [_owned(), _owned(), _owned()], _child_report())
        _install(module, helper)
        calls = {"n": 0}
        original = module.identities

        def drifting(root, names):
            calls["n"] += 1
            digest = "a" * 64 if calls["n"] == 1 else "b" * 64
            return {name: {"bytes": 1, "sha256": digest} for name in names}

        module.identities = drifting
        try:
            code = _run(module, output)
        finally:
            module.identities = original
        report = _read(output)
        check(calls["n"] >= 2, calls)
        check(report["ownedDrift"] is True, report["ownedDrift"])
        check(report["verificationRoot"]["confirmed"] is True, report)
        check(report["result"] == "FAIL_OR_INCONCLUSIVE", report["result"])
        check(report["release"] == "RELEASE", report["release"])
        check(report["publication"]["claimedStatus"] == "RELEASE", report)
        text = _published(output, "release-message.md")
        check(text.startswith("RELEASE NEWGRANT20261026"), text)
        check("drift" in text.lower(), text)
        check("no handoff" not in text, text)
        check(code != 0, code)


def check_identity_capture_failure_fails_but_releases(module) -> None:
    """A capture failure must publish FAIL, never PASS, and still release.

    Root-found defect: the capture branch appended an error but never downgraded
    the inner verification, so `final_status()` still saw `inner.passed is True`
    and `publish_final()` composed `status=PASS` while `persist()` recorded
    `FAIL_OR_INCONCLUSIVE`.
    """
    with _workspace() as (base, output):
        helper = _helper(module, [_owned(), _owned(), _owned()], _child_report())
        _install(module, helper)
        calls = {"n": 0}
        original = module.identities

        def flaky(root, names):
            calls["n"] += 1
            if calls["n"] >= 2:
                raise OSError("identity capture unavailable")
            return original(root, names)

        module.identities = flaky
        try:
            code = _run(module, output)
        finally:
            module.identities = original
        report = _read(output)
        check(calls["n"] >= 2, calls)
        # The managed child root really closed, so ownership is handed over.
        check(report["verificationRoot"]["confirmed"] is True, report)
        check(report["release"] == "RELEASE", report["release"])
        check(report["publication"]["delivered"] is True, report["publication"])
        check(report["publication"]["claimedStatus"] == "RELEASE",
              report["publication"])
        check(report["identityCapture"]["ok"] is False,
              report["identityCapture"])
        # The durable report and the delivered message must both say FAIL.
        check(report["result"] == "FAIL_OR_INCONCLUSIVE", report["result"])
        check(report["inner"]["passed"] is False, report["inner"])
        reasons = " ".join(report["inner"].get("reasons") or [])
        check("identity capture" in reasons.lower(), reasons)
        text = _published(output, "release-message.md")
        check(text.startswith("RELEASE "), text[:60])
        check("status=FAIL_OR_INCONCLUSIVE" in text, text)
        check("status=PASS" not in text, text)
        check("no handoff" not in text, text)
        check("recorded verification failure" in text, text)
        summary = _published(output, "window-summary.md")
        check("result=FAIL_OR_INCONCLUSIVE" in summary, summary)
        check(code != 0, code)
    # Static guard: both pre-publication outcomes share the same downgrade.
    source = (HERE / "run_python_granted_window.py").read_text(encoding="utf-8")
    check("def downgrade_verification(self" in source,
          "no shared verification downgrade exists")
    check(source.count("self.downgrade_verification(") == 2,
          "drift and capture failure must both downgrade the verification")


def check_identities_freeze_both_layers(module) -> None:
    names = set(module.OWNED_IDENTITIES)
    inner = ".trellis/tasks/10-22-python-offline-debugger/research/fixtures/run_python_host.py"
    outer = ".trellis/tasks/10-22-python-offline-debugger/research/fixtures/run_python_granted_window.py"
    check(inner in names, "inner runner missing from the source freeze")
    check(outer in names, "outer observer missing from the source freeze")
    check("tool/python_owned_process.py" in names, "owned helper missing")
    frozen = module.identities(ROOT, module.OWNED_IDENTITIES)
    for name in (inner, outer):
        digest = frozen[name]["sha256"]
        check(len(digest) == 64 and frozen[name]["bytes"] > 0,
              (name, frozen[name]))


def check_freeze_decided_before_publication(module) -> None:
    source = (HERE / "run_python_granted_window.py").read_text(encoding="utf-8")
    publish_final = source.split("    def publish_final(self)")[1]
    publish_final = publish_final.split("    def persist(self)")[0]
    persist = source.split("    def persist(self)")[1]
    persist = persist.split("    def summary(self)")[0]
    check("self.recheck_freeze()" in publish_final,
          "the freeze check is missing before publication")
    check("recheck_freeze" not in persist,
          "persist re-reads the freeze after publication, which could make the "
          "local report contradict the delivered message")
    check(publish_final.index("self.recheck_freeze()")
          < publish_final.index("text = ("),
          "the freeze check runs after the status text is composed")
    check("recheck_freeze" not in source.split("def main(")[1],
          "main re-checks the freeze outside publish_final")


def check_report_and_message_agree(module) -> None:
    cases = (
        ("pass", [_owned(), _owned(), _owned()], _child_report()),
        ("failed", [_owned(), _owned(exit_code=1), _owned()],
         _child_report(result="FAIL_OR_INCONCLUSIVE")),
    )
    for label, reports, child_report in cases:
        with _workspace() as (base, output):
            helper = _helper(module, reports, child_report)
            _install(module, helper)
            code = _run(module, output)
            report = _read(output)
            summary = _published(output, "window-summary.md")
            message = _published(output, "release-message.md")
            check(report["release"] == "RELEASE", (label, report["release"]))
            check(message.startswith("RELEASE "), (label, message[:48]))
            check(summary.startswith("RELEASE "), (label, summary[:48]))
            check(f"result={report['result']}" in summary,
                  (label, report["result"], summary))
            check("no handoff" not in message, (label, message))
            check(code == (0 if report["result"] == "PASS" else 1),
                  (label, report["result"], code))
            # Publication text and operator summary must not collide.
            check((output / "release-message.md").exists(), label)
            check(message != summary, label)


def check_fake_helper_has_no_real_fallback(module) -> None:
    """The double must reject an unknown command immediately, with no fallback."""
    source = (HERE / "verify_run_python_granted_window.py").read_text(encoding="utf-8")
    body = source.split("class _FakeHelper:")[1]
    body = body.split("@contextlib.contextmanager")[0]
    check("Unrecognised command" in body,
          "the fake helper has no rejection for an unknown command")
    check("raise RuntimeError" in body,
          "the fake helper does not raise on an unknown command")
    check("return _owned()" not in body,
          "the fake helper still has a silent real-report fallback")
    helper = _FakeHelper([], child_report=None, child_marker="inner.py")
    try:
        helper.run_owned(["node", "trellis.js", "channel", "send", "x"])
    except RuntimeError:
        pass
    else:
        raise AssertionError("The fake helper accepted an unknown command")
    check(helper.calls, "the fake helper did not record the rejected command")
    # An unscripted but recognised command must also raise, not invent a report.
    helper = _FakeHelper([], child_report=None, child_marker="inner.py")
    try:
        helper.run_owned(["node", "trellis.js", "x", "ack-message.md"])
    except RuntimeError:
        pass
    else:
        raise AssertionError("The fake helper invented an unscripted report")


def check_argument_guards_install_doubles(module) -> None:
    """Static guard: the first check must install doubles before module.main."""
    source = (HERE / "verify_run_python_granted_window.py").read_text(encoding="utf-8")
    body = source.split("def check_argument_guards(module) -> None:")[1]
    body = body.split("\ndef ", 1)[0]
    install_at = body.find("_install(module")
    main_at = body.find("module.main(")
    check(install_at != -1, "check_argument_guards never installs doubles")
    check(main_at != -1, "check_argument_guards never calls module.main")
    check(install_at < main_at,
          "check_argument_guards calls module.main before installing doubles")
    # Every other check that runs the window must install first too.
    for name in ("check_ack_failure_blocks_child", "check_success_single_window",
                 "check_failed_verification_releases",
                 "check_over_budget_child_fails_but_releases",
                 "check_wall_clock_over_budget_fails_but_releases",
                 "check_missing_child_report_is_fail_but_release",
                 "check_phase_closure_evidence_required",
                 "check_drift_before_publication_fails_but_releases",
                 "check_consumer_tests_threaded_to_child"):
        block = source.split(f"def {name}(module) -> None:")[1]
        block = block.split("\ndef ", 1)[0]
        check("_install(module" in block or "_run_failed_clean" in block,
              f"{name} runs the window without installing doubles")


def check_widened_guard_still_zero_io(module) -> None:
    """A deliberately widened guard must still reach only doubles.

    This is the C607-NEG negative control: the platform/budget guards are
    replaced with an accept-everything version, so the window really proceeds.
    The strict fake helper then refuses the unscripted ACK, and the fake
    publisher is the only publisher, proving zero real I/O.
    """
    with _workspace() as (base, output):
        helper = _helper(module, [], None)
        used = {"publisher": 0}

        def fake_publisher(args, used=used):
            used["publisher"] += 1
            return ["node", "trellis.js"]

        def fake_loader(root, helper=helper):
            return helper

        module.load_owned_helper = fake_loader
        module.resolve_publisher = fake_publisher
        original_validate = module.validate

        def widened(parser, args):
            # Simulate a regressed guard: nothing is rejected any more.
            if getattr(args, "scope", None):
                args.scope = tuple(args.scope)
            return None

        module.validate = widened
        try:
            code = module.main(["--grant", "G1",
                                "--next-owner", "c-coordinator",
                                "--output", str(output)])
        finally:
            module.validate = original_validate
        check(used["publisher"] == 1,
              f"the widened guard did not use the fake publisher: {used}")
        check(module.load_owned_helper is fake_loader,
              "the widened guard replaced the fake loader")
        check(module.resolve_publisher is fake_publisher,
              "the widened guard replaced the fake publisher")
        check(code != 0, f"a widened guard reported success: {code}")
        check(helper.calls, "the widened guard issued no command at all")
        check(helper.child_calls == 0, "a widened guard started the child")
        check(len(helper.publish_calls()) <= 1,
              f"a widened guard published more than the ACK: {helper.calls}")
        report = _read(output)
        check(report["ack"]["delivered"] is False, report["ack"])
        check(report["verificationRoot"]["started"] is False,
              report["verificationRoot"])
        check(report["publication"]["delivered"] is False,
              report["publication"])
        check(report["release"] == "HOLD_UNRELEASED", report["release"])
        check(not (output / "release-message.md").exists(),
              "a widened guard reached a final publication")


def check_refuses_non_windows(module) -> None:
    source = (HERE / "verify_run_python_granted_window.py").read_text(encoding="utf-8")
    main_body = source.rsplit("def main() -> int:", 1)[-1]
    platform_at = main_body.find('if os.name != "nt"')
    optimize_at = main_body.find("sys.flags.optimize")
    check(platform_at != -1,
          "the verifier does not refuse a non-Windows host")
    check(optimize_at != -1, "the verifier does not refuse optimized runs")
    check(platform_at < optimize_at,
          "the platform refusal must run before the optimized check")
    check("return 2" in main_body[platform_at:optimize_at],
          "the non-Windows refusal does not exit nonzero")
    check(os.name == "nt", "this verifier is only meaningful on Windows")


def check_construction_failure_is_a_clear_error(module) -> None:
    """A bad root or a missing helper is a parser error, not a traceback."""
    source = (HERE / "run_python_granted_window.py").read_text(encoding="utf-8")
    check("rmtree" not in source,
          "the wrapper deletes paths recursively on a construction failure")
    check("except (WindowFailure, OSError) as error:" in source,
          "construction failures are not caught")
    check('parser.error(f"Cannot open the window' in source,
          "a construction failure is not reported through parser.error")
    # A root that does not exist must fail cleanly, before any evidence exists.
    with _workspace() as (base, output):
        strict = _helper(module, [], None)
        _install(module, strict)
        try:
            module.main(["--grant", "G1", "--next-owner", "c-coordinator",
                         "--root", str(base / "no-such-root"),
                         "--output", str(output)])
        except SystemExit as exit_code:
            check(exit_code.code == 2,
                  f"a missing root exited {exit_code.code}, not 2")
        else:
            raise AssertionError("A root that does not exist was accepted")
        check(not output.exists(),
              "a missing root left an evidence directory behind")
        check(not strict.calls, "a missing root reached run_owned")
    # A missing helper module must fail the same way, with no directory.
    with _workspace() as (base, output):
        original = module.load_owned_helper

        def broken(root):
            raise FileNotFoundError("python_owned_process.py is missing")

        module.load_owned_helper = broken
        try:
            try:
                module.main(["--grant", "G1",
                             "--next-owner", "c-coordinator",
                             "--output", str(output)])
            except SystemExit as exit_code:
                check(exit_code.code == 2,
                      f"a missing helper exited {exit_code.code}, not 2")
            else:
                raise AssertionError("A missing helper was accepted")
        finally:
            module.load_owned_helper = original
        check(not output.exists(),
              "a missing helper left an evidence directory behind")


def check_readiness_command_is_ready(module) -> None:
    """The prepared readiness command must be accepted and correctly shaped."""
    grant = "READINESS20261026"
    with _workspace() as (base, output):
        helper = _helper(module, [_owned(), _owned(), _owned()], _child_report())
        _install(module, helper)
        argv = ["--grant", grant, "--next-owner", "c-coordinator",
                "--output", str(output), *READINESS_FLAGS]
        code = module.main(argv)
        report = _read(output)
        check(code == 0, f"readiness command was rejected: {report['errors']}")
        check(report["result"] == "PASS", report["result"])
        budget = report["budget"]
        reserved = (budget["ackSeconds"] + budget["innerSeconds"]
                    + budget["outerCleanupSeconds"] + budget["publishSeconds"]
                    + budget["marginSeconds"])
        check(reserved == 180.0, (reserved, budget))
        child_wall = (budget["innerPlanSeconds"]
                      + budget["maxInnerPhases"] * budget["childCleanupSeconds"])
        check(child_wall <= budget["innerSeconds"], (child_wall, budget))
        check(budget["innerSeconds"] <= module.INNER_SECONDS_CEILING, budget)
        check(budget["totalSeconds"] <= module.TOTAL_MAX, budget)
        children = [call for call in helper.calls
                    if str(module.INNER_PATH) in " ".join(call)]
        check(len(children) == 1, children)
        child = children[0]
        joined = " ".join(child)
        for expected in ("--grant", grant, "--next-owner", "c-coordinator",
                         "--plan-seconds", "123.0", "--cleanup-seconds", "5.0",
                         "--control-seconds", "60.0",
                         "--include-named-workspace"):
            check(expected in child, (expected, joined))
        check("--controls-report" not in joined,
              "the readiness command reuses a prior controls report")
        check("--control-only" not in joined,
              "the readiness command is control-only")
        for absent in ("--scope",):
            check(absent not in joined,
                  "the readiness command overrides the default scoped analyze")
        check("--include-consumer-tests" not in joined,
              "the default readiness command injects the consumer suites")
        summary = _published(output, "window-summary.md")
        check(summary.startswith("RELEASE " + grant), summary)


def check_consumer_tests_threaded_to_child(module) -> None:
    """The consumer flag reaches the child; the default window never adds it."""
    with _workspace() as (base, output):
        helper = _helper(module, [_owned(), _owned(), _owned()], _child_report())
        _install(module, helper)
        code = _run(module, output, "--include-consumer-tests")
        report = _read(output)
        check(code == 0, f"{code}: {report['errors']}")
        children = [" ".join(call) for call in helper.calls
                    if str(module.INNER_PATH) in " ".join(call)]
        check(len(children) == 1, children)
        check("--include-consumer-tests" in children[0],
              f"the consumer flag did not reach the child: {children[0]}")
        check("--include-named-workspace" not in children[0],
              f"the consumer flag implied the named workspace: {children[0]}")
    with _workspace() as (base, output):
        helper = _helper(module, [_owned(), _owned(), _owned()], _child_report())
        _install(module, helper)
        code = _run(module, output)
        report = _read(output)
        check(code == 0, f"{code}: {report['errors']}")
        children = [" ".join(call) for call in helper.calls
                    if str(module.INNER_PATH) in " ".join(call)]
        check(len(children) == 1, children)
        check("--include-consumer-tests" not in children[0],
              f"the consumer suites ran by default: {children[0]}")


def check_readiness_controls_precede_suites(module) -> None:
    """Controls run first; the five merged suites then the scoped analyze."""
    host = module.INNER_PATH.read_text(encoding="utf-8")
    controls_at = host.find("run_controls(helper, args, root, output, started)")
    suites_at = host.find('"focused-suites"')
    analyze_at = host.find('"scope-analysis"')
    check(controls_at != -1 and suites_at != -1 and analyze_at != -1,
          "the host phase names changed")
    check(controls_at < suites_at < analyze_at,
          "controls must run before the merged suites and the scoped analyze")
    gate = host.find('if not controls.get("passed")')
    check(gate != -1 and gate < suites_at,
          "the merged suites are not gated on a passed controls phase")
    focused = host.split("FOCUSED_SUITES = (")[1].split(")")[0]
    count = focused.count(".dart")
    check(count == 4, f"focused suite count changed: {count}")
    consumers = host.split("CONSUMER_SUITES = (")[1].split(")")[0]
    consumer_count = consumers.count(".dart")
    check(consumer_count == 2,
          f"consumer suite count changed: {consumer_count}")
    check("test/python_tools_page_test.dart" in consumers,
          "the tools-page consumer suite is missing")
    check("test/python_highlighting_test.dart" in consumers,
          "the highlighting consumer suite is missing")
    check("include_consumer_tests" in host, "the consumer flag is missing")
    check("NAMED_WORKSPACE_SUITE" in host, "the named workspace suite is missing")
    check("include_named_workspace" in host, "the named workspace flag is missing")
    check('return [args.dart, "analyze"' in host, "the scoped analyze changed")


def check_optimized_run_is_refused(module) -> None:
    source = (HERE / "run_python_granted_window.py").read_text(encoding="utf-8")
    check("sys.flags.optimize" in source, "no optimized-run guard in source")
    check("raise WindowFailure" in source, "always-on require() missing")
    check("\n    assert " not in source, "bare assert found in the wrapper")


def main() -> int:
    if os.name != "nt":
        print("Refusing to verify: every guard under test is Windows-only, so a "
              "non-Windows PASS would be vacuous", file=sys.stderr, flush=True)
        return 2
    if sys.flags.optimize:
        print("Refusing to verify under -O: checks would be stripped",
              file=sys.stderr, flush=True)
        return 2
    module = load_window()
    checks = (
        check_argument_guards,
        check_ack_failure_blocks_child,
        check_root_exit_zero_with_live_job_no_final_publish,
        check_root_not_terminal_no_final_publish,
        check_handles_not_closed_no_final_publish,
        check_missing_root_identity_no_final_publish,
        check_child_never_publishes,
        check_success_single_window,
        check_failed_verification_releases,
        check_failed_report_matches_global_message,
        check_over_budget_child_fails_but_releases,
        check_wall_clock_over_budget_fails_but_releases,
        check_missing_child_report_is_fail_but_release,
        check_phase_closure_evidence_required,
        check_drift_before_publication_fails_but_releases,
        check_identity_capture_failure_fails_but_releases,
        check_identities_freeze_both_layers,
        check_freeze_decided_before_publication,
        check_report_and_message_agree,
        check_fake_helper_has_no_real_fallback,
        check_argument_guards_install_doubles,
        check_widened_guard_still_zero_io,
        check_refuses_non_windows,
        check_construction_failure_is_a_clear_error,
        check_readiness_command_is_ready,
        check_consumer_tests_threaded_to_child,
        check_readiness_controls_precede_suites,
        check_optimized_run_is_refused,
    )
    for check_function in checks:
        check_function(module)
        print(f"SYNTHETIC_PASS {check_function.__name__}", flush=True)
    print("SYNTHETIC_VERIFY_PASS no child process, publisher or channel call was made",
          flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
