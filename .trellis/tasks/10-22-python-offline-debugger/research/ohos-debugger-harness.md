# Debugger audit repairs and bounded host runner

Date: 2026-10-24. Owner: `/root/python_debugger_audit`. This note records
source-only work. No Dart, Flutter, analyzer, test, compiler, SDK, WSL, signing,
HAP or device process was started.

## Exclusive files

- `tool/python_debugger_ohos_audit.dart` — five source-confirmed repairs.
- `test/python_debugger_audit_test.dart` — fault-injection regressions.
- `.trellis/tasks/10-22-python-offline-debugger/research/fixtures/run_python_host.py` — bounded runner.
- `.trellis/tasks/10-22-python-offline-debugger/research/fixtures/verify_run_python_host.py` — synthetic runner verification.
- This note.

No shared core, native, product adapter or preparer file was edited. Other
workers' edits are preserved.

## Repairs from `debugger-audit-review.md`

1. Stale-token deadline. `_rejects` now takes the `_Pending` tracker and runs the
   rejection through `tracker.wait`, so the whole assertion is bounded by the
   operation deadline. A timeout is rethrown with timeout classification; the
   underlying future stays observed, so cleanup is not accepted and the work
   directory is retained until actual settlement.
2. Failed-phase gate. `_ObservedSession.finished` now takes
   `DebugPhase expectedPhase` (default `terminated`) and requires it before the
   exit code. The explicit runtime-exception case passes `DebugPhase.failed`.
   A `failed` snapshot with exit 0/130 can no longer satisfy a success or
   cooperative-Stop exit.
3. Early stream observation. `normalRun` observes both stdout/stderr drains with
   `tracker.observe` before awaiting the native exit, and observes the actual
   exit independently. An early stream failure is handled immediately and
   surfaced as a case failure only after native settlement. A stalled drain keeps
   the project and pending exit retained.
4. Bounded final cancellation. `_ObservedSession.closeObservation` now wraps
   `subscription.cancel()` in a `.then` and bounds it through `tracker.wait`.
   Unsettled or failing cancellations are recorded in the session `errors` list.
   `report['cleanupErrors']` is the union of `_Pending.errors` and every session's
   `errors`, so the stalled-cancellation diagnostic is present in cleanup
   evidence while the `cleanup`/`cleanupConfirmed` decision is unchanged (it still
   requires every session's `errors` to be empty). The finalization awaits all
   observations before computing cleanup and before freezing the report. A
   never-settling cancel cannot hang the audit or turn a timeout into successful
   cleanup.
5. Frozen late snapshots. A `evidenceFrozen` flag gates the launch snapshot
   callback, so a late launch that settles after the audit returned still runs
   its real disposal and observation cleanup but no longer appends to the
   already-returned `report['snapshots']`.

## Fault-injection tests added

- `stale-token rejection is bounded and retains files until settlement`: a
  scripted session hangs the stale `resume`; the first case must report
  `timeout`, cleanup must be unconfirmed, files retained, and Dispose requested.
- `failed phase with exit 0 is not accepted as a successful run`: scripted
  `failed`/exit 0 with correct output must fail the case.
- `early stream error is observed before delayed exit and fails the case`: a
  runner fails stdout before completing its delayed exit; the case must fail on
  the drain, not as an unhandled zone error.
- `failed phase with exit 130 is not accepted as a cooperative Stop`: scenarios
  1 and 2 pass, then paused Stop ends `failed`/130 and must fail.
- `stalled update cancellation is bounded and keeps the work directory`: a
  subscription whose `cancel()` never settles must leave cleanup unconfirmed,
  files retained and a cancellation error in evidence.
- The existing late-launch test now also compares a serialized copy of
  `report['snapshots']` before and after late settlement.

The scripted scenario doubles implement the real audit contract (session id,
increasing revisions, pause tokens, frames/locals, breakpoints, terminal phase,
`done` and stream close). They do not execute Python; the production test keeps
the real adapter/VM side effects.

## Bounded host runner

`research/fixtures/run_python_host.py` wraps every phase in the shared
`tool/python_owned_process.py` `run_owned` API. Import starts no process and
writes nothing. Plan is 180 s (`--plan-seconds`), work = plan − cleanup
(`--cleanup-seconds`, default 10).

Order:

1. `owned-process-controls`: `python test/python_owned_process_control_test.py
   --grant <grant> --output <dir>/controls` (default `--control-seconds` 60; the
   inner real+synthetic worst case is about 40.3 s, so the outer budget keeps a
   margin).
2. `focused-suites`: one merged
   `flutter test --no-pub --concurrency=1 test/python_debugger_test.dart
   test/python_debugger_native_test.dart test/python_debugger_audit_test.dart
   test/python_content_audit_test.dart` call. With `--include-named-workspace`
   `test/python_named_workspace_test.dart` is appended to the same call.
3. `scope-analysis`: `dart analyze <owned scope>`.

In-run controls always run first. A supplied `--controls-report` is an
additional cross-check and must match the same grant and be a real (non
synthetic) `PASS`. `--output` must resolve under `<root>/build`; the wrapper
rejects any other location before creating evidence or starting a phase.

Each phase returns only after the exact root is terminal, the private Job is
empty and handles are closed. `run_phase` records `rootTerminal`,
`jobActiveProcesses`, `handlesClosed` and `handlesRetained`, and `confirmed`
requires all of: `cleanupConfirmed` true, `release` RELEASE, state `FINISHED`,
`handlesRetained` false, `rootTerminal` true, `jobActiveProcesses` 0 and
`handlesClosed` true. A terminal root with open handles is not confirmed. If
cleanup is unconfirmed, `run_owned` stays in HOLD_UNRELEASED retaining the exact
handles and the wrapper starts no later phase. The wrapper publishes `RELEASE`
only when every executed phase confirmed cleanup; otherwise `HOLD_UNRELEASED`.
Drift in an owned file, a bound suite, a bound binary or the audit inputs fails
the result but never fabricates a HOLD, so a real confirmed cleanup still
reports RELEASE.

Source binding: `OWNED_IDENTITIES` includes the runner and verifier themselves,
the shared owned-process helper, the audit harness, its test and the control
test. `suite_identities` hashes every executed focused suite, and the
named-workspace suite when `--include-named-workspace` is set, so binding is not
limited to the audit test. `bind_libraries` records the absolute path and SHA256
of every bound frozen binary: the default
`native/build/windows/qfli_py_ffi.dll` (always bound because the audit suite and
the default backend load it) plus `QFLI_PY_DEBUG_TEST_LIBRARY` and
`QFLI_PYTHON_TEST_LIBRARY` when set. A missing or non-file path refuses the run
before any evidence directory or command exists, so a Dart skip cannot turn the
run green. Bound binaries are frozen prebuilt binaries; this run never builds,
refreshes or claims them as products of the current native sources.

The runner also imports `tool/python_audit_inputs.py` and stores
`collect_inputs` digests for the real `lib` product tree and the
`qfli_studio_core` shared `lib` tree before and after, plus the changed-path
drift, so a mid-run source change is visible.

The controls gate requires both `confirmed` (exact cleanup) and `passed`
(command exit 0). A confirmed but nonzero controls phase records the failure and
ends the run without composing any Flutter phase, while still reporting the
actual `RELEASE` cleanup. `--plan-seconds` must be finite, positive and at most
180; every other seconds value must be finite and positive, so `nan`, `inf`,
zero, negative and over-budget plans are rejected before any command is built.
`--controls-report` accepts only a same-grant report whose `result` is `PASS`
with a nonempty real `cases` list; `SYNTHETIC_PASS` and other grants are
rejected and no later phase starts.

Commands (to run only under a NEW named grant):

```text
python .trellis/tasks/10-22-python-offline-debugger/research/fixtures/run_python_host.py \
  --grant <NEW_GRANT> --next-owner <OWNER> --control-only \
  --output build/python-debugger-control-<NEW_GRANT>

python .trellis/tasks/10-22-python-offline-debugger/research/fixtures/run_python_host.py \
  --grant <NEW_GRANT> --next-owner <OWNER> \
  --controls-report build/python-debugger-control-<NEW_GRANT>/report.json \
  --include-named-workspace \
  --output build/python-debugger-host-<NEW_GRANT>
```

`--control-only` runs only the real owned-process controls under a short plan.
No native build, HAP, signature, WSL or device gate is closed.

### Synthetic verification of the runner

`research/fixtures/verify_run_python_host.py` replaces `run_owned`,
`collect_inputs`, `bind_libraries` and the identity seams with doubles and
starts no real process. It proves: a confirmed but failing controls phase stops
after one call with zero Flutter phases; an unconfirmed controls phase keeps
HOLD_UNRELEASED and starts no Flutter; a terminal root with open handles is not
confirmed and starts no Flutter; a `SYNTHETIC_PASS` controls report is rejected
with zero Flutter; a same-grant real `PASS` report opens exactly one merged
`--no-pub --concurrency=1` focused call containing all four suites;
`--include-named-workspace` joins that same call and adds the suite to
`boundSuites`; a missing default DLL and a missing override DLL each refuse the
run with zero composed commands and no evidence directory; focused-suite drift
and bound-DLL drift each fail verification while the confirmed cleanup still
publishes RELEASE; and `nan`/`inf`/zero/negative/over-180 seconds plus
non-`build` output paths are rejected before any command is composed.

The double itself is fail-closed. `_FakeHelper.run_owned` classifies every
command and accepts only three exact shapes: the owned-process control
(`python test/python_owned_process_control_test.py --grant … --output …`), the
merged `flutter test --no-pub --concurrency=1` call over the known suites, and
the scoped `dart analyze` call over `.dart` inputs. An unrecognized or malformed
command raises, and so does a recognized command with no remaining scripted
report, so an unexpected extra call can never silently return a success. The
`check_fake_helper_refuses_unknown_and_exhausted` regression proves both
refusals directly, plus the malformed variants of each recognized shape.

Every check uses an always-on `require` rather than a bare `assert`, so
`python -O` cannot reduce the file to a vacuous pass, and `main` refuses an
optimized interpreter (exit 2). `main` also refuses a non-Windows host (exit 2),
because the wrapper is Windows only and the negative argument checks would
otherwise pass for the wrong reason with the platform guard firing first.
Module seams are reset to the real implementations before every check, so a
double installed by an earlier check cannot satisfy a later one. Run with:

```text
python .trellis/tasks/10-22-python-offline-debugger/research/fixtures/verify_run_python_host.py
```

Result: `SYNTHETIC_VERIFY_PASS`, 11/11 checks, exit 0. `python -O` and a
non-Windows host are both refused. This is a double-level check, not a real
controls, Dart, Flutter, native or device result.

## Verification status

- Source edits and the runner were written.
- `python -m py_compile` and `ast.parse` on `run_python_host.py` passed.
- The synthetic verifier passed 11/11 (`SYNTHETIC_VERIFY_PASS`) with exit 0; it
  started no real control, Dart, Flutter, native or device process. `python -O`
  and a non-Windows host are refused with exit 2.
- UNRUN, pending the next named host grant: all Dart/Flutter tests and analyzer,
  the real owned-process controls, the runner's real phases, and every native,
  HAP, signature, WSL and device acceptance. No skip or timeout result is
  claimed here.

## Reviewed source identities (SHA256)

| File | SHA256 |
| --- | --- |
| `tool/python_debugger_ohos_audit.dart` | `314424e87eb822e948eeed3110c2b0a2e136c637dd0df6aedd9e5ff93ee0cbdd` |
| `test/python_debugger_audit_test.dart` | `fc8f919e541015048232ada7331b21cc6c0ee54af566e5ff812d82d72daa44f4` |
| `research/fixtures/run_python_host.py` | `395bbd439e0da00c3587337b8d7ce73aa76aa8968a0a208d649b354b782dd547` |
| `research/fixtures/verify_run_python_host.py` | `a1965dd582d642dc0608391dac6ebdacaa9ad75eb9a8106c3573a63bf0acb3dc` |
| `tool/python_owned_process.py` | `3061cf1d6258061b41ba656dd5f2dd9da5f1907d40e861aa3ff3152f35beadfd` |

### Bound frozen binary (not built by this run)

The runner binds `native/build/windows/qfli_py_ffi.dll` by absolute path and
SHA256 before and after. It is a frozen prebuilt binary; this run neither builds
nor owns it and makes no claim that it matches the current native sources.

| Bound binary | SHA256 |
| --- | --- |
| `native/build/windows/qfli_py_ffi.dll` (default) | `52e7400fdcd50cb03d94026ad6331c3b27770e2795e3418259d54e4d3a79a54e` |

`QFLI_PY_DEBUG_TEST_LIBRARY` and `QFLI_PYTHON_TEST_LIBRARY` add further bound
paths; every bound path must exist or the run refuses before composing a
command.

Inner runner/verifier hashes changed in this freeze; p6 must re-freeze the inner
hash pair (`run_python_host.py`, `verify_run_python_host.py`) and p3 must re-run
its source-only guard review against the hardened verifier double.