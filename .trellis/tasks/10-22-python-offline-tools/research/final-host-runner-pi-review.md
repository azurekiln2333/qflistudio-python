# Final host-runner independent review (Pi)

Date: 2026-10-26. Reviewer: trellis-check reviewer (Pi). Direct review; no
subagent was spawned. Read-only on p4 files; this note is the only file written.

Reviewed p4 delivery:

- `tool/python_debugger_ohos_audit.dart`
- `test/python_debugger_audit_test.dart`
- `.trellis/tasks/10-22-python-offline-debugger/research/fixtures/run_python_host.py`
- `.trellis/tasks/10-22-python-offline-debugger/research/fixtures/verify_run_python_host.py`

Cross-checked against `.trellis/tasks/10-22-python-offline-debugger/research/review-run-host-pi.md`
(the prior note whose P1/P2/P3/P4 this delivery claims to fix) and
`tool/python_audit_inputs.py` (the binding scope). No p4 file was edited.

Method: source review plus the double-only verifier
`verify_run_python_host.py`. No Dart, Flutter, real controls, native, SDK, WSL,
HAP or device command ran. No commit was created. The outer publication wrapper
is p6's; this note does not review or touch it.

## Verdict

**A new host grant can be prepared.** No blocking source defect was found in the
five required behaviors. One runtime quantity (real merged-Flutter duration
against the remaining work budget) can only be measured under that grant.

## Required behaviors

| Requirement | Evidence | Result |
| --- | --- | --- |
| Four suites + optional workspace, one Flutter call, no reduced checks | `FOCUSED_SUITES` is the 4 debugger/native/audit/content files (`run_python_host.py` L36-41); `focused_command` builds one `flutter test --no-pub --concurrency=1` with all four (plus `NAMED_WORKSPACE_SUITE` when `--include-named-workspace`) | Pass (source + verifier) |
| 180 s hard cap | `main` rejects `--plan-seconds > 180`; default 180; `work_seconds = plan - cleanup`; every phase bounded by `remaining()`; `withinPlanSeconds` gates PASS | Pass |
| Input source bound before and after | `ownedIdentitiesBefore/After` over `OWNED_IDENTITIES`; `auditInputsBefore/After` over product+shared; `ownedDrift`/`auditInputDrift` force `FAIL_OR_INCONCLUSIVE` | Pass (product/core scope) |
| P1 cancel-error aggregation | `report['cleanupErrors'] = [...tracker.errors, ...sessions.expand((s) => s.errors)]` (`python_debugger_ohos_audit.dart` L483-486); `_closeObservation` adds `Update stream cancellation …` to session `errors` (L688-700); test asserts `cleanupErrors` contains `cancellation` (`test/python_debugger_audit_test.dart` L178) | Pass (source) |
| Controls failure gate | default `--control-seconds 60` (margin over the ~40.3 s real worst case); not confirmed → `Controls did not confirm exact cleanup; HOLD`; failed → `Controls exited nonzero; no later phase started`; supplied `--controls-report` must be same grant, `result == "PASS"`, non-empty `cases` (rejects `SYNTHETIC_PASS`) | Pass (source + verifier) |

The four focused suite files exist, and the audit test still holds 12 `test(`
cases, including the P1 stalled-cancellation regression. The merge lists the same
four suites; none was dropped.

## Double-only verifier run

`python .trellis/tasks/10-22-python-offline-debugger/research/fixtures/verify_run_python_host.py`

Result: `SYNTHETIC_VERIFY_PASS no real process was started`, exit 0, six checks:

- `check_control_failure_stops_before_flutter`: controls exit 1 with confirmed
  cleanup → exactly one `run_owned` call, zero Flutter calls, error contains
  `Controls exited nonzero`, release `RELEASE`.
- `check_control_hold_never_releases`: unconfirmed cleanup → no Flutter call,
  release `HOLD_UNRELEASED`.
- `check_synthetic_controls_report_rejected`: `SYNTHETIC_PASS` with empty `cases`
  → rejected, no Flutter call.
- `check_real_controls_report_opens_merged_suite`: real `PASS` report → one
  `flutter test --no-pub --concurrency=1` call containing all four suites, no
  named-workspace suite, result `PASS`.
- `check_named_workspace_joins_same_call`: `--include-named-workspace` joins the
  same single call.
- `check_second_values_and_output_rejected`: `181`, `200`, `nan`, `inf`, zero and
  negative seconds are rejected before any output is composed; an output outside
  `<root>/build` is rejected.

The argparse usage lines on stderr are the expected rejections from the last
check; the process exit is 0.

## Prior findings status

- P1 `cleanupErrors` omitted stalled-cancellation diagnostics: **fixed**. The
  union includes session `errors`, and `cleanup` still requires
  `session.errors.isEmpty`, so the stalled-cancel test is meaningful. The Dart
  test was not executed here (Dart is not allowed); it is verified by source and
  by its own assertion.
- P2 default `--control-seconds 40` at/over the ~40.3 s worst case: **fixed**.
  Default is now 60 with an explicit margin comment.
- P2 split of the 180 s plan: **addressed differently**. Instead of two grant
  windows, the four Flutter suites are merged into one invocation to cut
  per-process overhead. This is a valid alternative, with the residual budget
  risk below.
- P3 `--output` pre-check: **fixed**. `run` rejects a path outside
  `<root>/build` before creating it.
- P3 docstring: **fixed**. It now states in-run controls always run and a
  supplied report must be same-grant, real and PASS.
- P4 dead `release` local: **fixed**. No dead assignment remains.

## Observations (non-blocking)

1. Only `test/python_debugger_audit_test.dart` is pinned. The other three focused
   suites (`test/python_debugger_test.dart`, `test/python_debugger_native_test.dart`,
   `test/python_content_audit_test.dart`) and `test/python_named_workspace_test.dart`
   are executed but are not in `OWNED_IDENTITIES`, and
   `tool/python_audit_inputs.py` `collect_inputs` covers
   `lib`, `assets/python_stdlib`, `ohos/entry/src/main`, `native/ohos` and named
   top-level files but not `test/`. So a mid-run edit to one of those suites is
   not detected by `ownedDrift` or `auditInputDrift`.
   - Minimal repro (needs a grant; not run here): after capture, modify
     `test/python_content_audit_test.dart`; the after-capture hashes are
     unchanged, so the run can still report PASS.
   - This matches the documented binding scope ("product/core sources"). It is a
     gap only if all executed check files must be pinned. Fix, if desired: add the
     remaining suites to `OWNED_IDENTITIES` or include `test/` in the binding.

2. Merged-Flutter runtime is unmeasured. Work budget is `180 - 10 = 170 s`;
   controls may consume up to 60 s, leaving about 110 s for one four-suite
   `flutter test` plus `dart analyze`. If the merged run overruns, later phases
   become `SKIPPED` and the result is `FAIL_OR_INCONCLUSIVE`. This is honest
   (no false PASS) but must be observed under the new grant. If it overruns,
   lower `--control-seconds`, raise `--plan-seconds` is not allowed, or split.

3. `--cleanup-seconds` is applied per phase. A long cleanup after a phase timeout
   can push wall-clock past `--plan-seconds`; `withinPlanSeconds` then forces
   `FAIL_OR_INCONCLUSIVE`. No false PASS, but the wall-clock cap is not a hard
   process kill.

## Not run

- Any Dart/Flutter test, including the P1 stalled-cancellation regression and the
  merged four-suite command.
- Real `test/python_owned_process_control_test.py` under a grant, so real Windows
  Job containment, HANDLE lifetime and shell quoting are not established.
- Native build, SDK, WSL, HAP, signing or device acceptance.
- The outer publication wrapper (p6 owns it; the runner only marks
  `publication: NOT_ATTEMPTED`).

## Conclusion

Prepare the new host grant. Expect the grant to measure two things the source
cannot: the real merged four-suite Flutter duration inside the 170 s work budget,
and the real controls duration under the new 60 s control budget. Treat the
unpinned focused suites as a scope note, not a blocker, unless root decides every
executed check file must be hash-bound.
