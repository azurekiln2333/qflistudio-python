# wA:p8 — final read-only review: python_terminal.dart + offline_regression_test.dart

Scope: read-only cross-layer review of `lib/python_terminal.dart` (new, p6/p5
owned) and `test/offline_regression_test.dart` (final, p6 owned).
I changed neither file. No app/core edit, no commit.

## Files reviewed (untracked / newest)

| File | Last write |
|---|---|
| `lib/python_terminal.dart` | 2026-10-15 18:59 |
| `test/offline_regression_test.dart` | 2026-10-15 19:03 |

## Contract verification (matches the required semantics)

The required contract is: **success `--version` → stdout, exit 0;
unavailable → stderr, exit 127; production reads the real VM version via
`runtimeInfo`.**

1. **success → stdout / exit 0.** `_versionResult` returns `success: true` only
   when `probe.available && probe.version.isNotEmpty`, producing
   `MicroPython <version>`. `_report(stdout: version.lines, stderr: [])`
   routes stdout, and derives exit code `stderr.isEmpty ? 0 : 127` → **0**. ✔
2. **unavailable / probe-error / empty-version → stderr / exit 127.** Each maps
   to `success: false`, so `_report(stdout: [], stderr: version.lines)` →
   **127**. The assert `stdout.isEmpty || stderr.isEmpty` guarantees a
   diagnostic is never on both channels. ✔
3. **exit status is channel-derived, not hard-coded per branch**, so a failure
   can never render as success. `SandboxShellBackend.runStreams`
   (`sandbox_shell_backend.dart:323-345`) is the single writer; it sets
   `lastExitCode = code` only when `!cancelRequested`, and the session renders
   the shared "(运行结束, 退出码 N)". Cross-layer consistent. ✔
4. **Production reads the real VM version.** `main.dart:44-45` registers
   `_pythonTerminalDelegate` with no overrides → `pythonTerminalDelegate`
   defaults `probeSource` to `runner.runtimeInfo` → `PythonProgramRunner.runtimeInfo`
   → `_probeNative()` → native `available` channel; version is the upstream
   MicroPython string, not a constant. No second probe implementation
   (`python_runner.dart:429-437`). ✔
5. **No fabricated version.** Empty version is an explicit failure; the
   `Python 3` prefix is never invented. ✔

## Test coverage (final file) — verified by running it

Owner test run (single run, bounded 420s job; finished in ~1s):

```
flutter test test/offline_regression_test.dart
→ +24: All tests passed!   (24/24)
```

It asserts the **channel** (`stdout` vs `stderr`) and `backend.lastExitCode`
(`kProgramNotRunExitCode`), not just text: `--version` success (stdout/0),
unavailable (stderr/127), empty-version failure, `-V` parity, missing
file/escape/non-`.py` (stderr/127), and default-`runtimeInfo` real-probe.

Hang fix confirmed effective: the runner is injected as
`PythonProgramRunner(transport: PythonNativeTransport.methodChannel)` so the
Windows FFI path is never taken, `backend()` wires the delegate with that
runner, and widget tests wrap real file IO in `tester.runAsync` with bounded
polling. This is exactly the fake-clock/default-FFI hang class the coordinator
flagged — no hang reproduced.

## Cross-layer issues found

### I1 (low severity, note for coordinator) — project-root parity edge for unmarked projects
`projectRootForScript` (`python_terminal.dart`) resolves the project root by
walking to the nearest `.qfli/project.json`, falling back to the **script's own
directory**. The Run button instead passes `widget.project.path` (the registered
root). For a project created through the store this is identical, because
`ProjectStore.createProject` always writes `.qfli/project.json`
(`project_store.dart:346`, `strict: true`). But `ProjectStore.addExisting`
(`project_store.dart:392` region) registers a folder **without** rewriting a
missing marker. In that case a nested `src/main.py` run from the terminal would
use `src/` as the project root and miss a root-level `input.txt`, whereas the Run
button would find it.
- Impact: only unmarked projects + nested entry; root-level `main.py` is
  unaffected. Not a blocker, not Python-owned regression (the fallback is honest
  and sandbox-confined).
- The existing test pins only the **marked** case; the unmarked-nested case is
  currently untested.
- Recommendation (p6-owned): either document the marker requirement, or have
  `addExisting`/the delegate also consider the store's registered path. No action
  taken by me.

### I2 (informational) — `_report` returns `true` even for failures
`_report(...).then((_) => true)` always returns `true` so the delegate claims
the command even when it failed. This is correct (the sandbox must not fall
through to its own "unsupported" message for a Python diagnostic), and the
nonzero exit via `lastExitCode` conveys the failure. Consistent. ✔

## Blockers
None. No fabricate/placeholder, no second backend, no cross-layer contradiction
in the required contract.

## Process hygiene
Owner test was run once in a bounded background job (completed, none of my
qfli_python `flutter_tester`/dart processes remain). I did not run the full app
suite, did not modify p6 code, and did not kill any process globally.
