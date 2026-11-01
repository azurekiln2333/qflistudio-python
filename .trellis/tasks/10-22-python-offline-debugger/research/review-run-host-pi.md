# Reviewer note — `run_python_host.py` fixture + `python_debugger_ohos_audit.dart`

- Reviewer: `trellis-check` (read-only; no personnel dispatched)
- Task: `.trellis/tasks/10-22-python-offline-tools`
- Time: 2026-10-26T02:33+08:00
- Method: source review plus synthetic double-backed probes. **No real child
  process, Flutter/Dart test, native build, SDK, device, or signing command ran.**
- Do not overwrite p4's files from this note; treat it as input to p4/root.

## Snapshot identities

Both files changed under concurrent edits during this review (the runner hash
moved `CF6F40B1…` → `BA667B8C…`, the test hash moved to `FC8F919E…`). Re-hash
before acting on any finding.

| File | SHA256 at review |
| --- | --- |
| `tool/python_debugger_ohos_audit.dart` | `5E4D0E9DE2EA863DE41BA2A411175E276BA819E208AED925211059C7C307EFBB` |
| `test/python_debugger_audit_test.dart` | `FC8F919E541015048232ADA7331B21CC6C0EE54AF566E5FF812D82D72DAA44F4` |
| `.trellis/tasks/10-22-python-offline-debugger/research/fixtures/run_python_host.py` | `BA667B8C8F505C829F45BD5847B6280F66AD478CE8C18B71790A1442404A105E` |

## Scope (requested focus areas)

1. Real child-process time budget for tests.
2. Failure cleanup / handle retention.
3. Source binding (file hashes).
4. Runner `--grant` / `--next-owner` enforcement.
5. Correctness of the five audit repairs.

## Verified correct

1. **Repair 1 — stale token is bounded, not fatal.** `_rejects` goes through
   `_Pending.wait`, which bounds the stale command with a `TimeoutException` while
   leaving the underlying operation observed. Test `_Fault.staleHang` expects
   `status == 'timeout'`, `cleanupConfirmed == false`, work dir retained, and
   `disposeCalls == 1`. Consistent with the source.
2. **Repair 2 — `failed` is a terminal phase that can carry exit 0 or 130.**
   Confirmed against core `debug_session.dart`: `isTerminal => terminated || failed`
   and there is **no `stopped`** value. Fault doubles exercise both branches:
   `_Fault.failedExit0` (`finished` never reaches `terminated`) and
   `_StopFailureSession.stop()` setting `DebugPhase.failed, exitCode: 130`. Correct.
3. **Repair 3 — both drains are observed before the native exit is awaited.**
   `normalRun` observes `stdout`/`stderr`/exit (`python_debugger_ohos_audit.dart`
   L223–L228), so an early stream error cannot become an unhandled zone error.
   `_ScriptedRunner(earlyDrain: true)` injects an early `stdout` error and the test
   asserts the case error contains `stdout`. Correct.
4. **Repair 5 — evidence freezes after cancellation.** `evidenceFrozen` gates the
   snapshot callback (L195, L202, L504) and `journalOpen` gates late appends
   (L155, L506); `snapshots.add` is guarded (L197); `report['snapshots']` is later
   compared against the durable bytes. Correct.
5. **Runner guards.** `--grant` and `--next-owner` are required and reject empty
   and `REPLACE_` prefixes (`run_python_host.py` L300–L305, L267–L268). In-run
   controls are mandatory before focused phases; a controls cleanup failure raises
   `Controls did not confirm exact cleanup; HOLD` (L176–L177) and a non-zero
   controls exit raises `Controls exited nonzero; no later phase started` (L178).
   A supplied `--controls-report` must be same-grant and `result == "PASS"` (L182–L190).
   Verified with a synthetic double: controls exit 1 with confirmed cleanup stops
   after the controls phase (later phases executed: 0).

## Findings

### P1 — `cleanupErrors` does not carry stalled-cancellation diagnostics; `test/python_debugger_audit_test.dart:178` cannot be reliably satisfied

- `_closeObservation` writes the stalled-cancellation failure to the **session**
  `errors` list:
  - `tool/python_debugger_ohos_audit.dart:690/694/696`
    (`Update stream cancellation did not settle: …`)
  - surfaced as `report['sessions'][i]['contractErrors']` (L702).
- `report['cleanupErrors']` is `_Pending.errors` only: L483
  `report['cleanupErrors'] = tracker.errors.toList();`. `_Pending.errors` receives
  a `cancellation` string only from `background(...)` when a runner-cancel
  operation throws (label `runner cleanup cancellation`, L709/L731).
- The stalled-cancel test (`test/python_debugger_audit_test.dart:171–182`) uses
  `_ControlledDebugger(… stalledCancel: true)` whose `_StalledSubscription.cancel()`
  returns a never-completing future (L334). The only entry that contains the word
  `cancellation` is produced in the session path, which `cleanupErrors` excludes, so
  the assertion at L178 is not satisfied by that path unless a runner cancel throws.
  In the non-auto-session probe cases, `normalRun` is never reached, so
  `tracker.cancellations` stays empty.
- **Remediation (minimal, recommended):** make `cleanupErrors` the complete
  cleanup-evidence surface, e.g.
  ```dart
  report['cleanupErrors'] = [
    ...tracker.errors,
    ...sessions.expand((session) => session.errors),
  ];
  ```
  This matches the repair wording "include unsettled cancellation/errors in cleanup
  evidence" and keeps `cleanup`/`cleanupConfirmed` unchanged. Alternative: add
  `tracker.errors.add('Update stream cancellation …')` inside `_closeObservation`,
  or change the test to assert on `report['sessions'][i]['contractErrors']`.

### P2 — Real control worst case (~40.3 s) is at/over the default `--control-seconds 40`

From `test/python_owned_process_control_test.py`:

- Real child cases (`run_real_controls`, L678–L712), `cleanup_seconds=3` each:
  `normal` 5+3, `nonzero` 5+3, `timeout` 1.5+3, `root-exit-live-child` 2+3,
  `batch` 5+3 → work 18.5 s + cleanup 15 s = **33.5 s**.
- Synthetic worst contributors: `synthetic_termination_retry` (10 s work / 8 s
  cleanup, recovers ≈5.1 s), `startup-failure-hold-recovery` (0.15 s + 1 s), rest
  sub-second → ≈**6.8 s**.
- Combined worst case ≈ **40.3 s**, versus `run_python_host.py:275`
  `--control-seconds` default **40.0 s**, before interpreter startup and report I/O.

If the inner control test exceeds the outer budget, the outer `run_owned` kills
the control process (exit 124, cleanup confirmed). `controls.passed` is then false
(`run_phase`, L197–L198) and the runner raises
`Controls exited nonzero; no later phase started` (L178) → `FAIL_OR_INCONCLUSIVE`
with HOLD, masking every later suite. This is the concrete failure-cleanup /
handle-retention budget risk.

- **Remediation:** raise the default `--control-seconds` to 60 (still within
  `--plan-seconds` 180), and/or lower the in-test `cleanup_seconds=3` and the
  synthetic `10/8` pair. Document that the outer control budget must exceed the
  inner worst case (≈40.3 s).

### P2 — `--plan-seconds` (hard cap 180) cannot cover controls plus four Flutter suites

`run_python_host.py:301` rejects `--plan-seconds > 180`; `work_seconds = plan - cleanup`
(L298, default 170 s). Default run = controls (≤40 s) + four focused `flutter test`
phases + `scope-analysis`. If each Flutter phase is ≈35–45 s, the total exceeds the
170 s work budget, so later phases are appended as `SKIPPED` ("Insufficient remaining
plan budget") and the run is `FAIL_OR_INCONCLUSIVE` even on a healthy host.

- **Remediation:** split into two invocations with separate grant windows, e.g.
  (a) controls + debugger test, then (b) native / audit-inputs / content +
  scope-analysis; or use `--scope` to select a subset per invocation. Document the
  recommended split in the runner docstring.

### P3 — Runner does not pre-check `--output` location

The control test requires the evidence directory under `root/build`
(`test/python_owned_process_control_test.py:735–736`), but the runner only rejects
`output.is_relative_to(root / ".trellis")` (`run_python_host.py:149`). A bad
`--output` (e.g. `root/evidence/...`) therefore fails late inside the controls phase
with a parser error and the opaque "Controls exited nonzero" message.

- **Remediation:** in `main`, reject `not output.is_relative_to(root / "build")`
  with a clear message before creating any interaction.

### P3 — Docstring contradicts control-report semantics

`run_python_host.py:16` says "either a same-grant PASS controls report
(`--controls-report`) or an in-run …", but the code always runs in-run controls
(L176–L178) and treats `--controls-report` as an additional same-grant PASS
cross-check (L182–L190).

- **Remediation:** rewrite the sentence to "in-run controls always run; a supplied
  `--controls-report` must match the same grant and PASS".

### P3 (informational) — early drain error is not surfaced until exit completes

`normalRun` awaits `actualExit` (L232) before `await output` / `await errors`
(L233). An early stdout/stderr error with a process that lingers is bounded only by
the phase deadline rather than failing fast. The `earlyDrainError` test still passes
because its scripted exit completes at 20 ms. Consider
`await Future.wait([output, errors, actualExit])` or surface drain errors first.

### P4 — dead local

`run_python_host.py:166` assigns `release = "HOLD_UNRELEASED"` but never reads it;
`report["release"]` is set later (L235). Remove the unused local.

## Synthetic evidence (double-backed, no real child)

- Controls pass, budget exhaustion, and controls-failure scenarios were exercised
  with `load_owned_helper` monkey-patched (per-phase `FINISHED`/`RELEASE`/confirmed):
  clean PASS → `FINISHED/RELEASE/confirmed` with grant and `--next-owner root`
  propagated; timed-out phase gates later phases and returns `HOLD_UNRELEASED`;
  controls cleanup failure → immediate HOLD, no focused phases.
- Controls exit 1 with confirmed cleanup → run stops after controls
  (later phases executed: 0), result `FAIL_OR_INCONCLUSIVE`.
- Arg guards exercised: `REPLACE_` grant prefix, missing `--next-owner`, empty grant.

## Not run (blocked without a new window)

- Real `test/python_owned_process_control_test.py` (`--grant`, five real child cases).
- Any Flutter/Dart test, native build, SDK, device, or signing command.
- Therefore no claim is made about real Windows Job containment, real HANDLE
  lifetime, real shell quoting, or the five repairs under a live debug session.

## Recommended next actions (p4/root)

1. P1: align `report['cleanupErrors']` with the cancellation evidence (union) or
   move the diagnostic into `_Pending.errors`; then the stalled-cancel test is
   meaningful.
2. P2: raise `--control-seconds` and/or reduce inner cleanup, and split the 180 s
   plan across two grant windows.
3. P3/P4: pre-check `--output` under `build/`, fix the docstring, drop the dead local.