# Owned Windows process helper: independent static review

Date: 2026-10-24. Reviewer: `/root/python_debugger_adapter`.

Reviewed `tool/python_owned_process.py` and
`test/python_owned_process_control_test.py`. Read the builder's
`Invoke-AuditTool` call boundary and the original peer fixture for context. Only
this note was written. No helper, control, SDK/compiler/native command, Dart or
Flutter process, build, signing command, device, or emulator was executed.

## Conclusion

No source-confirmed early-release path was found in this revision: successful
release requires the retained root process HANDLE to be terminal, the private
Job's active process count to be zero, and retained thread/process/Job handles
to close successfully. Failure to observe cleanup or close handles remains in
the same wrapper's retry/HOLD loop. Root success with a live child is explicitly
rejected. This is a source review, not Windows runtime or control-test evidence.

There are two P2 corrections for the executable/control boundary and an open
failure-path coverage gate. The helper author independently acknowledged the
relative-PATH resolution issue. Root owns coordinating any source repair.

## Findings

### 1. P2: relative PATH entries resolve against the wrapper's directory

`tool/python_owned_process.py:119`–`:126` resolves an explicitly relative
executable against the supplied `cwd`, but a bare command uses
`shutil.which(argv[0], path=environment.get("PATH", ""))`, then resolves the
returned path without the supplied directory. Neither operation receives that
directory. `run_owned` does not change the wrapper's current directory before
calling it (`:400`, `:428`).

For example, if the wrapper is in repository A, the caller requests `cwd=B`,
and PATH contains `.\bin`, a bare `tool.exe` can resolve to A's `bin/tool.exe`
instead of B's. The resolved wrong executable is then launched explicitly in
B, and its successful exit can be reported as success. A matching command
present only in B can instead be reported missing. Relative `COMSPEC` values
are likewise resolved without the supplied directory (`:145`).

Minimal correction: resolve relative search entries and a relative interpreter
path against the requested directory without changing the process-wide cwd,
or reject ambiguous relative search inputs and require an absolute executable.
Honor the actual child environment's executable-extension policy as part of
that resolution. Add metadata-only coverage with distinct A/B directory trees;
no process needs to start to verify the selected application/command line.

The builder's current absolute resolved tool paths avoid this specific relative
search trigger; that does not correct the general helper API.

### 2. P2: Python optimization disables all control acceptance checks

`test/python_owned_process_control_test.py:31`–`:38` and all per-case result/log
checks at `:78`–`:111` use bare `assert`. The script does not reject optimized
Python execution. With `python -O` or inherited `PYTHONOPTIMIZE`, the checks are
removed while the unconditional `summary["result"] = "PASS"` remains at `:112`.
An incorrect command exit, lost output, incorrect batch quoting, or a malformed
cleanup result can therefore escape the intended checks and still yield PASS.

Minimal correction: use an always-on `require(condition, evidence)` that raises
on failure, or reject `sys.flags.optimize != 0` before creating evidence or
starting any child. The latter is sufficient to keep the currently prepared
control invocation honest. Add a metadata-only regression for the rejection or
the always-on check, without running a control child during a source-only gate.

### 3. Open gate: the controls do not exercise startup failure or HOLD recovery

The five prepared cases cover normal output, nonzero exit, an ordinary timeout,
root exit with a live child, and one `.cmd` quoted-argument case. They check the
eventual complete report and its durable copy. They do not inject or observe:

- Failure before Job creation or after Job creation but before process creation.
- Failure after `CreateProcess` returns its exact process/thread handles,
  including identity capture, Job assignment, suspended-state report publishing,
  or `ResumeThread` failure.
- A failed termination request that later succeeds, a failed observation that
  later succeeds, or partial handle closure followed by a successful retry.
- Cleanup past its budget, an actual durable `HOLD_UNRELEASED` state, retained
  handles during HOLD, and later recovery to RELEASE.
- Interrupts during startup/cleanup, log/report I/O failure, or the rejected
  batch-token characters.

The `root-exit-live-child` case is a useful negative release control, but its
ordinary successful timeout drain does not exercise `drain`'s HOLD branch.
Add deterministic fault-injection metadata controls for the no-resource and
retained-handle state machine branches, then run the real existing controls
only in a new named window. Metadata doubles should not be labeled as proof of
Windows Job containment, actual HANDLE lifetime, or real shell quoting.

## Specific checked paths

### No-resource open failure does not query a null Job in this revision

Root explicitly requested this check. The registered return type for
`CreateJobObjectW` is `W.HANDLE` (`:164`). Its null result leaves `self.job` as
`None`, while the already constructed object remains reachable from `run_owned`.
`OwnedJob.empty` has an explicit `self.job is None` / `self.process is None`
branch at `:261`–`:265`; it records terminal/zero-active and returns true before
the Job query at `:277`. `close_confirmed` then finds no handles and marks
`handlesClosed=True`. The recorded startup exception keeps the outcome at 125.

Thus a failed Job creation with no process is a vacuous cleanup/error RELEASE,
not an endless HOLD, in the exact reviewed source. A regression should preserve
this branch. A failure configuring an already created Job takes the different
path of querying and closing that real retained empty Job.

### Suspended startup and partial failure

- `CreateProcess` receives `CREATE_SUSPENDED | CREATE_NO_WINDOW` (`:221`–`:224`).
  The returned process and thread handles are stored before identity capture,
  Job assignment, suspended-state publication, or resume (`:227`–`:248`).
- Job limits enable kill-on-close without breakaway flags (`:199`–`:201`).
  Assignment precedes resume. The successful previous suspend count must be one.
- If assignment has not succeeded, `stop` may terminate only the exact retained
  never-resumed root handle, in addition to the private Job (`:286`–`:298`). It
  does not look up a process or terminate a process from a supplied PID.
- The shared log/standard-input handles use an explicit unique inherited handle
  list. Original inheritance flags are restored in `finally`; restoration
  failures become wrapper errors without discarding owned process handles.
- Main-thread soft signals are converted to cleanup requests over the entire
  acquisition/observation/drain scope. Abrupt process termination remains outside
  the cooperative retained-wrapper guarantee.

### Observation, cleanup, errors, and limits

- A root exit is checked through its exact process handle and coupled with a
  fresh Job accounting query. A root exit with active children records the
  rejected release observation (`:260`–`:284`).
- `drain` only closes handles after confirmed emptiness. It retains failed
  closures for retry; after partial closure it does not falsely claim every
  handle is closed (`:300`–`:315`, `:338`–`:350`).
- Once the cleanup observation budget is exceeded, the report remains
  `HOLD_UNRELEASED`, records the retained identity, and continues observation and
  termination/closure retries. The method does not return simply because the
  cleanup budget expired (`:330`–`:379`). No hard upper bound on termination is
  claimed. The caller must keep that wrapper alive and drain/poll its output.
- Initial durable evidence is required before process creation (`:418`–`:419`).
  A publication failure during startup/execution enters cleanup. Repeated
  cleanup publication failures are accumulated with bounded distinct error
  messages. Final durable publication can still fail after resources are safely
  closed; the CLI then returns the wrapper error rather than normal success.
- Child stdout/stderr use one inherited unbuffered file, avoiding a child-output
  pipe reader. The helper has no output byte cap; its work deadline is an
  observation limit, not a filesystem or OS scheduling/termination guarantee.
- The HOLD status print is synchronous. The current builder drains it through
  `Out-Null`; other callers must also drain it. A non-reading caller can block
  repeated stdout publication. Durable report polling plus bounded/nonblocking
  optional diagnostics would make that broader embedding case more robust.

### Batch command boundary

The source resolves `.bat`/`.cmd` to an explicit existing `cmd.exe`, uses
`/d /v:off /s /c`, adds outer `/c` quotes, and separately quotes every resolved
batch token. It rejects percent, exclamation, embedded quote, NUL, CR and LF
rather than passing them across batch expansion. Native executables use CRT
argument quoting without a shell (`:115`–`:153`). The prepared `.cmd` fixture
tests a space plus `&` and parentheses, but none of these controls was run in
this review. Batch scripts' own later expansion/requoting remains their code's
responsibility; the helper does not make an arbitrary batch body literal-safe.

## Reviewed source identities

These hashes describe inspected files, not executed inputs or test passes:

| File | SHA256 |
| --- | --- |
| `tool/python_owned_process.py` | `ff781c38316ae0a8312d5115f90bfbfdbce9a0db5ed22d6bd7d1f4a6d21b2d55` |
| `test/python_owned_process_control_test.py` | `ed4404db0e7a63aa99aa5f9a07d8feee63feb5d649eb3a14b5081b4f41ae8346` |

The root's separately reported metadata-only results are not rerun or enlarged
by this review. All real helper/control execution and all heavy native/build/
device acceptance gates remain UNRUN here.
