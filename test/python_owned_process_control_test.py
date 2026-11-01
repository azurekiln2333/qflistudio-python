"""Prepared Windows process controls plus source-only synthetic fault injection.

Source-only handoff: the real controls have not been executed. They start Python
children and one local .cmd fixture, never a compiler/SDK/build/device command.
Import has no execution or filesystem side effects. The shared helper owns all
started processes; controls never find or terminate a process by PID.

Two entry modes:

* ``--synthetic-only`` runs metadata doubles, a fake kernel32 for the handle
  state machine, and a source-path-resolution probe. It starts no controlled
  child, so it is safe for a source-only gate. Its PASS is NOT evidence of real
  Windows Job containment, real HANDLE lifetime or real shell quoting.
* default mode requires a new grant and adds the five real child cases.

Every acceptance check goes through ``require`` (an unconditional raise). There
are deliberately no bare ``assert`` statements, so ``python -O`` /
``PYTHONOPTIMIZE`` cannot strip the checks. Optimized execution is also refused
outright before any evidence directory or child is created.
"""
from __future__ import annotations

import argparse
import ast
import contextlib
import ctypes as C
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import time


class ControlFailure(Exception):
    """Unconditional control failure; never removed by Python optimization."""


def require(condition, *evidence) -> None:
    if not condition:
        detail = " ".join(str(item) for item in evidence)
        raise ControlFailure(f"Control check failed: {detail}".strip())


def load_helper(root: Path):
    spec = importlib.util.spec_from_file_location(
        "_python_owned_process_controls", root / "tool/python_owned_process.py")
    module = importlib.util.module_from_spec(spec)
    previous = sys.dont_write_bytecode
    try:
        sys.dont_write_bytecode = True
        spec.loader.exec_module(module)
    finally:
        sys.dont_write_bytecode = previous
    return module


def require_drained(report: dict) -> None:
    process = report["process"]
    require(report["release"] == "RELEASE" and report["state"] == "FINISHED", report)
    require(report["cleanupConfirmed"] and process["handlesClosed"], report)
    require(process["terminal"] and process["jobActiveProcesses"] == 0, report)
    require(process["createdSuspended"] and process["assignedBeforeResume"] and process["resumed"], report)
    require(int(process["creationFiletime100ns"]) > 0 and process["pid"] > 0, report)
    require(process["processHandleDecimal"] and process["jobHandleDecimal"], report)


# ---------------------------------------------------------------------------
# Synthetic (no controlled child) fault injection
# ---------------------------------------------------------------------------

def synthetic_resolution(helper, case: Path) -> dict:
    """Relative PATH/COMSPEC must resolve against the requested cwd, never the
    wrapper's process directory. Two distinct A/B trees prove the selection."""
    a = case / "A"
    b = case / "B"
    (a / "bin").mkdir(parents=True)
    (b / "bin").mkdir(parents=True)
    (a / "bin" / "tool.exe").write_bytes(b"A-tool")
    (b / "bin" / "tool.exe").write_bytes(b"B-tool")
    (a / "bin" / "cmd.exe").write_bytes(b"A-cmd")
    (b / "bin" / "cmd.exe").write_bytes(b"B-cmd")
    (b / "run.cmd").write_bytes(b"@echo off\r\n")
    environment = {
        "PATH": "bin",
        "PATHEXT": ".COM;.EXE;.BAT;.CMD",
        "COMSPEC": r"bin\cmd.exe",
    }
    expected_tool = (b / "bin" / "tool.exe").resolve()
    expected_cmd = (b / "bin" / "cmd.exe").resolve()
    previous = os.getcwd()
    try:
        os.chdir(a)  # Wrapper "starts" in A while the caller asks for cwd=B.
        application, _line, invocation = helper.command_line(["tool.exe", "arg"], b, environment)
        require(Path(application) == expected_tool,
                "bare command resolved outside the requested cwd", application, expected_tool)
        require(Path(application).read_bytes() == b"B-tool",
                "resolved the A-tree executable instead of B", application)
        require(invocation["resolvedArgv"][0] == str(expected_tool), invocation)

        # A relative path with a directory component stays anchored at cwd.
        relative_application, _line, _meta = helper.command_line([r"bin\tool.exe"], b, environment)
        require(Path(relative_application) == expected_tool, relative_application)

        # A relative COMSPEC is the requested cwd's cmd.exe, not A's.
        shell, _batch_line, batch = helper.command_line([str(b / "run.cmd"), "token"], b, environment)
        require(Path(shell) == expected_cmd, "relative COMSPEC resolved outside the requested cwd", shell)
        require(Path(batch["interpreter"]) == expected_cmd, batch)

        # Absolute PATH entries remain absolute and are honored unchanged.
        absolute_environment = dict(environment, PATH=str(a / "bin"))
        absolute_application, _line, _meta = helper.command_line(["tool.exe"], b, absolute_environment)
        require(Path(absolute_application) == (a / "bin" / "tool.exe").resolve(), absolute_application)

        # The child environment's PATHEXT decides whether extension search runs.
        no_extensions = dict(environment, PATHEXT="")
        raised = False
        try:
            helper.command_line(["tool"], b, no_extensions)
        except FileNotFoundError:
            raised = True
        require(raised, "child PATHEXT was ignored; extensionless name unexpectedly resolved")
        found, _line, _meta = helper.command_line(["tool"], b, environment)
        require(Path(found) == expected_tool, "child PATHEXT extension search failed", found)
    finally:
        os.chdir(previous)
    return {
        "wrapperCwd": str(a), "requestedCwd": str(b),
        "resolvedTool": str(expected_tool), "resolvedInterpreter": str(expected_cmd),
    }


def synthetic_always_on(helper, case: Path, script: Path) -> dict:
    """The acceptance checks must raise regardless of optimization flags."""
    try:
        require(False, "deliberate synthetic failure")
    except ControlFailure:
        pass
    else:
        raise ControlFailure("require() did not raise for a false condition")
    tree = ast.parse(script.read_text(encoding="utf-8"))
    bare = sorted(node.lineno for node in ast.walk(tree) if isinstance(node, ast.Assert))
    require(not bare, "control source still has bare assert statements that -O strips", bare)
    require(sys.flags.optimize == 0, "synthetic gate itself is optimized; refusal guard must run first")
    return {"requireRaises": True, "bareAssertLines": bare, "optimizeFlag": sys.flags.optimize}


class ExplodingKernel:
    """Any kernel32 call is a bug for a no-resource job."""

    def __getattr__(self, name):
        def explode(*_args, **_kwargs):
            raise ControlFailure(f"unexpected kernel32 call: {name}")
        return explode


class FakeCloseKernel:
    """Fake CloseHandle that fails the first close of one exact handle."""

    def __init__(self, fail_handle=None):
        self.fail_handle = fail_handle
        self.failed = False
        self.close_calls: list[int] = []

    def CloseHandle(self, handle):
        self.close_calls.append(handle)
        if handle == self.fail_handle and not self.failed:
            self.failed = True
            C.set_last_error(6)  # ERROR_INVALID_HANDLE
            return False
        return True


def synthetic_no_resource(helper, case: Path) -> dict:
    """CreateJobObjectW failure must be a vacuous terminal/empty release."""
    job = helper.OwnedJob()
    job.k = ExplodingKernel()
    require(job.job is None and job.process is None and job.thread is None, "new job not empty")
    require(job.empty() is True, "no-resource job did not report terminal/empty")
    require(job.record["terminal"] is True and job.record["jobActiveProcesses"] == 0, job.record)
    job.confirmed_empty = True
    job.close_confirmed()
    require(job.record["handlesClosed"] is True, "no-resource handles not marked closed", job.record)
    return {"empty": True, "handlesClosed": True, "kernelCalls": 0}


def synthetic_empty_job(helper, case: Path) -> dict:
    """A retained private Job with no root must be observed empty and closed."""
    job = helper.OwnedJob()

    class Kernel:
        def __init__(self):
            self.close_calls: list[int] = []

        def QueryInformationJobObject(self, handle, info_class, pointer, size, returned):
            C.cast(pointer, C.POINTER(helper.Accounting)).contents.active = 0
            return True

        def CloseHandle(self, handle):
            self.close_calls.append(handle)
            return True

    kernel = Kernel()
    job.k = kernel
    job.job, job.process, job.thread = 0x1111, None, None
    require(job.empty() is True, "retained empty Job was not observed empty")
    require(job.record["terminal"] is True and job.record["jobActiveProcesses"] == 0, job.record)
    job.confirmed_empty = True
    job.close_confirmed()
    require(kernel.close_calls == [0x1111], "exact retained Job handle was not closed", kernel.close_calls)
    require(job.job is None and job.record["handlesClosed"] is True, job.record)
    return {"jobHandle": "0x1111", "closed": kernel.close_calls}


def synthetic_close_failure(helper, case: Path) -> dict:
    """A failed CloseHandle must be retained and only cleared by a retry."""
    job = helper.OwnedJob()
    kernel = FakeCloseKernel(fail_handle=0x2222)
    job.k = kernel
    job.job, job.process, job.thread = 0x1111, 0x2222, 0x3333
    job.confirmed_empty = True
    raised = False
    try:
        job.close_confirmed()
    except RuntimeError:
        raised = True
    require(raised, "failed handle closure was not reported")
    require(job.process == 0x2222, "failed close did not retain the exact process handle", job.process)
    require(job.job is None and job.thread is None, "successful closes were not released", (job.job, job.thread))
    require(job.record["handlesClosed"] is False,
            "partial closure falsely claimed every handle was closed", job.record)
    job.close_confirmed()
    require(job.process is None, "retry did not close the retained process handle", job.process)
    require(job.record["handlesClosed"] is True, "retry did not confirm every handle closed", job.record)
    return {"failedOnce": True, "retainedProcess": "0x2222", "retryClosed": True}


class ScriptedNoResourceJob:
    """Double: Job creation fails, so no resource exists to retain."""

    def __init__(self):
        self.job = self.process = self.thread = None
        self.confirmed_empty = False
        self.record = {
            "rootCreated": False, "terminal": True, "exitCode": None,
            "jobActiveProcesses": None, "assignedBeforeResume": False,
            "createdSuspended": False, "resumed": False, "handlesClosed": False,
            "jobHandleDecimal": None, "jobHandleHex": None,
            "processHandleDecimal": None, "processHandleHex": None,
            "threadHandleDecimal": None, "threadHandleHex": None,
            "pid": None, "creationFiletime100ns": None,
        }

    def open(self):
        raise OSError(0, "CreateJobObjectW returned a null handle")

    def start(self, *_args, **_kwargs):
        raise ControlFailure("start must not run when Job creation failed")

    def empty(self):
        self.record.update(terminal=True, jobActiveProcesses=0)
        return True

    def stop(self, _code):
        raise ControlFailure("stop must not run when no resource exists")

    def close_confirmed(self):
        require(self.confirmed_empty, "close before confirmed empty")
        require(self.job is None and self.process is None and self.thread is None,
                "unexpected retained handle on a no-resource job")
        self.record["handlesClosed"] = True


def synthetic_no_resource_run(helper, case: Path) -> dict:
    """run_owned must release a startup failure that never created a resource."""
    original_job = helper.OwnedJob
    helper.OwnedJob = ScriptedNoResourceJob
    try:
        report = helper.run_owned(
            [sys.executable, "-c", "pass"], timeout_seconds=5, cleanup_seconds=1,
            cwd=case, log_path=case / "output.log", report_path=case / "report.json")
    finally:
        helper.OwnedJob = original_job
    require(report["state"] == "FINISHED" and report["release"] == "RELEASE", report)
    require(report["exitCode"] == helper.WRAPPER_ERROR_EXIT, report["exitCode"])
    require(report["cleanupConfirmed"] is True, report)
    require(report["process"]["handlesClosed"] is True, report["process"])
    require("holdPublicationCount" not in report, "no-resource failure entered HOLD", report)
    require(json.loads((case / "report.json").read_text(encoding="utf-8")) == report, "durable mismatch")
    return {"exitCode": report["exitCode"], "hold": False, "handlesClosed": True}


class ScriptedStartupJob:
    """Double: exact handles retained, then a post-CreateProcess startup failure.

    ``empty`` stays non-terminal until the wrapper has requested termination and
    a recovery delay elapses, so ``drain`` must publish a durable HOLD first and
    only release after the state machine recovers.
    """

    def __init__(self, *, fail_after_assignment: bool, recover_delay: float):
        self.fail_after_assignment = fail_after_assignment
        self.recover_delay = recover_delay
        self.job = self.process = self.thread = None
        self.confirmed_empty = False
        self.stop_calls = 0
        self.recover_at = None
        self.record = {
            "rootCreated": False, "terminal": True, "exitCode": None,
            "jobActiveProcesses": None, "assignedBeforeResume": False,
            "createdSuspended": False, "resumed": False, "handlesClosed": False,
            "jobHandleDecimal": "4369", "jobHandleHex": "0x1111",
            "processHandleDecimal": "8738", "processHandleHex": "0x2222",
            "threadHandleDecimal": "13107", "threadHandleHex": "0x3333",
            "pid": 4242, "creationFiletime100ns": "133000000000000000",
        }

    def open(self):
        self.job = 0x1111

    def start(self, _application, _line, _cwd, _environment, _log, on_assigned=None):
        self.process, self.thread = 0x2222, 0x3333
        self.record.update(rootCreated=True, terminal=False, createdSuspended=True)
        if self.fail_after_assignment:
            self.record["assignedBeforeResume"] = True
            if on_assigned is not None:
                on_assigned()  # Persisted while suspended, then resume fails.
            raise RuntimeError("Root did not resume from its single creation suspension")
        raise RuntimeError("Job assignment failed after exact handles were returned")

    def empty(self):
        if self.stop_calls >= 1 and self.recover_at is not None and time.monotonic() >= self.recover_at:
            self.record.update(terminal=True, jobActiveProcesses=0, exitCode=125)
            return True
        self.record.update(terminal=False, jobActiveProcesses=1)
        return False

    def stop(self, _code):
        self.stop_calls += 1
        self.record["ownedJobTerminationRequested"] = True
        if self.process is not None and not self.record["assignedBeforeResume"]:
            self.record["unassignedSuspendedRootTerminationRequested"] = True
        if self.recover_at is None:
            self.recover_at = time.monotonic() + self.recover_delay

    def close_confirmed(self):
        require(self.confirmed_empty, "close before confirmed empty")
        self.job = self.process = self.thread = None
        self.record["handlesClosed"] = True


def synthetic_startup_hold(helper, case: Path, *, fail_after_assignment: bool,
                           recover_delay: float, cleanup_seconds: float,
                           expect_hold: bool) -> dict:
    """Post-CreateProcess startup failure must HOLD with exact identity, then
    only release after the state machine recovers to terminal/empty."""
    published: list[dict] = []
    original_atomic = helper.atomic_report

    def capture(path, value):
        published.append(json.loads(json.dumps(value)))
        return original_atomic(path, value)

    original_job = helper.OwnedJob
    helper.OwnedJob = lambda: ScriptedStartupJob(
        fail_after_assignment=fail_after_assignment, recover_delay=recover_delay)
    helper.atomic_report = capture
    output = io.StringIO()
    try:
        with contextlib.redirect_stdout(output):
            report = helper.run_owned(
                [sys.executable, "-c", "pass"], timeout_seconds=5,
                cleanup_seconds=cleanup_seconds, cwd=case,
                log_path=case / "output.log", report_path=case / "report.json")
    finally:
        helper.OwnedJob = original_job
        helper.atomic_report = original_atomic

    held = [value for value in published
            if value.get("state") == "HOLD_UNRELEASED"]
    if expect_hold:
        require(held, "drain never published HOLD_UNRELEASED")
        require(all(value.get("release") == "HOLD_UNRELEASED" and value.get("handlesRetained") is True
                    for value in held), "HOLD did not advertise retained handles", held[-1])
        require(report["holdPublicationCount"] == len(held), "HOLD count mismatch",
                report.get("holdPublicationCount"), len(held))
        require(report["cleanupDeadlineExceeded"] is True, report)
        require(report["cleanupWithinDeadline"] is False, report)
    else:
        require(not held, "unexpected HOLD on a within-deadline recovery", held)
        require("holdPublicationCount" not in report, "unexpected HOLD count", report)
        require("cleanupDeadlineExceeded" not in report, "unexpected deadline flag", report)
        require(report["cleanupWithinDeadline"] is True, report)
    require(report["state"] == "FINISHED" and report["release"] == "RELEASE", report)
    require(report["cleanupConfirmed"] is True, report)
    require(report["process"]["handlesClosed"] is True, report["process"])
    require(report["process"]["terminal"] is True and report["process"]["jobActiveProcesses"] == 0,
            report["process"])
    require(report["exitCode"] == helper.WRAPPER_ERROR_EXIT, report["exitCode"])
    require(report["process"]["ownedJobTerminationRequested"] is True, report["process"])
    if fail_after_assignment:
        require(report["process"]["assignedBeforeResume"] is True, report["process"])
        require("unassignedSuspendedRootTerminationRequested" not in report["process"],
                "assigned root was terminated through its raw handle", report["process"])
    else:
        require(report["process"]["assignedBeforeResume"] is False, report["process"])
        require(report["process"]["unassignedSuspendedRootTerminationRequested"] is True,
                "never-resumed suspended root was not terminated", report["process"])

    hold_line = next((line for line in output.getvalue().splitlines()
                      if line.startswith("HOLD_UNRELEASED")), "")
    if expect_hold:
        require(hold_line, "HOLD identity was not printed", output.getvalue())
        for token in ("HANDLE=8738", "PID=4242", "FILETIME=133000000000000000", "jobHANDLE=4369"):
            require(token in hold_line, f"HOLD line missing {token}", hold_line)
    else:
        require(not hold_line, "unexpected HOLD line", hold_line)

    durable = json.loads((case / "report.json").read_text(encoding="utf-8"))
    require(durable == report, "durable report differs from the returned report")
    return {
        "holdPublications": len(held), "holdLine": hold_line,
        "recoveredTo": report["release"], "exitCode": report["exitCode"],
        "assignedBeforeResume": report["process"]["assignedBeforeResume"],
        "unassignedRootTerminated": report["process"].get(
            "unassignedSuspendedRootTerminationRequested", False),
    }


class ScriptedJobWithoutProcess:
    """Double: the private Job exists, but process creation failed."""

    def __init__(self):
        self.job = self.process = self.thread = None
        self.confirmed_empty = False
        self.stop_calls = 0
        self.record = {
            "rootCreated": False, "terminal": True, "exitCode": None,
            "jobActiveProcesses": None, "assignedBeforeResume": False,
            "createdSuspended": False, "resumed": False, "handlesClosed": False,
            "jobHandleDecimal": None, "jobHandleHex": None,
            "processHandleDecimal": None, "processHandleHex": None,
            "threadHandleDecimal": None, "threadHandleHex": None,
            "pid": None, "creationFiletime100ns": None,
        }

    def open(self):
        self.job = 0x1111
        self.record.update(jobHandleDecimal="4369", jobHandleHex="0x1111")

    def start(self, *_args, **_kwargs):
        raise RuntimeError("CreateProcess failed after the private Job was created")

    def empty(self):
        # No root was ever created, so the retained Job is already empty.
        self.record.update(terminal=True, jobActiveProcesses=0)
        return True

    def stop(self, _code):
        self.stop_calls += 1
        self.record["ownedJobTerminationRequested"] = True

    def close_confirmed(self):
        require(self.confirmed_empty, "close before confirmed empty")
        require(self.process is None and self.thread is None, "unexpected root handles")
        self.job = None
        self.record["handlesClosed"] = True


def synthetic_job_without_process(helper, case: Path) -> dict:
    """Job creation succeeded but process creation failed: the retained empty
    Job must be closed with no termination request and no HOLD."""
    original_job = helper.OwnedJob
    double = ScriptedJobWithoutProcess()
    helper.OwnedJob = lambda: double
    try:
        report = helper.run_owned(
            [sys.executable, "-c", "pass"], timeout_seconds=5, cleanup_seconds=1,
            cwd=case, log_path=case / "output.log", report_path=case / "report.json")
    finally:
        helper.OwnedJob = original_job
    require(report["state"] == "FINISHED" and report["release"] == "RELEASE", report)
    require(report["exitCode"] == helper.WRAPPER_ERROR_EXIT, report["exitCode"])
    require(report["cleanupConfirmed"] is True, report)
    require(report["process"]["handlesClosed"] is True, report["process"])
    require(report["process"]["terminal"] is True and report["process"]["jobActiveProcesses"] == 0,
            report["process"])
    require(double.stop_calls == 0, "empty Job needed a termination request", double.stop_calls)
    require("holdPublicationCount" not in report, "unexpected HOLD on an empty Job", report)
    require(json.loads((case / "report.json").read_text(encoding="utf-8")) == report,
            "durable report differs from the returned report")
    return {"exitCode": report["exitCode"], "stopCalls": double.stop_calls,
            "handlesClosed": True, "hold": False}


class ScriptedFlakyObservation:
    """Double: first drain observation raises, the next one reports empty."""

    def __init__(self):
        self.job = self.process = self.thread = None
        self.confirmed_empty = False
        self.empty_calls = 0
        self.stop_calls = 0
        self.record = {
            "rootCreated": False, "terminal": True, "exitCode": None,
            "jobActiveProcesses": None, "assignedBeforeResume": False,
            "createdSuspended": False, "resumed": False, "handlesClosed": False,
            "jobHandleDecimal": "4369", "jobHandleHex": "0x1111",
            "processHandleDecimal": "8738", "processHandleHex": "0x2222",
            "threadHandleDecimal": "13107", "threadHandleHex": "0x3333",
            "pid": 4242, "creationFiletime100ns": "133000000000000000",
        }

    def open(self):
        self.job = 0x1111

    def start(self, _application, _line, _cwd, _environment, _log, on_assigned=None):
        self.process, self.thread = 0x2222, 0x3333
        self.record.update(rootCreated=True, terminal=False, createdSuspended=True)
        raise RuntimeError("identity capture failed after exact handles were returned")

    def empty(self):
        self.empty_calls += 1
        if self.empty_calls == 1:
            raise OSError("simulated QueryInformationJobObject failure")
        self.record.update(terminal=True, jobActiveProcesses=0, exitCode=125)
        return True

    def stop(self, _code):
        self.stop_calls += 1
        self.record["ownedJobTerminationRequested"] = True

    def close_confirmed(self):
        require(self.confirmed_empty, "close before confirmed empty")
        self.job = self.process = self.thread = None
        self.record["handlesClosed"] = True


def synthetic_observation_retry(helper, case: Path) -> dict:
    """A failed observation must be recorded and retried, not abort cleanup."""
    original_job = helper.OwnedJob
    double = ScriptedFlakyObservation()
    helper.OwnedJob = lambda: double
    try:
        report = helper.run_owned(
            [sys.executable, "-c", "pass"], timeout_seconds=5, cleanup_seconds=1,
            cwd=case, log_path=case / "output.log", report_path=case / "report.json")
    finally:
        helper.OwnedJob = original_job
    require(report["state"] == "FINISHED" and report["release"] == "RELEASE", report)
    require(report["cleanupConfirmed"] is True, report)
    require(report["process"]["handlesClosed"] is True, report["process"])
    require(report["process"]["terminal"] is True and report["process"]["jobActiveProcesses"] == 0,
            report["process"])
    require("holdPublicationCount" not in report, "unexpected HOLD", report)
    require(any("Exact-handle cleanup observation/closure" in message
                for message in report["errors"]), "failed observation was not recorded", report["errors"])
    return {"emptyCalls": double.empty_calls, "recoveredTo": report["release"],
            "recordedError": True}


class ScriptedTerminationRetry:
    """Double: the first termination request fails, the retry succeeds."""

    def __init__(self):
        self.job = self.process = self.thread = None
        self.confirmed_empty = False
        self.stop_calls = 0
        self.recover_at = None
        self.record = {
            "rootCreated": False, "terminal": True, "exitCode": None,
            "jobActiveProcesses": None, "assignedBeforeResume": False,
            "createdSuspended": False, "resumed": False, "handlesClosed": False,
            "jobHandleDecimal": "4369", "jobHandleHex": "0x1111",
            "processHandleDecimal": "8738", "processHandleHex": "0x2222",
            "threadHandleDecimal": "13107", "threadHandleHex": "0x3333",
            "pid": 4242, "creationFiletime100ns": "133000000000000000",
        }

    def open(self):
        self.job = 0x1111

    def start(self, _application, _line, _cwd, _environment, _log, on_assigned=None):
        self.process, self.thread = 0x2222, 0x3333
        self.record.update(rootCreated=True, terminal=False, createdSuspended=True)
        raise RuntimeError("Job assignment failed after exact handles were returned")

    def empty(self):
        if (self.stop_calls >= 2 and self.recover_at is not None
                and time.monotonic() >= self.recover_at):
            self.record.update(terminal=True, jobActiveProcesses=0, exitCode=125)
            return True
        self.record.update(terminal=False, jobActiveProcesses=1)
        return False

    def stop(self, _code):
        self.stop_calls += 1
        if self.stop_calls == 1:
            raise RuntimeError("simulated TerminateJobObject failure")
        self.record["ownedJobTerminationRequested"] = True
        if self.recover_at is None:
            self.recover_at = time.monotonic()

    def close_confirmed(self):
        require(self.confirmed_empty, "close before confirmed empty")
        self.job = self.process = self.thread = None
        self.record["handlesClosed"] = True


def synthetic_termination_retry(helper, case: Path) -> dict:
    """A termination request that fails must be retried until it succeeds."""
    original_job = helper.OwnedJob
    double = ScriptedTerminationRetry()
    helper.OwnedJob = lambda: double
    try:
        report = helper.run_owned(
            [sys.executable, "-c", "pass"], timeout_seconds=10, cleanup_seconds=8,
            cwd=case, log_path=case / "output.log", report_path=case / "report.json")
    finally:
        helper.OwnedJob = original_job
    require(report["state"] == "FINISHED" and report["release"] == "RELEASE", report)
    require(double.stop_calls == 2, "termination was not retried", double.stop_calls)
    require(report["process"]["ownedJobTerminationRequested"] is True, report["process"])
    require(report["cleanupConfirmed"] is True and report["process"]["handlesClosed"] is True, report)
    require(report["process"]["terminal"] is True and report["process"]["jobActiveProcesses"] == 0,
            report["process"])
    require(report["cleanupWithinDeadline"] is True, report)
    require("holdPublicationCount" not in report, "unexpected HOLD within the deadline", report)
    require(any("Owned termination request" in message for message in report["errors"]),
            "failed termination was not recorded", report["errors"])
    return {"stopCalls": double.stop_calls, "recordedError": True,
            "recoveredTo": report["release"]}


def synthetic_batch_token_rejection(helper, case: Path) -> dict:
    """Batch tokens with percent/exclamation/quote/NUL/newline must be refused,
    while an ordinary token still resolves the explicit cmd wrapping."""
    batch = case / "run.cmd"
    batch.write_bytes(b"@echo off\r\n")
    interpreter = case / "cmd.exe"
    interpreter.write_bytes(b"metadata-cmd")
    environment = {"COMSPEC": str(interpreter)}
    rejected = []
    for token in ["%PATH%", "a!b", 'a"b', "a\0b", "a\rb", "a\nb"]:
        try:
            helper.command_line([str(batch), token], case, environment)
        except ValueError:
            rejected.append(token)
    require(len(rejected) == 6, "a rejected batch token was accepted", rejected)
    _application, _line, invocation = helper.command_line([str(batch), "plain token"], case, environment)
    require(invocation["kind"] == "explicit-cmd-batch", invocation)
    require(invocation["delayedExpansion"] is False, invocation)
    return {"rejectedTokens": len(rejected), "kind": invocation["kind"]}


# ---------------------------------------------------------------------------
# Real child controls (new grant + new window only)
# ---------------------------------------------------------------------------

def run_real_controls(helper, root: Path, output: Path, summary: dict) -> None:
    def run(name: str, command: list[str], timeout: float = 5) -> dict:
        case = output / name
        case.mkdir()
        report = helper.run_owned(
            command, timeout_seconds=timeout, cleanup_seconds=3, cwd=root,
            log_path=case / "output.log", report_path=case / "report.json")
        require_drained(report)
        # Confirm the durable JSON agrees with the returned result.
        require(json.loads((case / "report.json").read_text(encoding="utf-8")) == report,
                "durable report differs from the returned report")
        summary["cases"].append({"name": name, "kind": "real-child",
                                 "exitCode": report["exitCode"],
                                 "report": str(case / "report.json")})
        helper.atomic_report(output / "controls.json", summary)
        return report

    normal = run("normal", [sys.executable, "-I", "-u", "-c",
                 "import sys; sys.stdout.write('x' * 262144 + '\\nnormal-out\\n'); "
                 "sys.stderr.write('normal-err\\n')"])
    require(normal["exitCode"] == 0 and normal["process"]["exitCode"] == 0, normal["exitCode"])
    normal_log = (output / "normal/output.log").read_bytes()
    require(b"normal-out" in normal_log and b"normal-err" in normal_log, "normal output missing")
    require(normal["invocation"]["kind"] == "native-executable", normal["invocation"])

    nonzero = run("nonzero", [sys.executable, "-I", "-u", "-c",
                  "import sys; print('exit-seven', flush=True); sys.exit(7)"])
    require(nonzero["exitCode"] == 7 and nonzero["process"]["exitCode"] == 7, nonzero["exitCode"])
    require(not nonzero["timedOut"], "nonzero case timed out")

    timeout = run("timeout", [sys.executable, "-I", "-u", "-c",
                  "import time; print('timeout-ready', flush=True); time.sleep(60)"], 1.5)
    require(timeout["timedOut"] and timeout["exitCode"] == 124, timeout["exitCode"])
    require(timeout["process"]["ownedJobTerminationRequested"], timeout["process"])

    child_code = "import time; print('live-child-ready', flush=True); time.sleep(60)"
    root_code = (
        "import os, subprocess, sys; "
        f"child = subprocess.Popen([sys.executable, '-I', '-u', '-c', {child_code!r}], "
        "stdout=sys.stdout, stderr=sys.stderr); "
        "print('root-exit-zero child=' + str(child.pid), flush=True); os._exit(0)"
    )
    held = run("root-exit-live-child", [sys.executable, "-I", "-u", "-c", root_code], 2)
    require(held["timedOut"] and held["exitCode"] == 124, held["exitCode"])
    require(held["process"]["exitCode"] == 0, "root success alone cannot release", held["process"])
    negative = held["process"]["rootTerminalWithChildren"]
    require(negative["releaseRejected"] and negative["jobActiveProcesses"] > 0, negative)

    batch = output / "batch fixture.cmd"
    batch.write_text('@echo off\necho batch-token="%~1"\nexit /b 9\n',
                     encoding="ascii", newline="\r\n")
    wrapped = run("batch", [str(batch), "space & (literal token)"])
    require(wrapped["exitCode"] == 9 and wrapped["process"]["exitCode"] == 9, wrapped["exitCode"])
    require(wrapped["invocation"]["kind"] == "explicit-cmd-batch", wrapped["invocation"])
    require(b"space & (literal token)" in (output / "batch/output.log").read_bytes(),
            "batch argument not preserved")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--grant", help="New serialized control-process grant identity")
    parser.add_argument("--output", required=True,
                        help="New subdirectory under this repository's build/")
    parser.add_argument("--synthetic-only", action="store_true",
                        help="Run only metadata doubles/static checks; starts no controlled child")
    args = parser.parse_args(argv)
    if os.name != "nt":
        parser.error("These exact Job controls require Windows")
    if sys.flags.optimize:
        parser.error("Refusing to run under -O/PYTHONOPTIMIZE: acceptance checks would be stripped")
    if not args.synthetic_only and not (args.grant and args.grant.strip()):
        parser.error("A nonempty new grant identity is required for real controls")
    root = Path(__file__).resolve().parent.parent
    output = Path(args.output).resolve()
    if root / "build" not in output.parents:
        parser.error("Control evidence must stay in a new subdirectory of ignored build/")
    output.mkdir(parents=True, exist_ok=False)
    helper = load_helper(root)
    scope = "SYNTHETIC_ONLY" if args.synthetic_only else "CONTROL_PROCESSES_ONLY"
    summary = {"schemaVersion": 1, "grant": (args.grant or "").strip(),
               "startedAt": helper.now(), "scope": scope,
               "syntheticCases": [], "cases": [], "errors": [], "result": "RUNNING"}

    synthetic_cases = [
        ("resolution-cwd", "source-path-resolution",
         lambda case: synthetic_resolution(helper, case)),
        ("always-on-checks", "static-source-scan",
         lambda case: synthetic_always_on(helper, case, Path(__file__))),
        ("no-resource-open-failure", "fake-kernel",
         lambda case: synthetic_no_resource(helper, case)),
        ("empty-job-close", "fake-kernel",
         lambda case: synthetic_empty_job(helper, case)),
        ("handle-close-retry", "fake-kernel",
         lambda case: synthetic_close_failure(helper, case)),
        ("no-resource-run", "metadata-double",
         lambda case: synthetic_no_resource_run(helper, case)),
        ("batch-token-rejection", "source-metadata",
         lambda case: synthetic_batch_token_rejection(helper, case)),
        ("job-created-process-failed", "metadata-double",
         lambda case: synthetic_job_without_process(helper, case)),
        ("observation-failure-retry", "metadata-double",
         lambda case: synthetic_observation_retry(helper, case)),
        ("termination-failure-retry", "metadata-double",
         lambda case: synthetic_termination_retry(helper, case)),
        ("startup-failure-hold-recovery", "metadata-double",
         lambda case: synthetic_startup_hold(helper, case, fail_after_assignment=False,
                                             recover_delay=0.25, cleanup_seconds=0.15,
                                             expect_hold=True)),
        ("startup-failure-after-assignment", "metadata-double",
         lambda case: synthetic_startup_hold(helper, case, fail_after_assignment=True,
                                             recover_delay=0.0, cleanup_seconds=1.0,
                                             expect_hold=False)),
    ]

    try:
        synthetic_root = output / "synthetic"
        synthetic_root.mkdir()
        for name, kind, function in synthetic_cases:
            case = synthetic_root / name
            case.mkdir()
            details = function(case)
            summary["syntheticCases"].append({
                "name": name, "kind": kind,
                "evidenceClass": "metadata-only; not proof of Windows Job containment",
                "details": details,
            })
            helper.atomic_report(output / "controls.json", summary)

        if not args.synthetic_only:
            run_real_controls(helper, root, output, summary)

        summary["result"] = "SYNTHETIC_PASS" if args.synthetic_only else "PASS"
    except BaseException as error:
        summary["errors"].append(f"{type(error).__name__}: {error}")
        summary["result"] = "SYNTHETIC_FAIL" if args.synthetic_only else "FAIL"
    finally:
        summary["finishedAt"] = helper.now()
        helper.atomic_report(output / "controls.json", summary)
        print(f"OWNED_PROCESS_CONTROLS {summary['result']} scope={summary['scope']} "
              f"grant={summary['grant'] or '-'} synthetic={len(summary['syntheticCases'])} "
              f"real={len(summary['cases'])} report={output / 'controls.json'}", flush=True)
    return 0 if summary["result"] in ("PASS", "SYNTHETIC_PASS") else 1


if __name__ == "__main__":
    raise SystemExit(main())
