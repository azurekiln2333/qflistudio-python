# Independent review of consumer host scope

Initial review: 2026-10-26T10:31:05+08:00.
Final source recheck: 2026-10-26T12:31:37+08:00.
Reviewer: `/root/review_python_consumer_tests` (`trellis-check`).
Task: `.trellis/tasks/10-22-python-offline-debugger`.

Current result: the identified report-field defect is fixed in p4's final source. No remaining concrete source blocker was identified within this consumer-scope extension review. SDK commands, real controls, native work, and device operations remain UNRUN by this reviewer.

## Scope and restrictions

Source-only independent review of the optional `--include-consumer-tests` extension in four files under `research/fixtures`. The final recheck followed the parent's confirmation of p4's explicit final delivery. This reviewer inspected source, read existing synthetic logs, and computed hashes. This reviewer did not import or execute the fixtures, run synthetic checks, start subprocesses through them, invoke SDK commands, invoke real controls, publish channel messages, or touch native/device/signing state. The only write is this report. Pi p4 owns fixture changes.

## Exact final source identities

Paths are relative to this task's `research/fixtures` directory. These are the actual final SHA256 values independently read from disk, matching p4's delivered identities.

| File | Final SHA256 |
| --- | --- |
| `run_python_host.py` | `3d18b09c2806c3f6432471405874b6dc1f551e47281a4c1d04efc0edb96109b6` |
| `verify_run_python_host.py` | `5af93844e85c8b9f6a7d101fecc0b97cf316f210f7b95e7445e0cb7030d36376` |
| `run_python_granted_window.py` | `64faaa8d6d6ef6e47b1c188b74f1daf148320be3a8d2ccfce7fd67864e25bcb8` |
| `verify_run_python_granted_window.py` | `c04a8227d26c10c186e43ea4798ad1d63adf02228f3c09d55c71eba6b05ef51b` |

The initial recorded inner verifier hash was `01c321cdaa918cb93cc64069f638707821a4fed10d4d861f21e609398a565cf8`. The final verifier adds the exact default evidence assertions described below. Both outer files retain their previously recorded hashes.

Snapshot clarification: source reads and hashing during the initial review were not atomic while p4 was editing. The initial unconditional report-field observation preceded the runner hash capture. The captured runner hash was already `3d18b09c...`, which the final recheck proves contains the conditional fix. It must not be represented as an exact hash of the earlier defective runner source. No exact pre-fix runner hash was established by this reviewer.

## Findings (fixed by p4; independently source-rechecked)

### Default reports no longer claim unselected consumers are bound

Original issue: `run_python_host.py` unconditionally populated `boundConsumers` with both consumer names even when the option was disabled. Actual command selection, `boundSuites`, and suite hashing excluded them. This mislabeled the evidence. The original default-off synthetic check did not inspect the misleading field.

Final fix at `research/fixtures/run_python_host.py:303`: `boundConsumers` is now `list(CONSUMER_SUITES)` only when `args.include_consumer_tests` is true, and is otherwise `[]`.

Final regression coverage in `verify_run_python_host.py`, `check_consumer_tests_default_off`:

- Requires the selected default suite tuple to equal the four focused suites plus the explicitly requested named-workspace suite.
- Requires `boundConsumers == []`.
- Requires `boundSuites` to equal that exact default set in order.
- Requires both consumer names to be absent from the command and bound suite list.
- Requires both consumer names to be absent from both `suiteIdentitiesBefore` and `suiteIdentitiesAfter`.

The enabled-path check still requires both consumer names in the single merged command, both identity captures, and `boundConsumers`. The defect is resolved by source inspection. This reviewer did not execute the regression checks.

## Findings (not fixed / remaining)

No remaining concrete source blocker was identified in the reviewed consumer-scope extension. This does not establish host execution, process cleanup behavior under real controls, or installed OHOS acceptance.

## Source-path conclusions

- Outer-to-inner flag: both parsers declare the opt-in `store_true` flag. The outer child-command builder appends exactly `--include-consumer-tests` when enabled and omits it otherwise. The outer synthetic verifier checks enabled forwarding, default omission, and that consumers do not imply named-workspace selection.
- Selected suites: the inner suite selector preserves the four focused suites, independently adds the named-workspace suite when requested, and adds exactly `test/python_tools_page_test.dart` and `test/python_highlighting_test.dart` for the consumer flag. One merged `flutter test --no-pub --concurrency=1` command consumes that set. This option accepts no arbitrary suite string.
- Identity capture: the actual selected suite set is strictly resolved and hashed with SHA256 before execution and again in `finally`. Thus both enabled consumer files use the existing identity mechanism. Missing selected files refuse setup. Final capture failures add errors and prevent PASS.
- Each-consumer drift: the inner synthetic drift check loops over each exact consumer name separately. Each iteration requires that consumer in `suiteDrift`, requires nonzero return/non-PASS verification, and separately requires RELEASE for confirmed cleanup. The production PASS predicate rejects any nonempty `suiteDrift`.
- Strict doubles: the inner fake recognizes controls, the merged Flutter command restricted to the explicit suite allowlist, and Dart analysis. Unknown shapes and exhausted scripted results raise; there is no real-process fallback. The outer fake also rejects unknown command kinds and exhausted scripts, and returns only scripted reports. Adding the two exact consumer suite names does not introduce an arbitrary command fallback.
- Defaults: the consumer flag remains false by default. Focused suite selection and the independent named-workspace option remain intact. The default scoped analysis command is unchanged; this flag expands test scope only. The final `boundConsumers` evidence now matches selection.
- Controls and release: the inner controls phase must be confirmed and pass before any merged suite starts. The wrapper retains its same-grant controls evidence checks. Outer verification checks the inner result. Verification failure and confirmed resource release remain separate outcomes. These source observations do not prove actual control execution or process cleanup.
- Acceptance boundaries: this extension supplies no native rebuilding, signing, device selection, installed runtime, application rendering, or OHOS acceptance result. The highlighting consumer suite itself exercises core `.py` rendering, not actual application editor-route or Python profile registration acceptance.

## Existing final synthetic logs

Actual persistent mirror directory: `build/python-debugger-consumer-tests-synthetic-20261026`. The suggested `build/python-host-synthetic-consumer-20261026` name was not the directory located on disk.

| Log | Final SHA256 | Recorded checks |
| --- | --- | --- |
| `build/python-debugger-consumer-tests-synthetic-20261026/inner.log` | `532476f14f9113380a113556cbb0c9b34dc21e99a6c869cd29c1e12ffb76e866` | 14 `SYNTHETIC_PASS` lines |
| `build/python-debugger-consumer-tests-synthetic-20261026/outer.log` | `642d92943cf4f53170f113c5d82aa0a3c9a09f1a417ba9389e0f103827f9d098` | 28 `SYNTHETIC_PASS` lines |

The corresponding copies in `research/fixtures/synthetic-inner-consumer-tests-20261026.log` and `synthetic-outer-consumer-tests-20261026.log` have identical hashes to these build mirrors.

The inner log ends with `SYNTHETIC_VERIFY_PASS no real process was started`. The outer log ends with `SYNTHETIC_VERIFY_PASS no child process, publisher or channel call was made`. These are p4's existing synthetic logs inspected by this reviewer, not independent reruns. They do not establish real controls, SDK execution, current-source native runtime, or installed OHOS behavior.

Initial log hashes were `974471bb76bc7e2ba44eb3cd872c91daa55ee10564714fe9a723623f15bbe41c` and `dba45df82c18abf2d20db92623a49b444ebd0faff4e964f43dc0ce6965797020`; those are historical and do not identify the final logs above. Per-check temporary evidence directories under `build` are removed by verifier cleanup. The final mirrored logs persist separately.

## Verification

- Lint: NOT RUN.
- TypeCheck: NOT RUN.
- Synthetic verification: NOT RUN by this reviewer. Final delivered logs inspected only; they record 14 inner and 28 outer synthetic passes.
- Actual Dart/Flutter/analyzer SDK commands: UNRUN.
- Actual process controls and granted-window publication: UNRUN.
- Native rebuild/runtime, OHOS build, device operations, installation, launch, and signing: UNRUN.
- Completed: source/data-flow/strict-double recheck, exact final SHA256 capture, and inspection of final mirrored logs.

The source defect is resolved for the final identities recorded above. No execution window or installed-device acceptance is implied.
