# Independent debugger audit review

Date: 2026-10-24. Scope: read-only review of the audit harness, preparation
script and focused tests. No Dart, Flutter, analyzer, test, compiler, build or
device process was run. Findings below are confirmed from source data flow;
fault-injection execution remains pending a new coordinator-owned host window.

Reviewed hashes:

- `tool/python_debugger_ohos_audit.dart`:
  `c6c75d3bef397b82d85298197c56fa2a5d12038df87959b5240a5d4ab41e19fe`
- `tool/prepare_python_debugger_audit.py`:
  `f287fbdadfbe4171c2d114c124aaf8c0dacd749e4329a8e90f84a1e4319b8308`
- `test/python_debugger_audit_test.dart`:
  `ee971ee1c70d31ebb15c892cd5d6c16730cdf2dcaba7d5588c7d33fd7d8209a1`

Line numbers refer to those snapshots. Root accepted findings 1–3 and authorized
the audit owner to repair them in source. Findings 4–5 were sent to root and the
same owner separately; this reviewer did not edit the targets.

## Source-confirmed defects

### 1. Stale-token rejection has no finite deadline

At harness line 258 the first scenario directly awaits
`_rejects(() => session.session.command(...old token...))`. `_rejects` at line 495
directly awaits the provided future. Unlike normal command dispatch, this call
bypasses `tracker.wait`. A regression returning an unresolved stale-command
future prevents the scenario from reaching its catch/finally, final disposal,
settle deadline, and final durable report.

Minimal repair: bound the whole rejection assertion through `tracker.wait`, or
pass the tracker into the helper and preserve timeout classification. Keep the
underlying future observed after timing out. Add a controlled session that
reaches the stale-token assertion and never settles that command; the audit must
return a failed/timeout report within its finite deadlines, request cleanup, and
retain files until actual exit. Current doubles stall the first Step Over,
before reaching the stale-token branch, so they cannot detect this defect.

### 2. Failed sessions can satisfy expected success/Stop exits

`_ObservedSession.finished` at lines 612–621 checks `snapshot.isTerminal` and the
integer exit code. For expected exit 0 or 130 it does not require
`DebugPhase.terminated`. The actual Python adapter can report `failed` together
with real exit 0/130 when an operational debugger failure occurred. Such a
snapshot can satisfy this helper, and `_ObservedSession.observe` does not add a
contract error simply because the phase is failed. The explicit runtime-error
scenario separately checks `failed`, but the success/Stop cases do not.

Minimal repair: require terminated for expected successful/cooperative-Stop
cases, and failed for the explicit runtime-exception case. Keep the real exit
code and useful message. Add a fault session that ends with `failed`, exit 0
and an operational error, with otherwise correct output; it must not pass.
Equivalent coverage for failed/130 protects the Stop gate.

### 3. Early recovery stream errors lack immediate observation

`normalRun` at lines 214–220 starts stdout/stderr `toList()` futures, then awaits
the actual exit before attaching await/error handling to those futures. If a
stream fails before exit, its future can emit an unhandled zone error while the
native worker is still active. Observing the enclosing pending routine does not
attach a handler to these separate drain futures during the exit wait.

Minimal repair: observe both drain futures immediately and retain an independent
actual-exit observation. Surface drain errors as case failures only after native
settlement, or retain the project and pending exit if the deadline is exceeded.
Use the meaningful early-stream-error/delayed-exit regression already present in
the content audit as a pattern. Current debugger audit runner doubles only
override probing and do not reach this stream-failure path.

### 4. Final observation cancellation bypasses cleanup deadlines

Finalization line 486 awaits every `closeObservation()` directly. At line 641
this is an unbounded `subscription.cancel()`. A stream with a stalled asynchronous
onCancel future can therefore hang the overall audit after the finite settle
deadline and after writing a finished report. A cancellation exception can also
escape after the report already states a successful final result.

Severity is medium: the current production adapter uses an ordinary broadcast
controller with immediate cancellation, but the audit explicitly supports
injected failure providers and promises finite bookkeeping. Observe and bound
cancellation, include unsettled cancellation/errors in cleanup evidence, and
only freeze the final report afterward. Add a cancellation-future-never-settles
double. Do not convert a timeout into successful cleanup.

### 5. Late launches mutate the returned report after it is frozen on disk

The launch callback around line 186 always executes `snapshots.add(record)`.
Only the following `append` call checks `journalOpen`. After the audit returns an
unsettled-launch failure, a late session is correctly disposed, but its initial
and final snapshots append to the same list retained in `report['snapshots']`.
The durable file stays unchanged; the already-returned evidence object does not.

This does not manufacture a successful device gate: the original cleanup flag
remains false. It does make two representations of the returned result diverge.
Gate recording once final evidence is frozen while continuing actual late
cleanup. Extend the existing late-launch test to compare a serialized copy of
the returned report before/after settlement, as well as durable file bytes.

## Correct boundaries and acceptable tradeoffs

- `_Pending.wait` observes the original operation and applies a separate timeout;
  timeout does not cancel the actual worker or imply native exit.
- Debug `done` is observed separately as soon as a session exists. Late launch
  results are registered and disposed when `tracker.closing` is true. Pending
  operations, failed disposal, missing done, open updates or contract errors
  prevent cleanup acceptance and keep the work directory.
- The settle loop rechecks the pending set after each batch, so a launch that
  settles during cleanup can add its actual-exit/disposal futures without being
  mistaken for an empty cleanup set.
- Debug output compares retained strings exactly; ordinary Run compares line
  streams and explicitly states that final LF cannot be distinguished. There is
  no claim of raw-byte Run fidelity.
- Runtime-error inspection checks actual locals/container bounds and zero
  representation-hook effects. The main scenario checks a real side effect is
  absent before its breakpoint, then present after Continue, and compares an
  ordinary nondebug run. These are meaningful behavior assertions.
- Overrides of debugger, runner or assets force both runtime gate flags false.
  An ordinary host cannot satisfy `deviceGatePassed`. The report explicitly
  requires independent signed-HAP/native-SO binding. A device runtime flag is
  therefore only one release gate, not proof of the final HAP/source identity or
  interactive editor UI acceptance.
- Preparation records declared source/core/asset/native hashes and checks
  manifest digests and mirrored ArkTS parity. Its ELF-header/architecture check
  plus raw symbol-name search is a conservative old-library filter, not export,
  dependency or OHOS ABI proof. The script's comments/evidenceKind correctly
  leave actual packaged symbol/dependency/signature/binary binding to external
  verification. Its selected sourceDigests must not be described as every input
  to the complete native build.

## Test strength and remaining coverage

The existing unavailable, suite mismatch and asset drift tests genuinely check
that no debug worker is submitted. The late-launch test checks cleanup still
happens after timeout without rewriting durable evidence. The pending-disposal
test would fail if the audit deleted files or marked cleanup successful before
the fake actual-exit future settled. The failed-pause test verifies disposal,
actual done and stream closure separately. The production test invokes the real
adapter/VM and requires seven scenarios plus ordinary recovery while keeping the
OHOS gate false on host.

In addition to findings 1–5, current installed scenarios await `finished()` after
Stop/dispose returns. They establish eventual actual exit and safe file cleanup,
but do not directly assert that Stop/dispose itself waited for actual exit before
returning. A broken early-returning implementation might still pass if exit
follows before the later finished/cleanup checks. Existing product adapter tests
cover this ordering with delayed workers; stronger audit coverage should record
doneObserved at control-return time and inject early-returning Stop/dispose to
prove the installed harness enforces that ordering too.

All newly recommended fault cases and all repairs need the next named host
window. This review provides no new host pass or installed-device acceptance.
