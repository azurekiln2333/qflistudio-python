> Historical freeze superseded by the consumer-suite extension on 2026-10-26.
> The four runner/verifier hashes and11/27 counts below describe earlier source.
> READY704 was retired by global732 before ACK or execution. Do not replay it.
> Revised source requires final review, updated identity evidence and a fresh
> named grant. No current command in this historical note is an execution grant.

# Single-invocation granted window — coordinating observer design

- Owner: Python (this batch owns only the two new fixture files)
- Task: `.trellis/tasks/10-22-python-offline-tools`
- New files (untracked, not committed):
  - `.trellis/tasks/10-22-python-offline-debugger/research/fixtures/run_python_granted_window.py`
    SHA256 `6ABDB3F88B8B994B32735CA920C1644BFCEE1D80417695AEA9572583CBEFBFF7` (39696 B)
  - `.trellis/tasks/10-22-python-offline-debugger/research/fixtures/verify_run_python_granted_window.py`
    SHA256 `E22145649E194FE31E985BDE6DCBAD57C7B49CA2F3FFB37C1A99B9A33F3A3D21` (45435 B)
- p4's `run_python_host.py`, `verify_run_python_host.py`, the Dart harness and the
  control test were **not** modified by this batch.

Inner layer, now final (p4's hardening is complete): the inner fake helper rejects an
unrecognized command shape and an exhausted scripted-report list, with regression
`check_fake_helper_refuses_unknown_and_exhausted`.

| frozen input | SHA256 | bytes |
| --- | --- | --- |
| `run_python_host.py` (p4) | `395BBD439E0DA00C3587337B8D7CE73AA76AA8968A0A208D649B354B782DD547` | 22623 |
| `verify_run_python_host.py` (p4) | `A1965DD582D642DC0608391DAC6EBDACAA9AD75EB9A8106C3573A63BF0ACB3DC` | 21390 |
| `tool/python_owned_process.py` | `3061CF1D6258061B41BA656DD5F2DD9DA5F1907D40E861AA3FF3152F35BEADFD` | 26940 |
| `test/python_owned_process_control_test.py` | `AD2B9F7A001191E93DD70765BE6C58331432CF2FD595110B20605D2496B0E845` | 38934 |

These four, plus my two outer fixtures, are exactly the six source identities root's
JSON pins. The outer's `OWNED_IDENTITIES` also re-hashes
`tool/python_debugger_ohos_audit.dart` and `test/python_debugger_audit_test.dart` at
execute time, but no fixed hash is recorded here for those two because p4 still owns
them; the live window refuses to run on any drift it sees, so a stale hash is never
silently accepted.

The superseded `verify_run_python_host.py` value
`D6D47C5A6900C551994C1A18A9FF36EB47CD4389961538B1517F0DDFC4EB9DE1` is dead and is not
used anywhere.

Root's isolated synthetic rerun, `2026-10-26T05:38:27+08:00`, logs at
`build/python-host-synthetic-final-20261026/{inner,outer}.log`:

- inner `11/11` `SYNTHETIC_PASS`, exit 0, `SYNTHETIC_VERIFY_PASS no real process was
  started`;
- outer `27/27` `SYNTHETIC_PASS`, exit 0, `SYNTHETIC_VERIFY_PASS no child process,
  publisher or channel call was made`.

No real command was run to produce this freeze.

## Why this wrapper exists (global evidence 613/614)

- seq 613: `ACCEPT608 18:11:21.273Z -> final RELEASE610 18:17:55.269Z = 393.996s`
  while the inner runner was `113.072s` and every validation/publisher process was
  terminal at `18:13:14.442913Z`.
- seq 614: same window `runner 113.072s`, end-to-end `393.453s`, "exceeded 180,
  not bounded success".

So the work and its cleanup finished inside 180 s, but the *release* was relayed by
a later invocation. The 180 s end-to-end gate failed because ACK and final publish
were not in the same bounded invocation.

## Why the inner runner is no longer called in-process

Global evidence JSON622, Java640/641 and Note651 forbid a verification wrapper from
publishing a final RELEASE while it is itself still alive. The previous version
imported `run_python_host` and called `main()` in the same process, so *the
verifying process published its own release*: the release described a process that
had not exited, and no independent root was left to check.

The wrapper is now an **observer only**:

1. It publishes the ACK.
2. It starts an independent verification child `run_python_host.py` through
   `tool/python_owned_process.run_owned`, which keeps the exact verification-root
   HANDLE, creation FILETIME and private Job.
3. The child writes only its local report. It never publishes a final status.
4. `run_owned` returns only after that exact child root is terminal, its Job
   `ActiveProcesses == 0` and its handles are closed.
5. Only then does the observer reconcile the child report and publish the final
   RELEASE / HOLD, with the *child's* identity in the message.

The observer records `observerPid`, `observerRole` and `claims`, and its message
says it "does not claim it has itself exited". The handoff therefore names the
verification root that really terminated.

## Structure

1. `validate()` rejects placeholders, replays and budgets **before** any process or
   file: blank/`REPLACE_`/`--used-grant` grants, blank/`REPLACE_`/self-owned next
   owner, `--total-seconds > 180`, `--inner-seconds > 145`, non-finite or
   non-positive seconds, and both budget sums (child wall, window reserve).
2. `GrantedWindow.__init__` requires `<root>/build/<new>` evidence, then loads the
   owned helper and resolves the Trellis publisher (no shell).
3. `execute()`:
   - freezes `OWNED_IDENTITIES` (both runner layers, the helper, both verifiers and
     the owned Dart/test files);
   - publishes the **ACK** through `run_owned`;
   - aborts before the child if the ACK is not verified or the budget cannot cover
     the child, its cleanup and the final publish;
   - runs `run_child()`: `run_owned(python run_python_host.py …)` with
     `--plan-seconds = inner_plan_seconds`, then records
     `verificationRoot.confirmed = owned_confirmed(child_report)`;
   - reads `<output>/inner/report.json`, calls `verify_inner_report()`, and appends
     `timedOut` / non-zero child exit as verification failures;
   - returns early, without a final publish, when the managed root is unconfirmed.
4. `publish_final()`:
   - re-freezes owned sources **before** composing any text (see below);
   - withholds publication when the ACK failed, the root is unconfirmed, or the
     remaining budget cannot cover publish plus margin;
   - publishes RELEASE for PASS **and** for FAIL-but-clean, HOLD only for an
     unproven root.
5. `persist()` writes `report.json`; `window-summary.md` holds the operator line
   while `release-message.md` keeps the published text, so publication text is
   never overwritten.

## Release invariants (root exit is never enough)

`owned_confirmed()` requires all of:

- `state == "FINISHED"`
- `release == "RELEASE"`
- `cleanupConfirmed is True`
- `handlesRetained is False`
- `process.terminal is True`
- `process.jobActiveProcesses == 0`
- `process.handlesClosed is True`
- exact identity present: `pid`, `creationFiletime100ns`, `processHandleDecimal`,
  `jobHandleDecimal`

A zero root exit with a live Job child, an unclosed handle set, a non-terminal
root, or incomplete identity is HOLD, and **no final status is published at all**.
This is synthetically proven four times.

`verify_inner_report()` re-checks every executed child phase, never a single
`confirmed` flag:

- `cleanupConfirmed is True`
- `handlesRetained is False`
- `release == "RELEASE"`
- `rootTerminal is True`
- `jobActiveProcesses == 0`
- handle-closure evidence: either `handlesClosed is True`, or the durable
  `runOwnedReport` that phase names proves `cleanupConfirmed`, `terminal`,
  `jobActiveProcesses == 0` and `handlesClosed`.

A phase without closure evidence is unproven cleanup. A missing or unreadable child
report is unproven verification. Neither can be reported as PASS, and neither
withholds a release that the managed root really completed.

## Verification result vs resource release

The two stay strictly separate. `final_status()` returns `(status, verb)` where
`status` is about the checks and `verb` only about ownership handoff: RELEASE when
`verificationRoot.confirmed is True`, otherwise HOLD.

| situation | result | release | handoff |
| --- | --- | --- | --- |
| checks pass, root closed, published | `PASS` | `RELEASE` | to next owner |
| checks fail, root closed, published | `FAIL_OR_INCONCLUSIVE` | `RELEASE` | to next owner |
| source drift, root closed, published | `FAIL_OR_INCONCLUSIVE` | `RELEASE` | to next owner |
| child timed out / over budget, root closed, published | `FAIL_OR_INCONCLUSIVE` | `RELEASE` | to next owner |
| child report missing or phase unproven, root closed | `FAIL_OR_INCONCLUSIVE` | `RELEASE` | to next owner |
| managed root unproven | `HOLD_UNRELEASED` | `HOLD_UNRELEASED` | withheld |
| publication not verified | `FAIL_OR_INCONCLUSIVE` | `HOLD_UNRELEASED` | withheld |
| ACK not delivered | `ACK_NOT_DELIVERED` | `HOLD_UNRELEASED` | withheld |

`persist()` computes `released` from real evidence only
(`verificationRoot.confirmed is True` + `claimedStatus == RELEASE` + `delivered`),
independent of `result`. The failure text says the root "is terminal with Job 0 and
handles closed, so resources are released ... a recorded verification failure, not a
cleanup failure", and contains no "no handoff" and no claim of an empty handoff.

## Source freeze decides once, before publication

The freeze is re-read **only** in `publish_final`, and before the status text is
composed. A drift therefore changes the published status instead of contradicting
it.

The earlier version also re-read the freeze inside `persist()`, *after* the message
had been delivered. Drift found only there would have made the local report say FAIL
while the delivered message said PASS — exactly the local/global contradiction this
batch must not produce. Detecting drift after delivery cannot withdraw a delivered
message, so that re-read was removed and the single decision moved earlier.

`check_freeze_decided_before_publication` asserts all three properties on the source
text: the check exists in `publish_final`, it precedes `text = (`, and neither
`persist` nor `main` re-reads it.

## Budget arithmetic (total 180 s)

| item | seconds |
| --- | --- |
| total window | 180 |
| ACK publish | 12 |
| managed child timeout (`--inner-seconds`) | 120 |
| outer cleanup (`--outer-cleanup-seconds`) | 10 |
| final publish | 18 |
| outer margin | 5 |
| sum reserved | 165 |
| headroom left | 15 |

The child must also fit its own wall budget:
`plan + max-phases x cleanup <= inner timeout`, i.e. default
`105 + 3 x 5 = 120 <= 120`. The inner ceiling of 145 s is enforced separately, but
120 s is what the 180 s window actually pays for. `--inner-plan-seconds 106` (121 s
of child wall) and `--inner-seconds 146` are both rejected, as is
`--total-seconds 160` (needs 165).

Root can raise the inner timeout only by lowering another reserve so the sum still
fits.

## Publication verification

Publication uses `run_owned` on `node <trellis>/bin/trellis.js channel send
qfli-core-release-sync --scope global --as python-offline-1022 --to <successor>
--text-file <message>`. `delivered` is true only when the returned report is
`owned_confirmed` **and** `exitCode == 0` **and** `timedOut is False`. A nonzero or
timed-out publisher is recorded as `delivered: false`, and the result is not PASS.

## HOLD behaviour

- If the managed child root cannot be confirmed, the observer publishes nothing
  final, records `HOLD_UNRELEASED`, and says the exact handles stay retained and
  must not be killed by PID.
- `run_owned` itself keeps observing and retaining the exact handles; this file
  never kills a looked-up PID and never abandons handles.
- An unverified publication is HOLD for ownership even when the checks passed: the
  handoff was never delivered, so it cannot be claimed.

## Guard hardening against C607-NEG (p3 review F1, F2, F4)

p3's source-only review found that the first check, `check_argument_guards`, ran
`module.main` before installing doubles, so a regressed or widened guard could
reach the real `run_owned` and a real channel ACK before the failure surfaced
(the C607-NEG shape). All three findings are now fixed in the frozen revision.

**F1 — doubles installed before every `module.main`, no real fallback.**

- `check_argument_guards` now installs strict doubles *at the top*, before its
  first `module.main`. Static check `check_argument_guards_install_doubles` also
  proves `_install(module, …)` precedes every `module.main(` in that function, and
  that every other window-running check installs first or calls the
  install-first helper.
- `_FakeHelper.run_owned` no longer has a silent fallback. It classifies a command
  as ACK / child / release, raises `RuntimeError` immediately for anything else,
  and raises if the recognised command has no scripted report. Runtime check
  `check_fake_helper_has_no_real_fallback` proves both raises.
- `check_widened_guard_still_zero_io` is the explicit negative control. It replaces
  `validate` with an accept-everything stub, so the window really runs, and proves
  the fake publisher is the only publisher (`used["publisher"] == 1`), the fake
  loader stays installed, the strict helper refuses the unscripted ACK, no child
  starts, no final `release-message.md` appears, and the report is
  `ACK_NOT_DELIVERED` / `HOLD_UNRELEASED`.

**F2 — both verifiers refuse a non-Windows host.**

- `verify_run_python_granted_window.py:main()` now starts with
  `if os.name != "nt": … return 2`, before the optimized-run refusal. Static check
  `check_refuses_non_windows` asserts that ordering and that the refusal exits
  nonzero.
- p4 independently added the same refusal to `verify_run_python_host.py` (L391)
  and removed its bare asserts (F3). Both verifiers were run on this Windows host:
  `SYNTHETIC_VERIFY_PASS` each, exit 0; `python -O` on the host verifier exits 2.

**F4 — construction failure is a clear `parser.error`, and nothing is deleted.**

- `GrantedWindow.__init__` now resolves the owned helper and the publisher
  **before** `self.output.mkdir(...)`, so a missing root, helper or Trellis entry
  leaves no partial evidence directory.
- `main` catches `(WindowFailure, OSError)` around construction and calls
  `parser.error(f"Cannot open the window: {error}")`.
- No `shutil.rmtree` or other recursive delete exists in the wrapper; the verifier
  asserts `"rmtree" not in source`. `check_construction_failure_is_a_clear_error`
  drives both a missing root and a raising loader and proves exit 2, no directory,
  and no `run_owned` call.

## Report/message parity on a failed identity capture (root-found, fixed)

Root found a real contradiction in the previous revision. `recheck_freeze()`
appended the error, set `ownedDrift = None` and returned `False`, but it never set
`inner["passed"] = False`. `publish_final()` ignored the `False` return, so
`final_status()` still saw `inner.passed is True` and composed **status=PASS**,
while `persist()` saw a non-empty `errors` list and wrote
**FAIL_OR_INCONCLUSIVE**. The delivered message and the durable report disagreed.

Fixed by making both pre-publication outcomes share one downgrade:

- New `downgrade_verification(message)` records the failure in `errors`, sets
  `inner["passed"] = False` and appends the reason to `inner["reasons"]`.
- `recheck_freeze()` calls it on drift **and** on a capture exception, before the
  status text is composed. A capture failure also records
  `identityCapture = {"ok": False, "reason": ...}`.
- `publish_final()` keeps the return value (`frozen = self.recheck_freeze()`) and,
  as defence in depth, forces `FAIL_OR_INCONCLUSIVE` when `frozen` is false and the
  verb would otherwise be RELEASE with status PASS.
- Release is untouched: it still depends on `verificationRoot.confirmed` only, so a
  confirmed managed child still RELEASEs its resources.

`check_identity_capture_failure_fails_but_releases` is the strict-fake regression. It
makes the second (pre-publication) `identities()` capture raise `OSError`, then
proves:

- `verificationRoot.confirmed is True`, `release == RELEASE`,
  `publication.delivered is True`, `claimedStatus == RELEASE`;
- `identityCapture.ok is False`;
- durable `result == FAIL_OR_INCONCLUSIVE`, `inner.passed is False`, and the reason
  names the identity capture;
- delivered message contains `status=FAIL_OR_INCONCLUSIVE`, contains no
  `status=PASS` and no "no handoff", and says "recorded verification failure";
- `window-summary.md` contains `result=FAIL_OR_INCONCLUSIVE`;
- statically, `downgrade_verification` exists and has exactly two call sites, so
  drift and capture failure cannot diverge again.

Observed output for that case:

- durable: `result=FAIL_OR_INCONCLUSIVE release=RELEASE claimed=RELEASE
  delivered=True innerPassed=False`, `identityCapture = {"ok": false, "reason":
  "OSError: identity capture unavailable (simulated)"}`;
- message: `RELEASE … the managed verification root is terminal with Job 0 and
  handles closed, so resources are released. status=FAIL_OR_INCONCLUSIVE. …
  Pre-publication identity capture failed: OSError: … This is a recorded
  verification failure, not a cleanup failure.`

The message and the durable report now agree on both the status and the release.

## Synthetic evidence (no child, no publisher, no channel call)

`python .trellis/tasks/10-22-python-offline-debugger/research/fixtures/verify_run_python_granted_window.py`

27 checks pass:

- `check_argument_guards`
- `check_ack_failure_blocks_child`
- `check_root_exit_zero_with_live_job_no_final_publish`
- `check_root_not_terminal_no_final_publish`
- `check_handles_not_closed_no_final_publish`
- `check_missing_root_identity_no_final_publish`
- `check_child_never_publishes`
- `check_success_single_window`
- `check_failed_verification_releases`
- `check_failed_report_matches_global_message`
- `check_over_budget_child_fails_but_releases`
- `check_wall_clock_over_budget_fails_but_releases`
- `check_missing_child_report_is_fail_but_release`
- `check_phase_closure_evidence_required`
- `check_drift_before_publication_fails_but_releases`
- `check_identity_capture_failure_fails_but_releases`
- `check_identities_freeze_both_layers`
- `check_freeze_decided_before_publication`
- `check_report_and_message_agree`
- `check_fake_helper_has_no_real_fallback`
- `check_argument_guards_install_doubles`
- `check_widened_guard_still_zero_io`
- `check_refuses_non_windows`
- `check_construction_failure_is_a_clear_error`
- `check_readiness_command_is_ready`
- `check_readiness_controls_precede_suites`
- `check_optimized_run_is_refused`

Final line: `SYNTHETIC_VERIFY_PASS no child process, publisher or channel call was
made`.

Root's isolated rerun of both verifiers at `2026-10-26T05:38:27+08:00` recorded
inner `11/11` exit 0 and outer `27/27` exit 0 in
`build/python-host-synthetic-final-20261026/{inner,outer}.log`, with the machine
record at
`.trellis/tasks/10-22-python-offline-debugger/research/host-observer-synthetic-verification-20261026.json`
(2890 B, sha256
`BDB795E8F883BFF78B33FBFDD11B83B5E3B91234E825D4AF82F7184E3F187F07`), which pins
the same eleven source identities this note records, each with `bareAsserts: 0`.

Message and report parity was printed directly for four situations:

- success: `result=PASS release=RELEASE`, 3 commands (ACK, child, RELEASE),
  `verificationRoot.publication=NOT_ATTEMPTED`, message carries
  `verification root PID=4242 HANDLE=8738 FILETIME=… Job=4369 terminal=True
  jobActive=0 handlesClosed=True` and "observer PID=… does not claim it has
  exited";
- root exit 0 with a live Job: 2 commands only, no `release-message.md` at all,
  `publication.reason = "managed verification root not confirmed; no final
  publish"`, `result=HOLD_UNRELEASED`;
- verification failure with real cleanup: `result=FAIL_OR_INCONCLUSIVE
  release=RELEASE`, message "recorded verification failure, not a cleanup
  failure";
- failed pre-publication identity capture: `result=FAIL_OR_INCONCLUSIVE
  release=RELEASE`, message `status=FAIL_OR_INCONCLUSIVE` with the capture reason,
  and no `status=PASS` anywhere.

Guards also verified directly:

- `python -O .../run_python_granted_window.py` -> exit 2, refusal printed, no dir.
- `PYTHONOPTIMIZE=1` -> exit 2, same refusal.
- `python -O .../verify_run_python_granted_window.py` -> exit 2; the non-Windows
  refusal is asserted statically because this host is Windows.
- Zero bare `assert` statements in either new file; checks raise `WindowFailure`.
- `python -m py_compile` clean; `__pycache__` and every `build/_verify_*` directory
  removed afterwards.
- Global channel `events.jsonl` passed 690 lines during this session, advancing
  from **other** agents throughout. The newest event mentioning `python-offline-1022`
  is seq 533, which predates this batch. Nothing was published by this work.

## READY command (prepared only — NOT launched, no grant requested)

Status: **HELD on the grant only**. The hash gate is closed: p4's inner verifier is
frozen at `A1965DD582D642DC0608391DAC6EBDACAA9AD75EB9A8106C3573A63BF0ACB3DC` (21390 B)
and both inner hashes are recorded at the top of this note. The command below is
prepared and synthetically proven, but it must not be launched until the **C
coordinator issues a NEW host grant** and root then accepts and launches it.

Grant ownership is not self-service: C owns the host ownership handoff, so **root
cannot self-grant host ownership**. This file never issues, requests, claims or
assumes a grant, and every placeholder below stays a placeholder until C grants.

### Resolved publisher identity (filesystem lookup only, nothing executed)

| item | value |
| --- | --- |
| node | `D:\ProgramFiles\nodejs\node.exe` |
| node bytes / sha256 | 91694408 / `3331e1ffe19874215472217c5e94f5a0c6d8e18c4ac7111d3937aa0ad5e9b4a5` |
| shim resolved by `shutil.which` | `D:\AppData\Roaming\npm\trellis.cmd` |
| CLI entry | `D:\AppData\Roaming\npm\node_modules\@mindfoldhq\trellis\bin\trellis.js` |
| entry bytes / sha256 | 53 / `dba1db2ed1d34f7d1e151d69303f14ce54aeb9f9e5dab60dc125aca692ab519a` |
| trellis version | `0.6.17` |

The publisher is invoked as `node <entry> channel send <channel> --scope global
--as <sender> --to <successor> --text-file <message>` through `run_owned`, never
through a shell.

**What this identity does not bind.** The entry is only 53 bytes and its whole body
is a shebang plus `import("../dist/cli/index.js")`. The recorded hash therefore binds
the entry point only. It does **not** bind the imported CLI bundle under `dist/`, nor
the rest of the `@mindfoldhq/trellis` package, nor its `node_modules` dependency
tree, and it does not prove that those files are unchanged between this lookup and
the moment of publication. Likewise `trellis version 0.6.17` is read from
`package.json`, not derived from the entry hash.

So the honest claim is narrow: the launched interpreter (`node.exe`) and the entry
file are pinned by hash; the transitive CLI code that actually performs the send is
not covered by any hash recorded here. Anyone re-checking this must re-resolve and
re-hash the full tree, or accept this explicitly disclosed limit. No part of this
note claims that all toolchain bytes were captured.

### Exact command

PowerShell, single invocation, successor `C`:

```powershell
python .trellis/tasks/10-22-python-offline-debugger/research/fixtures/run_python_granted_window.py `
  --grant <NEW-GRANT> `
  --used-grant <EACH-CONSUMED-GRANT> `
  --next-owner c-coordinator `
  --output build/<NEW-GRANT>-window `
  --total-seconds 180 `
  --ack-seconds 12 `
  --inner-seconds 138 `
  --inner-plan-seconds 123 `
  --child-cleanup-seconds 5 `
  --outer-cleanup-seconds 10 `
  --publish-seconds 15 `
  --margin-seconds 5 `
  --max-inner-phases 3 `
  --control-seconds 60 `
  --min-phase-seconds 5 `
  --include-named-workspace `
  --node "D:\ProgramFiles\nodejs\node.exe" `
  --trellis-entry "D:\AppData\Roaming\npm\node_modules\@mindfoldhq\trellis\bin\trellis.js" `
  --channel qfli-core-release-sync `
  --sender python-offline-1022
```

Repeat `--used-grant` once per consumed grant so a replay is refused. `--scope` is
deliberately omitted: the child then uses the inner runner's `DEFAULT_SCOPE`, which is
the scoped analyze over `tool/python_debugger_ohos_audit.dart` and
`test/python_debugger_audit_test.dart`. `--controls-report` and `--control-only` are
deliberately omitted: the controls phase must run **inside** this window, and a prior
control-only report is not reused.

### Budget: exactly 180 s, one window

| item | seconds |
| --- | --- |
| ACK publish | 12 |
| managed child timeout (`--inner-seconds`) | 138 |
| outer cleanup (`--outer-cleanup-seconds`) | 10 |
| final publish | 15 |
| outer margin | 5 |
| **reserved total** | **180** |

Child wall: plan `123` + `3` phases x `5` s cleanup = `138` = its timeout, so it fits.
Child work budget: `123 - 5 = 118` s to cover, in this order:

1. `owned-process-controls` — `python test/python_owned_process_control_test.py
   --grant <NEW-GRANT> --output <out>/controls`, capped at
   `min(--control-seconds, work)` = 60 s (a cap, not a measured cost);
2. `focused-suites` — one merged `flutter test --no-pub --concurrency=1` over the
   five suites: the four `FOCUSED_SUITES` plus `python_named_workspace_test.dart`
   via `--include-named-workspace`;
3. `scope-analysis` — `dart analyze` over the two default scoped files.

The inner runner starts the suites only after the controls phase both confirmed
cleanup and passed; a controls failure stops the later phases outright.

`check_readiness_command_is_ready` runs this exact flag set through `validate()` and
a fake window, and proves: reserved == 180, child wall <= inner timeout, inner <=
ceiling, one child command carrying `--plan-seconds 123.0 --cleanup-seconds 5.0
--control-seconds 60.0 --include-named-workspace`, no `--controls-report`, no
`--control-only`, no `--scope`, and a `RELEASE` summary.
`check_readiness_controls_precede_suites` proves from the inner source that
`run_controls` precedes `focused-suites` which precedes `scope-analysis`, that the
suites are gated on `controls.get("passed")`, that there are four focused suites plus
the named one, and that the analyze stays scoped.

### Expected outcomes under this budget

- Controls pass, five suites and the analyze fit in 118 s -> `PASS` / `RELEASE`.
- Any check fails but every managed root really closed -> `FAIL_OR_INCONCLUSIVE` /
  `RELEASE`, with the failure reason in the message.
- Suites do not fit -> the inner runner appends `SKIPPED` phases, non-PASS, still
  `RELEASE`.
- A managed root unproven -> `HOLD_UNRELEASED`, no final publish, handles retained,
  never killed by PID.

### Capacity note (keep the real limit; measure after the new grant)

`--control-seconds 60` is a **timeout cap, not a measured cost**. The earlier
40.3 s estimate was never a real Windows measurement and is withdrawn. Keep
the cap until a fresh granted run supplies actual timing evidence.

The five merged suites and scoped analysis share the remaining work budget
after real controls. Their capacity is unmeasured. A fresh grant must establish
actual timing before any claim that this scope fits.

If a later grant shows a real overrun, the only legal fixes stay inside the 180 s
rule: split into two grants, or raise `--inner-seconds` while lowering a reserve so
the sum still fits and re-run the synthetic verifier to prove the new arithmetic.

No design blocker was found: the only hard constraint is the arithmetic above.

## Not run (blocked without a new explicit grant)

- No ACK, no channel send, no real control suite, no Flutter/Dart, no native build,
  no SDK, no device, no signing, no commit or stage.
- Therefore no claim is made about live Windows Job/HANDLE behaviour of a real
  child, real publication latency, or a real 180 s end-to-end window.
- The two fixture files stay untracked; `git diff --cached` is empty.
