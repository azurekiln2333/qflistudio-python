"""Coordinating observer for one bounded Python granted window.

Global evidence JSON622, Java640/641 and Note651 forbid a verification wrapper
from publishing a final RELEASE while it is itself still alive. The earlier
version imported and called the inner runner in-process, so the verifying
process published its own release. This version is an observer only:

1. It publishes the ACK.
2. It starts an independent verification child, `run_python_host.py`, through
   `tool/python_owned_process.py run_owned`, keeping the exact verification
   root HANDLE, creation FILETIME and Job.
3. The child writes only its local report; it never publishes a final status.
4. `run_owned` returns only after that exact child root is terminal, its
   private Job ActiveProcesses == 0 and its handles are closed.
5. Only then does the observer reconcile the child report and publish the final
   RELEASE / HOLD.

The observer is a coordinator and never claims it has itself exited. It records
`observerPid` and the exact managed-root identity, so the handoff describes the
child verification root that really terminated, not the observer.

Contracts:

* `--grant` must be a NEW nonempty named grant; blank, `REPLACE_` and any
  `--used-grant` replay are rejected. `--next-owner` is mandatory (documented
  successor `c-coordinator`) and must differ from the sender.
* The whole window is at most 180 s. The managed-root timeout, its cleanup
  budget and the two publications are reserved before the child starts. The
  default managed-root timeout is 120 s.
* `--include-named-workspace` and `--include-consumer-tests` are threaded to the
  child unchanged. The consumer flag only adds the inner runner's two bound
  consumer suites to its single merged call; it injects no arbitrary suite and
  no command, and the default focused set is unaffected when it is absent.
* Verification result and resource release stay separate. A failed check, a
  source drift or an over-budget child is FAIL, but it still RELEASEs to the
  next owner when the managed verification root really closed and the
  publication was verified. Only an unproven managed root is HOLD, and only
  then are handles retained.
* On HOLD the observer publishes nothing final and `run_owned` keeps observing;
  this file never kills a looked-up PID and never abandons handles.
* Import starts no process, writes no file and calls no Windows API.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import shutil
import sys
import time
from datetime import datetime, timezone

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
INNER_PATH = HERE / "run_python_host.py"
CHANNEL = "qfli-core-release-sync"
SENDER = "python-offline-1022"
TOTAL_MAX = 180.0
INNER_SECONDS_CEILING = 145.0
OWNED_IDENTITIES = (
    "tool/python_owned_process.py",
    ".trellis/tasks/10-22-python-offline-debugger/research/fixtures/run_python_host.py",
    ".trellis/tasks/10-22-python-offline-debugger/research/fixtures/verify_run_python_host.py",
    ".trellis/tasks/10-22-python-offline-debugger/research/fixtures/run_python_granted_window.py",
    ".trellis/tasks/10-22-python-offline-debugger/research/fixtures/verify_run_python_granted_window.py",
    "tool/python_debugger_ohos_audit.dart",
    "test/python_debugger_audit_test.dart",
    "test/python_owned_process_control_test.py",
)


class WindowFailure(RuntimeError):
    """A bounded-window contract violation; the observer must not claim success."""


def require(condition: object, message: str) -> None:
    """Always-on acceptance check: never a bare assert, never stripped by -O."""
    if not condition:
        raise WindowFailure(message)


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def identities(root: Path, names: tuple[str, ...]) -> dict:
    result = {}
    for name in names:
        path = (root / name).resolve(strict=True)
        data = path.read_bytes()
        result[name] = {"bytes": len(data),
                        "sha256": hashlib.sha256(data).hexdigest()}
    return result


def _load_module(root: Path, relative: str, name: str, attribute: str):
    path = (root / relative).resolve(strict=True)
    spec = importlib.util.spec_from_file_location(name, path)
    require(spec is not None and spec.loader is not None,
            f"Cannot import {relative}")
    module = importlib.util.module_from_spec(spec)
    previous_path, previous_bytecode = sys.path[:], sys.dont_write_bytecode
    try:
        sys.path.insert(0, str(path.parent))
        sys.dont_write_bytecode = True
        spec.loader.exec_module(module)
    finally:
        sys.path[:] = previous_path
        sys.dont_write_bytecode = previous_bytecode
    require(hasattr(module, attribute), f"{relative} does not expose {attribute}")
    return module


def load_owned_helper(root: Path):
    """Import the shared owned-process helper without running its CLI."""
    return _load_module(root, "tool/python_owned_process.py",
                        "_qfli_python_owned_process_observer", "run_owned")


def resolve_publisher(args) -> list[str]:
    """Resolve the installed Trellis CLI so a publisher can be owned, not shelled."""
    node = args.node or shutil.which("node.exe") or shutil.which("node")
    require(node is not None, "node is required to publish; manual relay needed")
    if args.trellis_entry is not None:
        entry = Path(args.trellis_entry).resolve(strict=True)
    else:
        shim = (shutil.which("trellis.cmd") or shutil.which("trellis.ps1")
                or shutil.which("trellis"))
        require(shim is not None,
                "Installed Trellis shim missing; manual relay required")
        entry = (Path(shim).parent
                 / "node_modules/@mindfoldhq/trellis/bin/trellis.js").resolve()
    require(entry.is_file(), "Installed Trellis CLI entry missing; manual relay required")
    return [str(Path(node).resolve()), str(entry)]


def owned_confirmed(report: dict) -> bool:
    """A managed root counts as released only with exact, complete evidence.

    A zero root exit alone is never enough: the exact root must be terminal, the
    private Job must have zero active processes, handles must be closed, and the
    exact HANDLE / FILETIME / Job identity must be present.
    """
    process = report.get("process") or {}
    return (report.get("state") == "FINISHED"
            and report.get("release") == "RELEASE"
            and report.get("cleanupConfirmed") is True
            and report.get("handlesRetained") is False
            and process.get("terminal") is True
            and process.get("jobActiveProcesses") == 0
            and process.get("handlesClosed") is True
            and process.get("pid") is not None
            and process.get("creationFiletime100ns") is not None
            and process.get("processHandleDecimal") is not None
            and process.get("jobHandleDecimal") is not None)


def _phase_cleanup_reasons(phase: dict) -> list[str]:
    """Cleanup evidence for one executed child phase; never trusts one field."""
    name = phase.get("name")
    problems: list[str] = []
    if phase.get("cleanupConfirmed") is not True:
        problems.append("cleanupConfirmed is not true")
    if phase.get("handlesRetained") is not False:
        problems.append("handlesRetained is not false")
    if phase.get("release") != "RELEASE":
        problems.append(f"release={phase.get('release')}")
    if phase.get("rootTerminal") is not True:
        problems.append(f"rootTerminal={phase.get('rootTerminal')}")
    if phase.get("jobActiveProcesses") != 0:
        problems.append(f"jobActiveProcesses={phase.get('jobActiveProcesses')}")
    closed = phase.get("handlesClosed") is True
    if not closed:
        source = phase.get("runOwnedReport")
        if isinstance(source, str) and source:
            try:
                durable = json.loads(Path(source).read_text(encoding="utf-8"))
                process = (durable or {}).get("process") or {}
                closed = (isinstance(durable, dict)
                          and durable.get("cleanupConfirmed") is True
                          and durable.get("handlesRetained") is False
                          and durable.get("release") == "RELEASE"
                          and process.get("terminal") is True
                          and process.get("jobActiveProcesses") == 0
                          and process.get("handlesClosed") is True)
            except BaseException:
                closed = False
    if not closed:
        problems.append("no handle-closure evidence")
    return [f"{name}: {problem}" for problem in problems]


def verify_inner_report(report: dict) -> tuple[bool, bool, list[str]]:
    """Return (child_cleanup, child_passed, reasons) for the verification child.

    The child report is verification evidence only. The authoritative release
    decision uses the managed child root from `run_owned`, not this report.
    """
    require(isinstance(report, dict), "Inner report must be a JSON object")
    phases = report.get("phases") or []
    require(isinstance(phases, list), "Inner report phases must be a list")
    executed = [phase for phase in phases
                if isinstance(phase, dict) and phase.get("result") != "SKIPPED"]
    cleanup_reasons: list[str] = []
    for phase in executed:
        cleanup_reasons.extend(_phase_cleanup_reasons(phase))
    cleanup = bool(executed) and not cleanup_reasons

    verification: list[str] = []
    drift = report.get("auditInputDrift") or {}
    drifted = [key for key in ("product", "shared") if drift.get(key)]
    if report.get("ownedDrift"):
        verification.append("inner owned-source drift")
    if drifted:
        verification.append(f"inner audit-input drift: {drifted}")
    if report.get("withinPlanSeconds") is not True:
        verification.append("inner exceeded its plan seconds")
    if cleanup and report.get("release") != "RELEASE":
        verification.append(f"inner release={report.get('release')}")
    if report.get("result") != "PASS":
        verification.append(f"inner result={report.get('result')}")
    if report.get("errors"):
        verification.append(f"inner errors={report.get('errors')}")
    passed = cleanup and not verification
    return cleanup, passed, cleanup_reasons + verification


def root_identity_line(root: dict) -> str:
    """Exact managed verification-root identity, never the observer's own."""
    return (f"verification root PID={root.get('rootPid')} "
            f"HANDLE={root.get('processHandle')} "
            f"FILETIME={root.get('creationFiletime100ns')} "
            f"Job={root.get('jobHandle')} terminal={root.get('terminal')} "
            f"jobActive={root.get('jobActiveProcesses')} "
            f"handlesClosed={root.get('handlesClosed')} "
            f"exit={root.get('exitCode')} timedOut={root.get('timedOut')}")


def validate(parser: argparse.ArgumentParser, args) -> None:
    """Reject placeholders, replays and budgets before any process or file."""
    def finite_positive(name: str, value: float) -> None:
        if not math.isfinite(value) or value <= 0:
            parser.error(f"{name} must be finite and positive")

    if os.name != "nt":
        parser.error("Windows only")
    grant = args.grant.strip()
    next_owner = args.next_owner.strip()
    if not grant or not next_owner:
        parser.error("A NEW nonempty grant and explicit next owner are required")
    if grant.startswith("REPLACE_") or next_owner.startswith("REPLACE_"):
        parser.error("REPLACE_ placeholders are not a grant or a successor")
    if grant in {value.strip() for value in args.used_grant}:
        parser.error(f"Grant {grant!r} was already consumed; a NEW name is required")
    if next_owner == args.sender.strip():
        parser.error("Next owner must differ from the publishing sender")
    finite_positive("--total-seconds", args.total_seconds)
    if args.total_seconds > TOTAL_MAX:
        parser.error(f"--total-seconds must not exceed {TOTAL_MAX:g}")
    finite_positive("--inner-seconds", args.inner_seconds)
    if args.inner_seconds > INNER_SECONDS_CEILING:
        parser.error(f"--inner-seconds must not exceed {INNER_SECONDS_CEILING:g}")
    for name in ("--ack-seconds", "--publish-seconds", "--margin-seconds",
                 "--inner-plan-seconds", "--child-cleanup-seconds",
                 "--outer-cleanup-seconds", "--control-seconds",
                 "--min-phase-seconds"):
        finite_positive(name, getattr(args, name.lstrip("-").replace("-", "_")))
    if args.max_inner_phases < 1:
        parser.error("--max-inner-phases must be at least 1")
    child_wall = (args.inner_plan_seconds
                  + args.max_inner_phases * args.child_cleanup_seconds)
    if child_wall > args.inner_seconds:
        parser.error(
            f"Child budget does not fit: plan {args.inner_plan_seconds:g} + "
            f"phases*cleanup {args.max_inner_phases * args.child_cleanup_seconds:g} "
            f"exceeds the managed-root timeout {args.inner_seconds:g}s")
    reserved = (args.ack_seconds + args.inner_seconds
                + args.outer_cleanup_seconds + args.publish_seconds
                + args.margin_seconds)
    if reserved > args.total_seconds:
        parser.error(
            f"Window does not fit: ack {args.ack_seconds:g} + inner "
            f"{args.inner_seconds:g} + outer cleanup "
            f"{args.outer_cleanup_seconds:g} + publish {args.publish_seconds:g} "
            f"+ margin {args.margin_seconds:g} = {reserved:g}s exceeds "
            f"{args.total_seconds:g}s")
    args.scope = tuple(args.scope) if args.scope else None


class GrantedWindow:
    """Observer that coordinates a separate managed verification child."""

    def __init__(self, args):
        self.args = args
        self.started = time.monotonic()
        self.deadline = self.started + args.total_seconds
        self.root = args.root.resolve(strict=True)
        self.output = args.output.resolve()
        require(self.output.is_relative_to(self.root / "build"),
                "Evidence output must live under <root>/build")
        require(not self.output.exists(), "Evidence output must not exist")
        self.grant = args.grant.strip()
        self.next_owner = args.next_owner.strip()
        self.channel = args.channel
        self.sender = args.sender
        # Resolve both collaborators before creating evidence. A missing root,
        # helper or Trellis entry then leaves no partial directory behind, and
        # reports through parser.error instead of a traceback.
        self.helper = load_owned_helper(self.root)
        self.publisher = resolve_publisher(args)
        self.output.mkdir(parents=True, exist_ok=False)
        self.observer_pid = os.getpid()
        self.report = {
            "schemaVersion": 1, "mode": "GRANTED_WINDOW_OBSERVER",
            "grant": self.grant, "nextOwner": self.next_owner,
            "sender": self.sender, "channel": self.channel,
            "outerToolHandle": args.outer_handle,
            "observerPid": self.observer_pid, "root": str(self.root),
            "output": str(self.output), "startedAt": now(),
            "budget": {
                "totalSeconds": args.total_seconds,
                "ackSeconds": args.ack_seconds,
                "innerSeconds": args.inner_seconds,
                "innerPlanSeconds": args.inner_plan_seconds,
                "childCleanupSeconds": args.child_cleanup_seconds,
                "outerCleanupSeconds": args.outer_cleanup_seconds,
                "publishSeconds": args.publish_seconds,
                "marginSeconds": args.margin_seconds,
                "maxInnerPhases": args.max_inner_phases,
                "innerSecondsCeiling": INNER_SECONDS_CEILING,
            },
            "ack": None, "verificationRoot": None, "inner": None,
            "publication": None, "errors": [],
            "observerRole": (
                "Coordinator only. Verification ran in the separate managed "
                "child recorded under verificationRoot. The observer publishes "
                "after that child root is terminal, Job is 0 and handles are "
                "closed, and never claims it has itself exited."),
            "claims": (
                "Focused host checks only; no native build, HAP, signing, WSL "
                "or device gate. ACK, child verification and final publication "
                "share one bounded invocation; the child never publishes."),
        }

    def remaining(self) -> float:
        return self.deadline - time.monotonic()

    def child_command(self) -> list[str]:
        args = self.args
        inner_output = self.output / "inner"
        require(not inner_output.exists(), "Child evidence directory must not exist")
        command = [
            args.python, str(INNER_PATH),
            "--grant", self.grant, "--next-owner", self.next_owner,
            "--root", str(self.root), "--output", str(inner_output),
            "--plan-seconds", repr(float(args.inner_plan_seconds)),
            "--cleanup-seconds", repr(float(args.child_cleanup_seconds)),
            "--control-seconds", repr(float(args.control_seconds)),
            "--min-phase-seconds", repr(float(args.min_phase_seconds)),
            "--python", args.python, "--flutter", args.flutter,
            "--dart", args.dart,
        ]
        if args.control_only:
            command.append("--control-only")
        if args.controls_report is not None:
            command.extend(["--controls-report", str(args.controls_report)])
        if args.include_named_workspace:
            command.append("--include-named-workspace")
        if args.include_consumer_tests:
            command.append("--include-consumer-tests")
        for item in args.scope or ():
            command.extend(["--scope", str(item)])
        return command

    def publish(self, text: str, phase: str, seconds: float) -> dict:
        entry = {"phase": phase, "startedAt": now(), "seconds": seconds}
        message_path = self.output / f"{phase}-message.md"
        message_path.write_text(
            text if text.endswith("\n") else text + "\n", encoding="utf-8")
        entry["messagePath"] = str(message_path)
        command = [*self.publisher, "channel", "send", self.channel,
                   "--scope", "global", "--as", self.sender,
                   "--to", self.next_owner, "--text-file", str(message_path)]
        entry["command"] = command
        log_path = self.output / f"{phase}.combined.log"
        report_path = self.output / f"{phase}.report.json"
        try:
            report = self.helper.run_owned(
                command, timeout_seconds=seconds,
                cleanup_seconds=self.args.child_cleanup_seconds,
                cwd=self.root, log_path=log_path, report_path=report_path)
            entry["runOwnedReport"] = str(report_path)
            entry.update(
                state=report.get("state"), release=report.get("release"),
                exitCode=report.get("exitCode"),
                timedOut=report.get("timedOut"),
                cleanupConfirmed=report.get("cleanupConfirmed"),
                handlesRetained=report.get("handlesRetained"))
            process = report.get("process") or {}
            entry["rootTerminal"] = process.get("terminal")
            entry["jobActiveProcesses"] = process.get("jobActiveProcesses")
            entry["handlesClosed"] = process.get("handlesClosed")
            entry["delivered"] = bool(owned_confirmed(report)
                                      and report.get("exitCode") == 0
                                      and report.get("timedOut") is False)
        except BaseException as error:
            entry["error"] = f"{type(error).__name__}: {error}"
            entry["delivered"] = False
        entry["finishedAt"] = now()
        return entry

    def run_child(self) -> dict:
        """Start the separate verification child and keep its exact root."""
        args = self.args
        command = self.child_command()
        entry = {"command": command, "startedAt": now(),
                 "publication": "NOT_ATTEMPTED",
                 "reportPath": str(self.output / "inner" / "report.json")}
        log_path = self.output / "verification-child.combined.log"
        owned_path = self.output / "verification-child.report.json"
        entry["runOwnedReport"] = str(owned_path)
        try:
            owned = self.helper.run_owned(
                command, timeout_seconds=args.inner_seconds,
                cleanup_seconds=args.outer_cleanup_seconds,
                cwd=self.root, log_path=log_path, report_path=owned_path)
            process = owned.get("process") or {}
            entry.update(
                state=owned.get("state"), release=owned.get("release"),
                exitCode=owned.get("exitCode"),
                timedOut=owned.get("timedOut"),
                cleanupConfirmed=owned.get("cleanupConfirmed"),
                handlesRetained=owned.get("handlesRetained"),
                rootPid=process.get("pid"),
                creationFiletime100ns=process.get("creationFiletime100ns"),
                processHandle=process.get("processHandleDecimal"),
                jobHandle=process.get("jobHandleDecimal"),
                terminal=process.get("terminal"),
                jobActiveProcesses=process.get("jobActiveProcesses"),
                handlesClosed=process.get("handlesClosed"))
            entry["confirmed"] = owned_confirmed(owned)
            entry["ownedErrors"] = list(owned.get("errors") or [])
            if entry["confirmed"]:
                entry["terminalOrder"] = (
                    "root terminal, Job ActiveProcesses 0, handles closed, then "
                    "final publication")
        except BaseException as error:
            entry["error"] = f"{type(error).__name__}: {error}"
            entry["confirmed"] = False
        entry["finishedAt"] = now()
        return entry

    def execute(self) -> None:
        args, report = self.args, self.report
        report["ownedIdentitiesBefore"] = identities(self.root, OWNED_IDENTITIES)
        ack_reserve = args.ack_seconds + args.margin_seconds
        if self.remaining() < ack_reserve:
            report["errors"].append("Insufficient budget before ACK; nothing published")
            report["ack"] = {"delivered": False, "reason": "insufficient budget"}
        else:
            ack_text = (
                f"ACK {self.grant}; Python granted window opened as a "
                f"coordinating observer for one bounded <= {args.total_seconds:g}s "
                f"invocation. A separate managed child runs the verification; the "
                f"observer publishes final RELEASE/HOLD only after that child root "
                f"is terminal, Job is 0 and handles are closed. managed root <= "
                f"{args.inner_seconds:g}s; successor {self.next_owner}; evidence "
                f"{self.output}.")
            report["ack"] = self.publish(ack_text, "ack", args.ack_seconds)
        ack = report["ack"]
        if not ack.get("delivered"):
            report["errors"].append("ACK publication not verified; child not started")
            report["verificationRoot"] = {"started": False,
                                           "reason": "ACK not delivered"}
            return

        child_reserve = (args.inner_seconds + args.outer_cleanup_seconds
                         + args.publish_seconds + args.margin_seconds)
        if self.remaining() < child_reserve:
            report["errors"].append(
                "Insufficient budget before child; verification not started")
            report["verificationRoot"] = {"started": False,
                                           "reason": "insufficient budget"}
            return

        child = self.run_child()
        report["verificationRoot"] = child
        child_report_path = self.output / "inner" / "report.json"
        inner = {"reportPath": str(child_report_path),
                 "reportPresent": child_report_path.is_file(),
                 "childExitCode": child.get("exitCode"),
                 "childTimedOut": child.get("timedOut")}
        report["inner"] = inner
        if not child.get("confirmed"):
            report["errors"].append(
                "Managed verification root not confirmed terminal/Job0/"
                "handlesClosed; no final publication")
            inner.update(cleanupConfirmed=False, passed=False, reasons=[
                "managed verification root not confirmed"])
            return
        if not inner["reportPresent"]:
            report["errors"].append(
                "Child report missing; verification FAIL, managed root still released")
            inner.update(cleanupConfirmed=True, passed=False,
                         reasons=["child report missing"])
            return
        try:
            child_report = json.loads(
                child_report_path.read_text(encoding="utf-8"))
        except BaseException as error:
            report["errors"].append(
                f"Child report unreadable: {type(error).__name__}: {error}")
            inner.update(cleanupConfirmed=True, passed=False,
                         reasons=["child report unreadable"])
            return
        child_cleanup, passed, reasons = verify_inner_report(child_report)
        if child.get("timedOut") is True:
            passed = False
            reasons.append("managed child timed out")
        if child.get("exitCode") != 0:
            passed = False
            reasons.append(f"managed child exit={child.get('exitCode')}")
        inner.update(
            cleanupConfirmed=child_cleanup, passed=passed, reasons=reasons,
            result=child_report.get("result"),
            release=child_report.get("release"),
            withinPlanSeconds=child_report.get("withinPlanSeconds"),
            ownedDrift=child_report.get("ownedDrift"))
        if reasons:
            report["errors"].append("Child verification: " + "; ".join(reasons))

    def downgrade_verification(self, message: str) -> None:
        """Record a verification failure and force the status off PASS.

        Used by both pre-publication identity outcomes, so a capture failure and
        a drift can never disagree with what `final_status()` reports. Resource
        release is decided separately from `verificationRoot.confirmed`, so a
        downgraded status still RELEASEs when the managed child really closed.
        """
        report = self.report
        report["errors"].append(message)
        inner = report.get("inner") or {}
        inner["passed"] = False
        reasons = inner.setdefault("reasons", [])
        if message not in reasons:
            reasons.append(message)

    def recheck_freeze(self) -> bool:
        """Re-freeze owned sources before publication.

        This is the only freeze decision that matters: it runs before the final
        status text is composed. Drift detected after publication could not
        withdraw a delivered message and would only make the local report
        contradict it, so there is no post-publication re-read.

        Both outcomes downgrade the verification. A failed capture is unproven
        verification, not unproven cleanup, so the confirmed managed root still
        releases its resources.
        """
        report = self.report
        label = "Pre-publication identity capture"
        try:
            after = identities(self.root, OWNED_IDENTITIES)
        except BaseException as error:
            report["ownedDrift"] = None
            report["identityCapture"] = {
                "ok": False,
                "reason": f"{type(error).__name__}: {error}"}
            # Downgrade before the status text is composed. Without this the
            # capture failure only appended an error, `final_status()` still saw
            # `inner.passed is True`, and a global status=PASS was published
            # while persist() wrote FAIL_OR_INCONCLUSIVE.
            self.downgrade_verification(
                f"{label} failed: {type(error).__name__}: {error}")
            return False
        report["ownedIdentitiesAfter"] = after
        report["identityCapture"] = {"ok": True}
        drift = report.get("ownedIdentitiesBefore") != after
        report["ownedDrift"] = drift
        if drift:
            self.downgrade_verification(
                "Owned source drifted before publication")
        return not drift

    def final_status(self) -> tuple[str, str]:
        """Verification status and resource verb, kept strictly separate.

        `status` reports whether the checks passed. `verb` reports ownership
        handoff: RELEASE whenever the managed verification root really closed,
        otherwise HOLD. A failed check alone never withholds a real release.
        """
        root = self.report.get("verificationRoot") or {}
        if root.get("confirmed") is not True:
            return "HOLD_UNRELEASED", "HOLD"
        inner = self.report.get("inner") or {}
        return ("PASS" if inner.get("passed") is True
                else "FAIL_OR_INCONCLUSIVE"), "RELEASE"

    def publish_final(self) -> None:
        args, report = self.args, self.report
        ack = report.get("ack") or {}
        if not ack.get("delivered"):
            report["publication"] = {"delivered": False,
                                     "reason": "no ACK; release withheld"}
            return
        root = report.get("verificationRoot") or {}
        if root.get("confirmed") is not True:
            report["publication"] = {
                "delivered": False,
                "reason": "managed verification root not confirmed; no final publish",
                "claimedStatus": "HOLD"}
            return
        if self.remaining() < args.publish_seconds + args.margin_seconds:
            report["publication"] = {"delivered": False,
                                     "reason": "insufficient budget for publication"}
            report["errors"].append(
                "Insufficient budget for final publication; release withheld")
            return
        # The freeze decision must happen before the status text is composed.
        frozen = self.recheck_freeze()
        inner = report.get("inner") or {}
        status, verb = self.final_status()
        # Defence in depth: a failed capture or a drift must never publish PASS,
        # even if a future edit forgets to downgrade the verification.
        if not frozen and verb == "RELEASE" and status == "PASS":
            status = "FAIL_OR_INCONCLUSIVE"
        reasons = inner.get("reasons") or []
        detail = ("; ".join(reasons) if reasons else
                  f"inner result={inner.get('result')} "
                  f"withinPlan={inner.get('withinPlanSeconds')}")
        identity = root_identity_line(root)
        observer = (
            f"observer PID={self.observer_pid} is the coordinator and does not "
            f"claim it has exited; this final status is published only after "
            f"the managed child root closed.")
        elapsed = round(time.monotonic() - self.started, 3)
        if verb == "HOLD":
            text = (f"HOLD {self.grant}; release withheld, no handoff to "
                    f"{self.next_owner}. status={status}; managed root not "
                    f"confirmed. {identity}. {detail}. Exact managed-root "
                    f"handles stay retained; do not kill by PID. {observer} "
                    f"evidence {report['output']}.")
        elif status == "PASS":
            text = (f"RELEASE {self.grant} to {self.next_owner}; one bounded "
                    f"observer invocation: ACK, separate managed child "
                    f"verification, terminal/Job0/handle check, final release. "
                    f"status=PASS inner={inner.get('result')} withinPlan="
                    f"{inner.get('withinPlanSeconds')} elapsed={elapsed}s. "
                    f"{identity}. {observer} Focused host checks only; no "
                    f"native/HAP/signing/device claim. evidence {report['output']}.")
        else:
            text = (f"RELEASE {self.grant} to {self.next_owner}; the managed "
                    f"verification root is terminal with Job 0 and handles "
                    f"closed, so resources are released. status={status}. "
                    f"{identity}. {detail}. This is a recorded verification "
                    f"failure, not a cleanup failure. {observer} evidence "
                    f"{report['output']}.")
        entry = self.publish(text, "release", args.publish_seconds)
        entry["claimedStatus"] = verb
        report["publication"] = entry
        if not entry.get("delivered"):
            report["errors"].append(
                "Final publication not verified; manual relay required")

    def persist(self) -> None:
        report = self.report
        root = report.get("verificationRoot") or {}
        inner = report.get("inner") or {}
        publication = report.get("publication") or {}
        ack = report.get("ack") or {}
        claimed_release = publication.get("claimedStatus") == "RELEASE"
        released = bool(root.get("confirmed") is True
                        and claimed_release
                        and publication.get("delivered") is True)
        if not ack.get("delivered"):
            result = "ACK_NOT_DELIVERED"
        elif root.get("confirmed") is not True:
            result = "HOLD_UNRELEASED"
        elif (inner.get("passed") is not True or not released
              or report.get("ownedDrift") or report["errors"]):
            result = "FAIL_OR_INCONCLUSIVE"
        else:
            result = "PASS"
        report["withinTotalSeconds"] = (
            round(time.monotonic() - self.started, 3) <= self.args.total_seconds)
        report["elapsedSeconds"] = round(time.monotonic() - self.started, 3)
        if not report["withinTotalSeconds"]:
            report["errors"].append("Window exceeded its total seconds")
            if result == "PASS":
                result = "FAIL_OR_INCONCLUSIVE"
        report["result"] = result
        # Release describes real resource handoff of the managed root only. A
        # failed, drifted or over-budget verification can still release when
        # that root and the publication are real, so the local report never
        # contradicts the global RELEASE message.
        report["release"] = "RELEASE" if released else "HOLD_UNRELEASED"
        report["finishedAt"] = now()
        path = self.output / "report.json"
        temporary = path.with_suffix(".json.tmp")
        temporary.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n",
                             encoding="utf-8")
        os.replace(temporary, path)

    def summary(self) -> str:
        report = self.report
        ack = report.get("ack") or {}
        root = report.get("verificationRoot") or {}
        inner = report.get("inner") or {}
        publication = report.get("publication") or {}
        return (f"{report['release']} {report['grant']}; next owner "
                f"{report['nextOwner']}. result={report['result']} "
                f"elapsed={report['elapsedSeconds']}s "
                f"withinTotal={report['withinTotalSeconds']}. "
                f"ackDelivered={ack.get('delivered')} "
                f"rootConfirmed={root.get('confirmed')} "
                f"rootTerminal={root.get('terminal')} "
                f"jobActive={root.get('jobActiveProcesses')} "
                f"handlesClosed={root.get('handlesClosed')} "
                f"innerPassed={inner.get('passed')} "
                f"publicationDelivered={publication.get('delivered')} "
                f"claimed={publication.get('claimedStatus')} "
                f"observerPid={report['observerPid']}. "
                f"report={report['output']}/report.json")


def main(argv: list[str] | None = None) -> int:
    if sys.flags.optimize:
        print("Refusing to run under -O/PYTHONOPTIMIZE: window checks would be "
              "stripped", file=sys.stderr, flush=True)
        return 2
    parser = argparse.ArgumentParser(description=__doc__,
                                     fromfile_prefix_chars="@")
    parser.add_argument("--grant", required=True,
                        help="NEW named grant; never REPLACE_ or a consumed name")
    parser.add_argument("--next-owner", required=True,
                        help="Explicit successor; documented value c-coordinator")
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path, required=True,
                        help="New evidence directory under <root>/build")
    parser.add_argument("--total-seconds", type=float, default=TOTAL_MAX)
    parser.add_argument("--inner-seconds", type=float, default=120.0,
                        help="Managed verification child timeout")
    parser.add_argument("--inner-plan-seconds", type=float, default=105.0,
                        help="Child --plan-seconds; plan + phases*cleanup <= inner")
    parser.add_argument("--child-cleanup-seconds", type=float, default=5.0)
    parser.add_argument("--outer-cleanup-seconds", type=float, default=10.0,
                        help="Outer run_owned cleanup budget for the child Job")
    parser.add_argument("--ack-seconds", type=float, default=12.0)
    parser.add_argument("--publish-seconds", type=float, default=18.0)
    parser.add_argument("--margin-seconds", type=float, default=5.0)
    parser.add_argument("--max-inner-phases", type=int, default=3)
    parser.add_argument("--control-seconds", type=float, default=60.0)
    parser.add_argument("--min-phase-seconds", type=float, default=5.0)
    parser.add_argument("--control-only", action="store_true")
    parser.add_argument("--controls-report", type=Path)
    parser.add_argument("--include-named-workspace", action="store_true")
    parser.add_argument("--include-consumer-tests", action="store_true",
                        help="Thread the inner flag that adds the two bound "
                             "consumer suites to the child's merged call")
    parser.add_argument("--scope", action="append")
    parser.add_argument("--flutter", default="flutter")
    parser.add_argument("--dart", default="dart")
    parser.add_argument("--python", default=sys.executable)
    parser.add_argument("--node")
    parser.add_argument("--trellis-entry", type=Path)
    parser.add_argument("--channel", default=CHANNEL)
    parser.add_argument("--sender", default=SENDER)
    parser.add_argument("--used-grant", action="append", default=[],
                        help="A grant name already consumed; replay is rejected")
    parser.add_argument("--outer-handle")
    args = parser.parse_args(argv)
    validate(parser, args)
    try:
        window = GrantedWindow(args)
    except (WindowFailure, OSError) as error:
        # A missing root, helper or Trellis entry is a construction failure. It
        # must read as a clear parser error, not a traceback, and it must not
        # leave a half-built window or a stray evidence directory.
        parser.error(f"Cannot open the window: {error}")
    try:
        window.execute()
    except BaseException as error:
        window.report["errors"].append(f"{type(error).__name__}: {error}")
    try:
        window.publish_final()
    except BaseException as error:
        window.report["errors"].append(
            f"Final publication aborted: {type(error).__name__}: {error}")
        window.report["publication"] = {"delivered": False,
                                        "reason": "publication raised"}
    finally:
        window.persist()
        line = window.summary()
        print(line, flush=True)
        # The published release text lives in release-message.md; keep the
        # operator summary separate so publication text is never overwritten.
        (window.output / "window-summary.md").write_text(line + "\n",
                                                         encoding="utf-8")
    return 0 if window.report["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
