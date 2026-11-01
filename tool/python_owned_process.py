"""Run one Windows command in its own suspended-start Job, with durable evidence.

Importing this module starts no process, writes no file, and calls no Windows API.
OwnedJob is adapted from qfli_go/.trellis/tasks/10-22-go-offline-ide/research/
fixtures/run_native_window.py, itself adapted from qfli_note's run_host_window.py.

Only a terminal exact root HANDLE and Job ActiveProcesses == 0 permit release.
An exceeded cleanup observation budget means HOLD, not permission to abandon
handles: this same wrapper keeps observing and publishing until cleanup is real.
Callers must retain/poll the wrapper while HOLD; never kill by a looked-up PID.
Stdout/stderr go directly to an inherited unbuffered file, so no pipe can fill.
Batch commands use explicit cmd wrapping. Literal percent, exclamation, quote,
NUL and newline characters in batch tokens are rejected rather than expanded.
Native executable arguments use normal Windows CRT quoting without a shell.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import ctypes as C
from ctypes import wintypes as W
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import threading
import time


CREATE_SUSPENDED = 0x00000004
CREATE_NO_WINDOW = 0x08000000
KILL_ON_JOB_CLOSE = 0x00002000
WAIT_OBJECT_0 = 0
WAIT_TIMEOUT = 258
TIMEOUT_EXIT = 124
WRAPPER_ERROR_EXIT = 125
INTERRUPTED_EXIT = 130


class Limits(C.Structure):
    _fields_ = [("processTime", C.c_longlong), ("jobTime", C.c_longlong),
                ("flags", W.DWORD), ("minWs", C.c_size_t), ("maxWs", C.c_size_t),
                ("activeLimit", W.DWORD), ("affinity", C.c_size_t),
                ("priority", W.DWORD), ("scheduling", W.DWORD)]


class ExtendedLimits(C.Structure):
    _fields_ = [("basic", Limits), ("io", C.c_ulonglong * 6),
                ("processMemory", C.c_size_t), ("jobMemory", C.c_size_t),
                ("peakProcess", C.c_size_t), ("peakJob", C.c_size_t)]


class Accounting(C.Structure):
    _fields_ = [("times", C.c_longlong * 4), ("faults", W.DWORD),
                ("total", W.DWORD), ("active", W.DWORD), ("terminated", W.DWORD)]


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def atomic_report(path: Path, value: dict) -> None:
    """Replace one complete JSON report; never expose a partially written JSON."""
    descriptor, name = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
            json.dump(value, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def record_error(report: dict, label: str, error: BaseException) -> None:
    message = f"{label}: {type(error).__name__}: {error}"[:1024]
    counts = report.setdefault("errorCounts", {})
    if message not in counts and len(counts) >= 32:
        message = "Additional distinct errors omitted"
    counts[message] = counts.get(message, 0) + 1
    if message not in report["errors"]:
        report["errors"].append(message)


@contextmanager
def defer_interrupts():
    """A soft signal requests cleanup; it cannot interrupt handle acquisition."""
    received = []
    previous = []
    try:
        if threading.current_thread() is threading.main_thread():
            def receive(number, _frame):
                if number not in received:
                    received.append(number)

            for name in ("SIGINT", "SIGBREAK", "SIGTERM"):
                number = getattr(signal, name, None)
                if number is not None:
                    previous.append((number, signal.signal(number, receive)))
        yield received
    finally:
        for number, handler in reversed(previous):
            signal.signal(number, handler)


def absolute_against(cwd: Path, value: str | Path) -> Path:
    """Interpret a possibly relative caller path against the requested directory.

    Never relies on (or changes) the helper's process-wide current directory, so
    a relative PATH entry, COMSPEC or SystemRoot means what the requested cwd
    says it means, not where this wrapper happened to be started.
    """
    candidate = Path(value)
    return candidate if candidate.is_absolute() else cwd / candidate


def search_directories(cwd: Path, environment: dict[str, str]) -> list[Path]:
    """Expand the child PATH with every entry anchored at the requested directory."""
    value = environment.get("PATH", "")
    entries = [entry.strip('"') for entry in value.split(os.pathsep)]
    directories = [cwd if not entry else absolute_against(cwd, entry) for entry in entries]
    if os.curdir not in entries:
        # Match Windows/Python search order: the requested directory first.
        directories.insert(0, cwd)
    return directories


def executable_names(name: str, environment: dict[str, str]) -> list[str]:
    """Honor the child environment's PATHEXT instead of the wrapper's own."""
    value = environment.get("PATHEXT")
    if value is None:
        value = ".COM;.EXE;.BAT;.CMD"  # Windows default when the child omits it.
    extensions = [extension for extension in value.split(os.pathsep) if extension]
    lowered = name.lower()
    if any(lowered.endswith(extension.lower()) for extension in extensions):
        return [name]
    return [name, *(name + extension for extension in extensions)]


def find_executable(name: str, cwd: Path, environment: dict[str, str]) -> Path | None:
    for directory in search_directories(cwd, environment):
        for candidate_name in executable_names(name, environment):
            candidate = directory / candidate_name
            if candidate.is_file():
                return candidate.resolve()
    return None


def command_line(argv: list[str], cwd: Path, environment: dict[str, str]) -> tuple[str, str, dict]:
    """Resolve an executable; only .bat/.cmd explicitly enter the command shell."""
    if not argv or not all(isinstance(value, str) and "\0" not in value for value in argv):
        raise ValueError("Command must contain non-NUL string arguments")
    directory = Path(cwd).resolve()
    program = Path(argv[0])
    if program.is_absolute() or os.path.dirname(argv[0]):
        program = (directory / program).resolve(strict=True)
    else:
        found = find_executable(argv[0], directory, environment)
        if found is None:
            raise FileNotFoundError(f"Executable not found: {argv[0]}")
        program = found
    if not program.is_file():
        raise ValueError("Command executable is not a file")
    resolved = [str(program), *argv[1:]]
    if program.suffix.lower() not in (".bat", ".cmd"):
        return str(program), subprocess.list2cmdline(resolved), {
            "kind": "native-executable", "resolvedArgv": resolved,
        }
    # cmd has a separate grammar from the CRT. Quote every token, disable
    # delayed expansion, and reject characters whose literal meaning is not
    # preserved through the batch expansion boundary. No shell=True fallback.
    if any(any(character in token for character in '%!"\r\n\0') for token in resolved):
        raise ValueError("Batch tokens cannot contain percent, exclamation, quote, NUL or newline")
    system_root = environment.get("SystemRoot") or environment.get("SYSTEMROOT")
    shell = environment.get("COMSPEC") or environment.get("ComSpec")
    if shell is None and system_root:
        shell = str(absolute_against(directory, system_root) / "System32/cmd.exe")
    if not shell:
        raise ValueError("An explicit Windows cmd.exe path is required for batch commands")
    shell_path = absolute_against(directory, shell).resolve(strict=True)
    if not shell_path.is_file() or shell_path.name.lower() != "cmd.exe":
        raise ValueError("Batch interpreter must be an existing cmd.exe")
    tokens = " ".join('"' + token + '"' for token in resolved)
    prefix = subprocess.list2cmdline([str(shell_path), "/d", "/v:off", "/s", "/c"])
    return str(shell_path), prefix + ' "' + tokens + '"', {
        "kind": "explicit-cmd-batch", "resolvedArgv": resolved,
        "interpreter": str(shell_path), "delayedExpansion": False,
    }


class OwnedJob:
    """Retain exactly the handles returned for one private Job and root process."""

    def __init__(self):
        if os.name != "nt":
            raise OSError("OwnedJob requires Windows")
        self.k = C.WinDLL("kernel32", use_last_error=True)
        signatures = {
            "CreateJobObjectW": ([C.c_void_p, W.LPCWSTR], W.HANDLE),
            "SetInformationJobObject": ([W.HANDLE, C.c_int, C.c_void_p, W.DWORD], W.BOOL),
            "QueryInformationJobObject": ([W.HANDLE, C.c_int, C.c_void_p, W.DWORD, C.c_void_p], W.BOOL),
            "AssignProcessToJobObject": ([W.HANDLE, W.HANDLE], W.BOOL),
            "TerminateJobObject": ([W.HANDLE, W.UINT], W.BOOL),
            "TerminateProcess": ([W.HANDLE, W.UINT], W.BOOL),
            "ResumeThread": ([W.HANDLE], W.DWORD),
            "CloseHandle": ([W.HANDLE], W.BOOL),
            "WaitForSingleObject": ([W.HANDLE, W.DWORD], W.DWORD),
            "GetExitCodeProcess": ([W.HANDLE, C.POINTER(W.DWORD)], W.BOOL),
            "GetProcessId": ([W.HANDLE], W.DWORD),
            "GetProcessTimes": ([W.HANDLE] + [C.POINTER(W.FILETIME)] * 4, W.BOOL),
        }
        for name, (arguments, result) in signatures.items():
            function = getattr(self.k, name)
            function.argtypes, function.restype = arguments, result
        self.job = self.process = self.thread = None
        self.confirmed_empty = False
        self.record = {
            "rootCreated": False, "terminal": True, "exitCode": None,
            "jobActiveProcesses": None, "assignedBeforeResume": False,
            "createdSuspended": False, "resumed": False, "handlesClosed": False,
        }

    @staticmethod
    def check(value):
        if not value:
            raise C.WinError(C.get_last_error())

    def open(self) -> None:
        # Separate from construction so a partial configuration failure still
        # leaves the object and its exact Job handle available to the caller.
        self.job = self.k.CreateJobObjectW(None, None)
        self.check(self.job)
        self.record.update(jobHandleDecimal=str(self.job), jobHandleHex=hex(self.job))
        limits = ExtendedLimits()
        limits.basic.flags = KILL_ON_JOB_CLOSE  # No breakaway flags.
        self.check(self.k.SetInformationJobObject(self.job, 9, C.byref(limits), C.sizeof(limits)))

    def start(self, application: str, line: str, cwd: Path, environment: dict,
              log, on_assigned=None) -> None:
        import _winapi
        import msvcrt

        if self.job is None or self.process is not None:
            raise RuntimeError("Start requires one initialized empty private Job")
        with open(os.devnull, "rb") as null:
            handles = [msvcrt.get_osfhandle(stream.fileno()) for stream in (null, log, log)]
            unique = list(dict.fromkeys(handles))
            previous = [(handle, os.get_handle_inheritable(handle)) for handle in unique]
            try:
                for handle in unique:
                    os.set_handle_inheritable(handle, True)
                startup = subprocess.STARTUPINFO()
                startup.dwFlags = subprocess.STARTF_USESTDHANDLES
                startup.hStdInput, startup.hStdOutput, startup.hStdError = handles
                startup.lpAttributeList = {"handle_list": unique}
                hp, ht, pid, tid = _winapi.CreateProcess(
                    application, line, None, None, True,
                    CREATE_SUSPENDED | CREATE_NO_WINDOW, environment, str(cwd), startup,
                )
                # Signals are deferred by run_owned. Store both returned handles
                # immediately, even if identity capture or Job assignment fails.
                self.process, self.thread = hp, ht
                self.record.update(
                    rootCreated=True, terminal=False, createdSuspended=True,
                    processHandleDecimal=str(hp), processHandleHex=hex(hp),
                    threadHandleDecimal=str(ht), threadHandleHex=hex(ht),
                    pid=pid, threadId=tid, createdObservedAt=now(),
                )
                stamps = [W.FILETIME() for _ in range(4)]
                self.check(self.k.GetProcessTimes(hp, *(C.byref(stamp) for stamp in stamps)))
                self.record["creationFiletime100ns"] = str(
                    (stamps[0].dwHighDateTime << 32) | stamps[0].dwLowDateTime)
                if self.k.GetProcessId(hp) != pid:
                    raise RuntimeError("Exact created root HANDLE/PID mismatch")
                self.check(self.k.AssignProcessToJobObject(self.job, hp))
                self.record["assignedBeforeResume"] = True
                if on_assigned is not None:
                    on_assigned()  # Persist exact identity while still suspended.
                resumed = self.k.ResumeThread(ht)
                self.record["resumePreviousSuspendCount"] = int(resumed)
                if resumed != 1:
                    raise RuntimeError("Root did not resume from its single creation suspension")
                self.record["resumed"] = True
            finally:
                # Do not discard an owned process/thread if restoration fails.
                errors = []
                for handle, inherit in previous:
                    try:
                        os.set_handle_inheritable(handle, inherit)
                    except OSError as error:
                        errors.append(str(error))
                if errors:
                    raise RuntimeError("Restore inherited handle flags: " + "; ".join(errors))

    def empty(self) -> bool:
        if self.job is None:
            if self.process is not None:
                raise RuntimeError("Cannot observe a live root without its retained private Job")
            self.record.update(terminal=True, jobActiveProcesses=0, lastObservedAt=now())
            return True  # Job/root creation never succeeded.
        terminal = self.process is None
        if self.process is not None:
            status = self.k.WaitForSingleObject(self.process, 0)
            if status not in (WAIT_OBJECT_0, WAIT_TIMEOUT):
                raise C.WinError(C.get_last_error())
            terminal = status == WAIT_OBJECT_0
            if terminal:
                code = W.DWORD()
                self.check(self.k.GetExitCodeProcess(self.process, C.byref(code)))
                self.record["exitCode"] = int(code.value)
        info = Accounting()
        self.check(self.k.QueryInformationJobObject(self.job, 1, C.byref(info), C.sizeof(info), None))
        self.record.update(terminal=terminal, jobActiveProcesses=int(info.active), lastObservedAt=now())
        if terminal and info.active and "rootTerminalWithChildren" not in self.record:
            self.record["rootTerminalWithChildren"] = {
                "observedAt": now(), "exitCode": self.record["exitCode"],
                "jobActiveProcesses": int(info.active), "releaseRejected": True,
            }
        return terminal and info.active == 0

    def stop(self, code: int) -> None:
        self.record["ownedJobTerminationRequested"] = True
        errors = []
        if self.job is not None and not self.k.TerminateJobObject(self.job, code):
            errors.append(f"TerminateJobObject: {C.get_last_error()}")
        if self.process is not None and not self.record["assignedBeforeResume"]:
            # The only permitted direct termination: our exact never-resumed
            # root handle, retained after its own partial startup failure.
            if not self.k.TerminateProcess(self.process, code):
                errors.append(f"TerminateProcess own suspended root: {C.get_last_error()}")
            self.record["unassignedSuspendedRootTerminationRequested"] = True
        if errors:
            raise RuntimeError("; ".join(errors))

    def close_confirmed(self) -> None:
        if not self.confirmed_empty:
            raise RuntimeError("Cannot close handles before exact root terminal AND private Job empty")
        errors = []
        for name in ("thread", "process", "job"):
            handle = getattr(self, name)
            if handle is None:
                continue
            if self.k.CloseHandle(handle):
                setattr(self, name, None)
            else:
                errors.append(f"CloseHandle {name}: {C.get_last_error()}")
        self.record["handlesClosed"] = all(
            handle is None for handle in (self.thread, self.process, self.job))
        if errors:
            raise RuntimeError("; ".join(errors))


def publish(report: dict, path: Path, started: float) -> None:
    report.update(updatedAt=now(), elapsedSeconds=round(time.monotonic() - started, 3))
    atomic_report(path, report)


def safe_publish(report: dict, path: Path, started: float) -> None:
    try:
        publish(report, path, started)
    except BaseException as error:
        record_error(report, "Durable state publication", error)


def drain(job: OwnedJob, report: dict, path: Path, started: float,
          cleanup_seconds: float, termination_code: int) -> None:
    """Never return with unconfirmed cleanup, including after soft interrupts."""
    deadline = time.monotonic() + cleanup_seconds
    report.update(state="CLEANUP", cleanupStartedAt=now())
    safe_publish(report, path, started)
    next_stop = 0.0
    next_hold = deadline
    while True:
        try:
            if not job.confirmed_empty:
                job.confirmed_empty = job.empty()
            report["cleanupConfirmed"] = job.confirmed_empty
            if job.confirmed_empty:
                job.close_confirmed()
                report["cleanupConfirmedAt"] = now()
                report["cleanupWithinDeadline"] = time.monotonic() <= deadline
                return
        except BaseException as error:
            report["cleanupConfirmed"] = job.confirmed_empty
            record_error(report, "Exact-handle cleanup observation/closure", error)
        current = time.monotonic()
        if not job.confirmed_empty and current >= next_stop:
            try:
                job.stop(termination_code)
            except BaseException as error:
                record_error(report, "Owned termination request", error)
            next_stop = current + 5
        if current >= next_hold:
            report.update(state="HOLD_UNRELEASED", release="HOLD_UNRELEASED",
                          cleanupDeadlineExceeded=True, handlesRetained=True)
            report["holdPublicationCount"] = report.get("holdPublicationCount", 0) + 1
            safe_publish(report, path, started)
            process = job.record
            try:
                print(
                    "HOLD_UNRELEASED "
                    f"HANDLE={process.get('processHandleDecimal')} PID={process.get('pid')} "
                    f"FILETIME={process.get('creationFiletime100ns')} "
                    f"jobHANDLE={process.get('jobHandleDecimal')} "
                    f"terminal={process.get('terminal')} active={process.get('jobActiveProcesses')} "
                    f"report={path}; retain/poll this wrapper", flush=True,
                )
            except BaseException as error:
                record_error(report, "HOLD stdout publication", error)
            next_hold = current + 5
        try:
            time.sleep(1 if current >= deadline else 0.05)
        except BaseException as error:
            record_error(report, "Cleanup interrupted; exact handles retained", error)


def positive_seconds(value: str | float) -> float:
    result = float(value)
    if not math.isfinite(result) or result <= 0:
        raise ValueError("Seconds must be finite and positive")
    return result


def run_owned(argv: list[str], *, timeout_seconds: float, cleanup_seconds: float,
              cwd: str | Path, log_path: str | Path, report_path: str | Path,
              environment: dict[str, str] | None = None) -> dict:
    """Run exactly one command; return only after terminal+empty and handle closure.

    The timeout bounds work observation, not an OS termination guarantee. If
    cleanup cannot be confirmed within cleanup_seconds, this call stays alive
    in HOLD and retains exact handles. No new command is started in that state.
    """
    timeout_seconds = positive_seconds(timeout_seconds)
    cleanup_seconds = positive_seconds(cleanup_seconds)
    directory = Path(cwd).resolve(strict=True)
    if not directory.is_dir():
        raise ValueError("cwd must be an existing directory")
    log_path, report_path = Path(log_path).resolve(), Path(report_path).resolve()
    if log_path == report_path:
        raise ValueError("Log and report must be different files")
    log_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    report = {
        "schemaVersion": 1, "state": "STARTING", "release": "HOLD_UNRELEASED",
        "wrapperPid": os.getpid(), "startedAt": now(), "command": list(argv),
        "cwd": str(directory), "logPath": str(log_path), "reportPath": str(report_path),
        "logMode": "combined inherited unbuffered file; no pipe reader",
        "timeoutSeconds": timeout_seconds, "cleanupSeconds": cleanup_seconds,
        "timedOut": False, "cleanupConfirmed": False, "exitCode": None,
        "process": None, "errors": [],
    }
    # Failure to establish initial durable evidence must precede process creation.
    publish(report, report_path, started)
    job = None
    log = None
    outcome = None
    termination_code = WRAPPER_ERROR_EXIT
    with defer_interrupts() as interrupts:
        try:
            log = log_path.open("wb", buffering=0)
            child_environment = dict(os.environ if environment is None else environment)
            application, line, invocation = command_line(list(argv), directory, child_environment)
            report["invocation"] = invocation
            job = OwnedJob()
            report["process"] = job.record
            job.open()
            job.start(application, line, directory, child_environment, log,
                      on_assigned=lambda: publish(report, report_path, started))
            report["state"] = "RUNNING"
            publish(report, report_path, started)
            deadline = started + timeout_seconds
            next_update = time.monotonic() + 1
            while True:
                if job.empty():
                    break
                current = time.monotonic()
                if current >= deadline:
                    report["timedOut"] = True
                    outcome = termination_code = TIMEOUT_EXIT
                    break
                if interrupts:
                    outcome = termination_code = INTERRUPTED_EXIT
                    break
                if current >= next_update:
                    publish(report, report_path, started)
                    next_update = current + 1
                time.sleep(0.05)
        except BaseException as error:
            outcome = INTERRUPTED_EXIT if isinstance(error, KeyboardInterrupt) else WRAPPER_ERROR_EXIT
            termination_code = outcome
            record_error(report, "Command startup/execution", error)
        finally:
            if job is not None:
                drain(job, report, report_path, started, cleanup_seconds, termination_code)
            else:
                report["cleanupConfirmed"] = True  # No private Job/root was created.
                report["cleanupWithinDeadline"] = True
            if log is not None:
                try:
                    log.flush()
                    os.fsync(log.fileno())
                except BaseException as error:
                    record_error(report, "Final log flush", error)
                    outcome = WRAPPER_ERROR_EXIT if outcome is None else outcome
                try:
                    log.close()
                except BaseException as error:
                    record_error(report, "Final log close", error)
                    outcome = WRAPPER_ERROR_EXIT if outcome is None else outcome
            if interrupts:
                report["interruptSignals"] = list(interrupts)
                if outcome is None:
                    outcome = INTERRUPTED_EXIT
            if outcome is None:
                outcome = job.record["exitCode"] if job is not None else WRAPPER_ERROR_EXIT
                if report["errors"]:
                    outcome = WRAPPER_ERROR_EXIT
            if outcome is None:
                outcome = WRAPPER_ERROR_EXIT
            report.update(
                state="FINISHED", release="RELEASE", handlesRetained=False,
                finishedAt=now(), exitCode=int(outcome),
                result="TIMED_OUT" if report["timedOut"] else ("SUCCESS" if outcome == 0 else "FAILED"),
            )
            publish(report, report_path, started)
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout-seconds", type=positive_seconds, required=True)
    parser.add_argument("--cleanup-seconds", type=positive_seconds, required=True)
    parser.add_argument("--cwd", default=".")
    parser.add_argument("--log", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("Specify -- followed by executable and arguments")
    try:
        report = run_owned(command, timeout_seconds=args.timeout_seconds,
                           cleanup_seconds=args.cleanup_seconds, cwd=args.cwd,
                           log_path=args.log, report_path=args.report)
    except BaseException as error:
        print(f"OWNED_PROCESS wrapper failure: {type(error).__name__}: {error}", flush=True)
        return WRAPPER_ERROR_EXIT
    process = report["process"] or {}
    try:
        print(f"OWNED_PROCESS {report['result']} exit={report['exitCode']} "
              f"rootExit={process.get('exitCode')} terminal={process.get('terminal')} "
              f"active={process.get('jobActiveProcesses')} cleanup={report['cleanupConfirmed']} "
              f"report={report['reportPath']}", flush=True)
    except OSError:
        pass  # A closed caller stdout cannot change the already recorded exit.
    return report["exitCode"]


if __name__ == "__main__":
    raise SystemExit(main())
