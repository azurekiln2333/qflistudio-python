# Source-only harness guard review — frozen pass

- Date: 2026-10-26 (second pass, post-freeze)
- Reviewer role: trellis-check (independent, direct; no delegation)
- Requesting task: `.trellis/tasks/10-22-python-offline-tools`
- Subject task: `.trellis/tasks/10-22-python-offline-debugger`
- Artifact class: exclusive; this file is the reviewer's own and is updated in place
- Method: read-only source audit plus the two fully isolated synthetic verifiers.
  No real wrapper invocation with real collaborators, no controls, no publisher, no
  Dart/Flutter/native/SDK/WSL/HAP/signing/device, no channel publication.
- Status: **FINAL PASS. No blocker; notes only.** Final hashes: inner verifier
  `a1965dd5…`, outer wrapper `6abdb3f8…`, outer verifier `e2214564…`.

## Frozen artifacts (hashes at review)

| file | bytes | sha256 | mtime |
| --- | --- | --- | --- |
| `fixtures/run_python_host.py` | 22623 | `395bbd439e0da00c3587337b8d7ce73aa76aa8968a0a208d649b354b782dd547` | 04:29:00 |
| `fixtures/run_python_granted_window.py` | 39696 | `6abdb3f88b8b994b32735ca920c1644bfcee1d80417695aea9572583cbefbff7` | 05:19:54 |
| `fixtures/verify_run_python_host.py` | 21390 | `a1965dd582d642dc0608391dac6ebdacaa9ad75eb9a8106c3573a63bf0acb3dc` | 05:34:50 |
| `fixtures/verify_run_python_granted_window.py` | 45435 | `e22145649e194fe31e985bde6dcbad57c7b49ca2f3ffb37c1a99b9a33f3a3d21` | 05:20:58 |

Support files (unchanged, still in the freeze): `test/python_owned_process_control_test.py`
`ad2b9f7a001191e93dd70765be6c58331432cf2fd595110b20605d2496b0e845` (38934 B),
`tool/python_owned_process.py`
`3061cf1d6258061b41ba656dd5f2dd9da5f1907d40e861aa3ff3152f35beadfd` (26940 B).

Freeze was confirmed by repeated hash snapshots with identical results, and
re-confirmed after the verifier runs. No file changed during the review.

After the first frozen-pass note, p4 re-hardened the inner verifier's fake
command and report-exhaustion handling (root found the old silent
`return _phase_report(0)` fallback). The inner verifier hash moved from
`d6d47c5a…` (17752 B) to the final `a1965dd5…` (21390 B). This review uses the
final hash; the inner verifier was re-read after the handoff and re-run alone.

## Actual results (isolated doubles, executed)

| verifier | checks | result | exit |
| --- | --- | --- | --- |
| `verify_run_python_host.py` | 11/11 | `SYNTHETIC_VERIFY_PASS no real process was started` | 0 |
| `verify_run_python_granted_window.py` | 27/27 | `SYNTHETIC_VERIFY_PASS no child process, publisher or channel call was made` | 0 |

Root independently re-read the hardened fake helper and re-ran the final inner
verifier (11/11) and outer verifier (27/27), both exit 0, at 05:38:27. No source
changed after that. (The earlier `28/28` note was a miscount: this review had
included `check_function(module)` in a `check_[a-z]` count. The outer checks
tuple holds 27 checks.)

Optimized-interpreter refusal (no vacuous optimized pass), all exit 2:

- `python -O verify_run_python_host.py` → `OPTIMIZED_INTERPRETER_REJECTED`
- `python -O verify_run_python_granted_window.py` → `Refusing to verify under -O`
- `python -O run_python_granted_window.py …` → `Refusing to run under -O/PYTHONOPTIMIZE`

No `build/_verify_*` directory and no `build/x` survived the runs.

## Guard questions (prior pass → now)

| guard | prior | now |
| --- | --- | --- |
| Simulation loaders fully replaced | gap at `check_argument_guards` (F1) | **fixed**; doubles installed first, plus static guard and a widened-guard negative control |
| Unknown phase throws immediately | no phase-name dispatch (vacuous) | unchanged; still no name dispatch, so no real-execution path |
| Exception recovery leaking the real helper | F1 window | **fixed**; every `module.main`/`module.run` installs or resets doubles first |
| Optimized branch starts resources | host verifier could pass vacuously (F3) | **fixed**; both verifiers and the wrapper refuse `-O`/`-OO` before loading |

## F1 — medium — owner p6 — FIXED

Prior defect: `check_argument_guards` ran first in the checks tuple and never
called `_install`, so a regressed guard could reach the real `load_owned_helper`
and `resolve_publisher`, then a real `channel send` — the C607-NEG shape, with
detection only after the side effect.

Now:
- `check_argument_guards` calls `_install(module, _helper(module, [], None))` as
  its first statement, before any `module.main`.
- `_FakeHelper.run_owned` raises `RuntimeError` on any unrecognised command and
  on an unscripted report; the silent `return _owned()` fallback is gone,
  asserted by `check_fake_helper_has_no_real_fallback`.
- `check_argument_guards_install_doubles` statically asserts install-before-main
  for `check_argument_guards` and for every other check that runs the window.
- `check_widened_guard_still_zero_io` is the C607-NEG negative control: it
  replaces `validate` with an accept-everything version so the window really
  proceeds. Result: `result=ACK_NOT_DELIVERED`, `release=HOLD_UNRELEASED`,
  `child_calls == 0`, no `release-message.md`. The strict fake refused the
  unscripted ACK, so zero real I/O even with a fully regressed guard.

Verified: `SYNTHETIC_PASS check_argument_guards`,
`… check_widened_guard_still_zero_io`,
`… check_fake_helper_has_no_real_fallback`,
`… check_argument_guards_install_doubles`.

## F2 — medium — owner p6 and p4 — FIXED

Prior defect: `os.name != "nt"` inside `validate()` made every negative case exit
2 on non-Windows, so both verifiers passed vacuously on WSL/Linux.

Now both verifiers refuse the platform outright, before loading the module:
`verify_run_python_host.py:main` prints `NON_WINDOWS_HOST_REJECTED` and returns 2;
`verify_run_python_granted_window.py:main` refuses with an explicit reason and
returns 2, ahead of the `-O` check (`check_refuses_non_windows` asserts the
platform refusal precedes the optimized check and exits nonzero). The runners
keep `os.name` in `validate`, which is correct for the real runner. A non-Windows
`SYNTHETIC_VERIFY_PASS` is no longer possible.

Verified: `SYNTHETIC_PASS check_refuses_non_windows` (static; cannot be proven
dynamically on a Windows host, which is the intended limit).

## F3 — low — owner p4 — FIXED

Prior defect: `verify_run_python_host.py` had 23 bare `assert` statements and no
`-O` refusal, so `python -O` printed PASS vacuously.

Now: zero bare `assert` in all four files. The host verifier uses an always-on
`require()` raising `VerificationError`, and `main` refuses `sys.flags.optimize != 0
or not __debug__` with exit 2 (`OPTIMIZED_INTERPRETER_REJECTED`, observed).

Verified: `python -O verify_run_python_host.py` → exit 2; full run 10/10.

## F4 — low — owner p6 — FIXED

Prior defect: `main` caught only `WindowFailure` around construction, so a missing
root or a non-`WindowFailure` from a loader escaped as a traceback with no report,
and `mkdir` before the loader calls could leave an empty evidence directory.

Now: `except (WindowFailure, OSError) as error:` with
`parser.error(f"Cannot open the window: {error}")`. `check_construction_failure_is_a_clear_error`
runs a missing `--root` and a missing helper module and asserts exit 2, no
`run_owned` call, and no leftover evidence directory. No `rmtree` anywhere in the
wrapper (asserted).

Verified: observed `error: Cannot open the window: …no-such-root` and
`… python_owned_process.py is missing`, both exit 2, `SYNTHETIC_PASS`.

## F7 — medium — owner p6 — ROOT-FOUND FREEZE-EXCEPTION PARITY — FIXED AND INDEPENDENTLY VERIFIED

Defect (root found, sent to p6): in the pre-publication freeze check, the
exception branch returned `False` but `publish_final()` ignored the return value
and the branch never downgraded `inner.passed`. So an identity-read `OSError`
produced a global message `status=PASS` while `persist()` recorded
`FAIL_OR_INCONCLUSIVE` — a global/durable contradiction, and the exception path
disagreed with the drift path.

Fix in place:
- New `downgrade_verification(message)` sets `inner["passed"] = False` and appends
  the reason. Both pre-publication outcomes call it.
- `recheck_freeze()` capture-exception branch: records `identityCapture.ok = False`,
  sets `ownedDrift = None`, calls `downgrade_verification`, returns `False`.
  Drift branch calls the same downgrade.
- `publish_final()` now uses `frozen = self.recheck_freeze()` and adds defence in
  depth: `if not frozen and verb == "RELEASE" and status == "PASS": status =
  "FAIL_OR_INCONCLUSIVE"`.
- `persist()` records `FAIL_OR_INCONCLUSIVE` whenever `inner.passed is not True`,
  the publication was not a delivered RELEASE, `ownedDrift`, or any error exists;
  `release` is `RELEASE` iff the managed root is confirmed and the RELEASE was
  delivered, so a verification FAIL still releases real resources.

Independent verification (static + executed double):
- Static: path traced through `recheck_freeze` → `downgrade_verification` →
  `final_status` (`inner.passed` False ⇒ status `FAIL_OR_INCONCLUSIVE`, verb
  `RELEASE` because `root.confirmed is True`) → `publish_final` composes the
  `status=FAIL_OR_INCONCLUSIVE` branch → `persist` writes the same result and
  `release=RELEASE`.
- Executed: `check_identity_capture_failure_fails_but_releases` injects a
  `identities` double that succeeds once then raises `OSError`. Observed line:

  `RELEASE NEWGRANT20261026 … result=FAIL_OR_INCONCLUSIVE … rootConfirmed=True
  rootTerminal=True jobActive=0 handlesClosed=True innerPassed=False
  publicationDelivered=True claimed=RELEASE`

  The check also asserts `release-message.md` starts `RELEASE `, contains
  `status=FAIL_OR_INCONCLUSIVE`, never `status=PASS`, never `no handoff`, contains
  `recorded verification failure`; `window-summary.md` contains
  `result=FAIL_OR_INCONCLUSIVE`; exit is nonzero; and a static guard requires
  exactly two `self.downgrade_verification(` call sites (drift and capture).

Conclusion: final identity-read `OSError` ⇒ validation `FAIL_OR_INCONCLUSIVE`,
resource `RELEASE`, and global message, operator summary and durable `report.json`
agree. `SYNTHETIC_PASS check_identity_capture_failure_fails_but_releases`.

## Observer contract (exact terminal / Job 0 / handles closed before publication)

Enforced in source and covered by four negative checks plus the success check:

- `owned_confirmed()` requires `state == FINISHED`, `release == RELEASE`,
  `cleanupConfirmed`, `handlesRetained is False`, and exact
  `terminal`, `jobActiveProcesses == 0`, `handlesClosed`, plus non-null
  PID / FILETIME / process HANDLE / Job HANDLE.
- `execute()` returns without final publication when the child root is not
  confirmed (`Managed verification root not confirmed terminal/Job0/handlesClosed`).
- `publish_final()` re-checks `root.confirmed is not True` and withholds.
- `final_status()` keeps verification status separate from the resource verb.

Negative checks: `check_root_exit_zero_with_live_job_no_final_publish`,
`check_root_not_terminal_no_final_publish`,
`check_handles_not_closed_no_final_publish`,
`check_missing_root_identity_no_final_publish` — each asserts one publish call
(the ACK), `confirmed=False`, `publication.delivered=False`, `HOLD_UNRELEASED`,
and no `release-message.md`. `check_success_single_window` asserts the order
ACK → managed child → RELEASE and `terminal/Job0/handlesClosed`.

## Suite and DLL fingerprints

- Host runner binds a fingerprint for every suite: `suite_identities` over
  `suite_relative(args)` (four focused suites, plus the named-workspace suite
  only when requested), recorded as `boundSuites`.
- Host runner binds every DLL: `bound_library_paths` resolves the always-bound
  `DEFAULT_LIBRARY` plus each `LIBRARY_ENV_OVERRIDES` entry (`QFLI_PY_DEBUG_TEST_LIBRARY`,
  `QFLI_PYTHON_TEST_LIBRARY`), refuses a missing/non-file path with `ValueError`,
  and `bind_libraries` records path + SHA256 for each.
- Before/after drift is computed for both: `suiteDrift` and `libraryDrift`, and
  either forces `FAIL_OR_INCONCLUSIVE` while a confirmed root still RELEASEs.
- Granted observer freezes both layers: `OWNED_IDENTITIES` contains the inner
  runner, the outer observer and `tool/python_owned_process.py`;
  `check_identities_freeze_both_layers` asserts it and hashes them.

Verified: `SYNTHETIC_PASS check_missing_library_refuses_before_flutter`,
`… check_suite_drift_fails_but_releases`,
`… check_library_drift_fails_but_releases`,
`… check_identities_freeze_both_layers`,
`… check_real_controls_report_opens_merged_suite`.

## Remaining findings (non-blocking)

R1 — low — owner p4 — FIXED (inner verifier re-frozen). The old
`_FakeHelper.run_owned` returned `_phase_report(0)` for an unscripted command.
Now `verify_run_python_host.py` has `_classify(module, command)` which accepts
exactly three shapes: the owned-process control command (`command[1]` is
`test/python_owned_process_control_test.py` and it carries `--grant` and
`--output`), the merged `flutter test --no-pub --concurrency=1` command (suites
restricted to `FOCUSED_SUITES` plus the named-workspace suite), and the scoped
`dart analyze` command (`.dart` paths only). Every other shape raises
`VerificationError`, and an exhausted scripted-report list also raises; there is
no silent success fallback. `check_fake_helper_refuses_unknown_and_exhausted`
proves the unknown shape, the exhausted list, the accepted control shape, and
five malformed shapes (flutter without `--no-pub`, flutter with an unknown
suite, empty `dart analyze`, non-`.dart` analyze scope, control command without
`--output`). `_ok(count)` supplies exactly one report per expected phase call.

R2 — note — owner p6 — `check_optimized_run_is_refused` remains a static source
scan of the wrapper. The verifier's own `-O`/`-OO` refusal is exercised
dynamically (observed exit 2), so the optimized branch is covered in practice.

R3 — note — owner p4 — the control test's synthetic cases still construct
`helper.OwnedJob()`, whose `__init__` calls `C.WinDLL("kernel32")`
(`tool/python_owned_process.py:205`). `CreateJobObjectW` is only called in
`open()`, so no Job handle and no child process is created; the fake kernel owns
the handle state machine. The claim "starts no controlled child" holds.

## What was run

- `python verify_run_python_host.py` (11/11, exit 0) — re-run alone after the
  final inner hash handoff.
- `python verify_run_python_granted_window.py` (27/27, exit 0; root re-ran
  27/27 at 05:38:27).
- `python -O` on both verifiers and on the wrapper (each exit 2, refusal before
  any load or evidence directory).

## What was not run

No real wrapper invocation with real collaborators, no `run_real_controls`, no
publisher or `channel send`, no Dart/Flutter/native/SDK/WSL/HAP/signing/device,
no commit. Only the two synthetic verifiers, which install doubles before every
`module.main`/`module.run` call.

## Spec consistency review — `quality-guidelines.md` section 8 (read-only)

Cross-checked each normative claim in section 8 against the frozen code. Every
claim held; no contradiction found. Exact matches:

- `run_owned(argv, *, timeout_seconds, cleanup_seconds, cwd, log_path,
  report_path, environment=None) -> dict` matches `tool/python_owned_process.py`
  verbatim.
- The required RELEASE evidence list matches the host `run_phase` `confirmed`
  predicate and the observer `owned_confirmed`: both AND `state == FINISHED`,
  `release == RELEASE`, `cleanupConfirmed`, `handlesRetained is False`,
  `terminal`, `jobActiveProcesses == 0`, `handlesClosed`, plus the exact PID,
  FILETIME and process/Job HANDLE identity.
- `DEFAULT_LIBRARY = native/build/windows/qfli_py_ffi.dll`, plus the effective
  `QFLI_PY_DEBUG_TEST_LIBRARY` and `QFLI_PYTHON_TEST_LIBRARY` overrides, match
  `run_python_host.py`; a missing path refuses before any command or evidence.
- The 180 s observer ceiling, fresh-grant reserve/replay rules,
  never-kill-by-scanned-PID, child-never-publishes, and every validation-matrix
  row match the code and the checks.
- "Unknown fake commands raise; no fake may fall back to real execution" now
  holds in both verifiers.

Notes (non-blocking):

- N1 — the host verifier has no dedicated "deliberately widened guard" negative
  control. The property holds structurally because `_install`/`_reset` precede
  every `module.run`/`module.main`, and `check_second_values_and_output_rejected`
  asserts `not helper.calls` and no evidence. The granted verifier has the
  explicit control (`check_widened_guard_still_zero_io`).
- N2 — the host `_classify` control shape keys on `command[1]` only and does not
  require `command[0]` to be the Python interpreter. The fake never executes a
  command, so there is no real-I/O risk; classification is cosmetic.
- N3 — `check_missing_library_refuses_before_flutter` exercises the default DLL
  and the `QFLI_PY_DEBUG_TEST_LIBRARY` override. The `QFLI_PYTHON_TEST_LIBRARY`
  override shares the same code path but is not separately exercised.

Synthetic results establish decision logic only; the spec's requirement to run
real Windows process controls under a fresh grant before SDK-dependent
validation remains an open gate, consistent with the not-run list.

## Frozen readiness

FINAL PASS. F1, F2, F3 and F4 are fixed and verified; the root-found
freeze-exception parity defect F7 is fixed and independently verified (validation
FAIL, resource RELEASE, global/durable agreement). The observer publishes only
after exact terminal / Job 0 / handle closure, suite and DLL fingerprints are
bound and drift-gated, and neither verifier can pass vacuously on a non-Windows
host or under `-O`. The prior R1 host-fake fallback is fixed: the inner fake now
classifies command shapes, raises on an unrecognised shape and raises on report
exhaustion, proven by `check_fake_helper_refuses_unknown_and_exhausted`. Spec
section 8 is consistent with the frozen code (notes N1–N3 only).

Final artifacts, PASS with no blocker:

| item | hash | status |
| --- | --- | --- |
| inner verifier `verify_run_python_host.py` | `a1965dd582d642dc…` | PASS 11/11, exit 0 |
| outer wrapper `run_python_granted_window.py` | `6abdb3f88b8b994b…` | reviewed, no defect |
| outer verifier `verify_run_python_granted_window.py` | `e22145649e194fe3…` | PASS 27/27, exit 0 |
| inner runner `run_python_host.py` | `395bbd439e0da00c…` | reviewed, no defect |
| spec `quality-guidelines.md` section 8 | mtime 05:24:28 | consistent, notes N1–N3 |

**No exact blocker.**
