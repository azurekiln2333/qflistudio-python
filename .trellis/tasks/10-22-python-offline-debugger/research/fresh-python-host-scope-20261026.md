# Fresh Python host scope — consumer suites and budget honesty

Date: 2026-10-26. Owner: Python for `10-22-python-offline-debugger`.
Status: **preparation plus the narrow authorized implementation.** No READY, no
grant requested, no replay. READY704 was retired by the RETIRE message 732; 732 is
a message, not a retired grant.

Only synthetic verifiers ran, with doubles. No real child, publisher, channel,
control suite, SDK, `pub get`, native build or device action was performed. No
helper, control test or core file was touched.

## 1. Delivered in this batch

| File | Bytes | SHA256 |
| --- | --- | --- |
| `research/fixtures/run_python_host.py` | 23603 | `3d18b09c2806c3f6432471405874b6dc1f551e47281a4c1d04efc0edb96109b6` |
| `research/fixtures/verify_run_python_host.py` | 27229 | `5af93844e85c8b9f6a7d101fecc0b97cf316f210f7b95e7445e0cb7030d36376` |
| `research/fixtures/run_python_granted_window.py` | 40328 | `64faaa8d6d6ef6e47b1c188b74f1daf148320be3a8d2ccfce7fd67864e25bcb8` |
| `research/fixtures/verify_run_python_granted_window.py` | 47762 | `c04a8227d26c10c186e43ea4798ad1d63adf02228f3c09d55c71eba6b05ef51b` |

Synthetic logs (doubles only, no real child or publisher). Full relative paths
from the repository root, because a bare filename is not findable:

| Log (full relative path) | Bytes | SHA256 |
| --- | --- | --- |
| `build/python-debugger-consumer-tests-synthetic-20261026/inner.log` | 18163 | `532476f14f9113380a113556cbb0c9b34dc21e99a6c869cd29c1e12ffb76e866` |
| `build/python-debugger-consumer-tests-synthetic-20261026/outer.log` | 46707 | `642d92943cf4f53170f113c5d82aa0a3c9a09f1a417ba9389e0f103827f9d098` |

Byte-identical mirror copies kept beside the fixtures, so either path resolves to
the same evidence:

| Log (full relative path) | Bytes | SHA256 |
| --- | --- | --- |
| `.trellis/tasks/10-22-python-offline-debugger/research/fixtures/synthetic-inner-consumer-tests-20261026.log` | 18163 | `532476f14f9113380a113556cbb0c9b34dc21e99a6c869cd29c1e12ffb76e866` |
| `.trellis/tasks/10-22-python-offline-debugger/research/fixtures/synthetic-outer-consumer-tests-20261026.log` | 46707 | `642d92943cf4f53170f113c5d82aa0a3c9a09f1a417ba9389e0f103827f9d098` |

Observed results: inner verifier **14/14** checks, exit 0, final line
`SYNTHETIC_VERIFY_PASS no real process was started`; outer verifier **28/28**
checks, exit 0, final line `SYNTHETIC_VERIFY_PASS no child process, publisher or
channel call was made`; `python -O` on each exits 2 with its refusal printed. No
`__pycache__` and no `build/_verify_*` directory remains.

### 1.1 Defect found by root, and the fix

Root's spot check was correct. The report field was written unconditionally as
`"boundConsumers": list(CONSUMER_SUITES)` at `run_python_host.py:303`, so a
**default** run advertised two consumer suites as bound even though it never
executed them and never hashed them. That is a false claim of coverage, and it is
exactly the class of defect the drift binding exists to prevent: a consumer file
could be missing, edited or skipped and the report would still say it was bound.

Fixed to be flag-conditional:

```python
"boundConsumers": (list(CONSUMER_SUITES)
                    if args.include_consumer_tests else []),
```

The regression `check_consumer_tests_default_off` was extended from "absent from
the command" to exact evidence:

- `report["boundConsumers"] == []` exactly, so an unconditional claim fails;
- `report["boundSuites"]` equals the default tuple `FOCUSED_SUITES +
  (NAMED_WORKSPACE_SUITE,)` exactly, not merely a superset check;
- each consumer name is absent from `boundSuites`, from `suiteIdentitiesBefore`
  **and** from `suiteIdentitiesAfter`, so an unbound-but-claimed file cannot pass;
- `suite_relative()` on a default namespace returns exactly that tuple, proving
  the bound set itself excludes the consumers rather than only the report text.

`check_consumer_tests_join_same_call` was strengthened in the same direction: with
the flag set it now requires `boundSuites` to equal the focused-plus-consumers
tuple exactly. Both verifiers were re-run after the change; the counts are
unchanged at 14/14 and 28/28, and the logs above are the post-fix runs.

What was added:

- `run_python_host.py`: a fixed `CONSUMER_SUITES` tuple of exactly
  `test/python_tools_page_test.dart` and `test/python_highlighting_test.dart`, a
  new `--include-consumer-tests` flag, and a report field `boundConsumers` that is
  empty unless that flag is set.
- `run_python_granted_window.py`: `--include-consumer-tests`, threaded to the
  child unchanged.
- Both verifiers: new checks proving both consumers execute in the one merged
  call, are bound through the existing suite-identity mechanism, and that drift of
  **each** consumer individually refuses PASS while the confirmed root still
  releases. The inner verifier also proves the default set stays free of them.

The two suites are bound through the same `suite_relative(args)` /
`suite_identities` path as the focused and named-workspace suites, so
`boundSuites`, `suiteIdentitiesBefore/After` and `suiteDrift` all cover them. There
is no arbitrary suite or command injection: the set is a module constant, and the
flag can only add those two exact files to the single merged call.

## 2. Superseded and NOT re-READY

- `run_python_host.py` was `22623` / `395bbd439e0da00c…`: **superseded**.
- `verify_run_python_host.py` was `21390` / `a1965dd582d642dc…`: **superseded**.
- The intermediate revision of this batch, `run_python_host.py` `23534` /
  `2a87c8838ccde872…` and `verify_run_python_host.py` `25683` /
  `01c321cdaa918cb9…`, carried the unconditional `boundConsumers` defect and is
  also **superseded** by §1. Only the §1 hashes are current.
- Patch B and the F1 deliverable are untouched by this batch.
- `tool/python_owned_process.py`, `test/python_owned_process_control_test.py`,
  `tool/python_debugger_ohos_audit.dart` and `test/python_debugger_audit_test.dart`
  are unchanged, so four of the six fixture identities in
  `granted-window-source.md` are now stale and two are still valid.
- `granted-window-source.md` and `host-observer-synthetic-verification-20261026.json`
  pin the superseded hashes and the old check counts. I do not own them; root must
  re-freeze them before any window. **No new READY exists and none is proposed.**

## 3. The seven files, resolved by exact name

| # | Suite | Bytes | SHA256 (first 16) | Role |
| --- | --- | --- | --- | --- |
| 1 | `test/python_debugger_test.dart` | 19182 | `80f16c510d820bfd` | `FOCUSED_SUITES` |
| 2 | `test/python_debugger_native_test.dart` | 10620 | `64be087ad6116f8d` | `FOCUSED_SUITES` |
| 3 | `test/python_debugger_audit_test.dart` | 26806 | `fc8f919e54101504` | `FOCUSED_SUITES` |
| 4 | `test/python_content_audit_test.dart` | 18325 | `189b4df2bc645beb` | `FOCUSED_SUITES` |
| 5 | `test/python_named_workspace_test.dart` | 21405 | `4841f06604267be5` | `NAMED_WORKSPACE_SUITE` |
| 6 | `test/python_tools_page_test.dart` | 41698 | `248fba741725af91` | `CONSUMER_SUITES` |
| 7 | `test/python_highlighting_test.dart` | 9680 | `bb094416539aecc3` | `CONSUMER_SUITES` |

Both requested names match files on disk exactly, so the target really is seven.

## 4. Corrections to the earlier draft of this note

Stated explicitly, because each was wrong or unsupported before:

1. **732.** The earlier draft called 732 a retired grant. It is the RETIRE message
   that retired READY704. Corrected.
2. **`--scope` never added suites.** That was already written correctly; it remains
   true and is now moot, because the consumer suites have their own flag.
3. **Consumers are additive, so a "just the two consumers" window is impossible.**
   The earlier draft's Window B implied a two-suite run. With the delivered flag the
   merged call is `FOCUSED_SUITES` (4) plus consumers (2), plus the named-workspace
   suite if also requested: 6, or 7 with named. It cannot be 2. Removed and
   corrected; narrowing the set would require arbitrary suite injection, which is
   not implemented on purpose.
4. **The Windows controls are CURRENTLY UNRUN.** The earlier draft said the real
   control worst case is about 40.3 s. No real control run exists: the only control
   files on disk are `build/owned-process-synthetic-source-gate-*/controls.json`,
   all `result: SYNTHETIC_PASS` with no timing. That figure is a source comment in
   the runner, not evidence. It must not be cited as a measurement.
5. **No "budget fits" claim.** With no measured suite or control runtime, no window
   can be asserted to fit. The reserved arithmetic below is bookkeeping, not a
   capacity result.

## 5. `re_editor` direct dev-dependency and current graph resolution

Unchanged from the earlier draft and still the concrete risk for suite 7, which
imports `package:re_editor/re_editor.dart` directly. Suite 6 pulls the editor in
transitively through `main.dart`, `home_page.dart` and `quick_tools_page.dart`.

- `pubspec.yaml:30-32` overrides `re_editor` to
  `path: ../qfli_studio_core/vendor/re_editor`.
- `pubspec.yaml:40` declares `re_editor: ^0.10.0` under `dev_dependencies`.
- `.dart_tool/package_config.json` (12595 B, SHA256 `cb81efd271435d0d…`, mtime
  2026-10-22 15:53) maps `re_editor` to `../../qfli_studio_core/vendor/re_editor`,
  so the override wins and the direct import is legal today.

Consequences: the merged call uses `--no-pub`, so it never re-resolves and depends
on that existing `package_config.json`; a fresh host without `.dart_tool` would
need `flutter pub get`, which is network/toolchain work outside every grant; the
override points into a sibling repository, so an absent checkout breaks resolution;
and because `package_config.json` predates the current pubspec declaration, a
declared-but-unresolved graph change would pass silently. Check freshness
read-only before any consumer window. Do not add `pub get` to any window.

## 6. Budget: reserved arithmetic only

From `granted-window-source.md`, the observer composition is ACK 12 + inner 138 +
outer cleanup 10 + publish 15 + margin 5 = 180. The child gets
`--plan-seconds 123 --cleanup-seconds 5`, so its wall is `123 + 3 x 5 = 138` and its
reserved work budget is `123 - 5 = 118 s`.

Two facts, both from source:

- **Controls always run.** `run()` calls `run_controls(...)` before the
  `--controls-report` branch, so that flag adds a same-grant real-PASS requirement
  and does not skip the in-run controls. `--control-only` skips the suites only. So
  every window reserves the controls cost.
- **`--control-seconds 60` is a timeout cap, not a cost.** It is applied as
  `min(args.control_seconds, args.work_seconds)`.

Honest position: the controls duration is **unmeasured on Windows** (UNRUN), and no
suite timing exists for any of the seven files on a fresh host. Therefore:

| item | seconds | status |
| --- | --- | --- |
| child reserved work budget | 118 | arithmetic |
| controls reserve (cap) | up to 60 | cap, unmeasured cost |
| remainder for suites + analyze | 58 to 118 | **unknown sufficiency** |

The earlier draft's "~78 best / ~58 long-controls" figures and its "does not
honestly fit" verdict both rested on the unmeasured 40.3 s. They are withdrawn. The
correct statement is narrower: the reserved budget is 118 s for controls plus every
requested suite plus the scoped analyze; whether that suffices is a measurement
question, and no measurement exists.

## 7. Recommended shape

Because consumers are additive, a consumer window necessarily re-runs the focused
suites. Two shapes are possible; the first is unchanged from before.

**Window A — default focused set (no consumers), frozen semantics.**

```powershell
python .trellis/tasks/10-22-python-offline-debugger/research/fixtures/run_python_host.py `
  --grant <GRANT-A> --next-owner <owner> `
  --output build/<GRANT-A>-host `
  --plan-seconds 123 --cleanup-seconds 5 --control-seconds 60 --min-phase-seconds 5 `
  --include-named-workspace
```

`--scope` omitted, so the default scoped analyze over
`tool/python_debugger_ohos_audit.dart` and `test/python_debugger_audit_test.dart`
is used.

**Window B — the same focused set plus the two consumers, consumers bound.**

```powershell
python .trellis/tasks/10-22-python-offline-debugger/research/fixtures/run_python_host.py `
  --grant <GRANT-B> --next-owner <owner> `
  --output build/<GRANT-B>-host `
  --plan-seconds 123 --cleanup-seconds 5 --control-seconds 60 --min-phase-seconds 5 `
  --include-consumer-tests `
  --scope test/python_tools_page_test.dart `
  --scope test/python_highlighting_test.dart `
  --scope lib/python_tools_page.dart
```

This runs six suites (four focused plus the two consumers), not two. If
`--include-named-workspace` is also passed it runs seven. The `--scope` flags only
supply `dart analyze` arguments; they never add a test.

Through the observer, the same flag is `--include-consumer-tests`, threaded to the
child unchanged (proved by `check_consumer_tests_threaded_to_child`).

Whether one window can hold the reserved work is unmeasured. Measure first: run a
window under a new grant, read the per-phase `elapsedSeconds`, and only then decide
between one window and a split into two grants. Do not pre-commit a split or a
"fits" claim before that evidence exists. If a split is needed, Window A covers the
focused set and Window B covers the additive consumer set, at the cost of running
the controls phase and the focused suites twice.

## 8. Preconditions before any window

1. A NEW named grant issued by C per window. No grant is requested or assumed here,
   and no replay of READY704/732 occurs.
2. Root re-freezes the superseded identities in `granted-window-source.md` and
   `host-observer-synthetic-verification-20261026.json` against the hashes in §1,
   and re-runs both synthetic verifiers for the frozen revision.
3. Read-only `re_editor` freshness check: `package_config.json` entries versus the
   `pubspec.yaml` declarations, and confirmation that
   `../qfli_studio_core/vendor/re_editor` exists. No `pub get`.
4. The bound frozen binary must still exist (`native/build/windows/qfli_py_ffi.dll`
   = `52e7400f…`); a missing binary refuses the run before any command is composed.
5. Evidence under `<root>/build` only, one fresh directory per window.

## 9. Not run, and not claimed

No real controls (Windows), no Flutter/Dart suite, no `dart analyze`, no
`pub get`, no native build, no HAP, signing, WSL, device, publisher or channel
action. No suite timing, control timing or capacity figure exists. The only
execution in this batch was the two synthetic verifiers with doubles, whose logs
are in §1. No PASS, no capacity and no grant is asserted for any real window.

## 10. R3 status in the existing independent review — explicitly reported

Requested check: correct the stale R3 wording in
`generator-trace-disable-independent-review-20261026.md` **only if still stale**.
It is **not stale, so it was not edited.** R3 already records the current spec:
`native-python-runtime.md` at the 2026-10-26 07:16 revision (15061 bytes, SHA256
`c4b0fc2aae05cf5eb97a7ddc3577c5da42bf2573ebf679a3e560b2d2c350ec2f`), which carries
the `(global || code_state->frame)` guard, the resumed-generator rationale, the
executing-frame boundary and the two required regressions. The stale `:150-153`
citation no longer appears. No file other than the four fixtures, the two logs and
this note was written by me.