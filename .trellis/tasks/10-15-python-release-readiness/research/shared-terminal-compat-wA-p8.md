# wA:p8 — shared-core terminal / editor compatibility audit (read-only)

Task: `.trellis/tasks/10-15-python-release-readiness`.
Scope: **read-only** verification of the shared `qfli_studio_core` standalone
terminal and editor terminal, focused on whether the Python profile's
`toolsPageBuilder` affects the shared standalone terminal, and whether the run
entry points / long-press-current-file / continuous transcript / offline tool
commands actually work.
Shared core was NOT modified. No commit. Coordinator serializes commits.

## Shared core identity this round

| Item | Value |
|---|---|
| Core HEAD at round start | `ad17f35` |
| Core HEAD after coordinator commit | `8731df8` (`git rev-parse HEAD`) |
| Concurrent dirty files (other workers, untouched) | first `lib/editor/editor_page.dart` + `lib/pages/profile_page.dart`; later `lib/editor/retained_editor_host.dart` + new `test/retained_editor_animation_test.dart` |
| New task dir (other worker) | `.trellis/tasks/10-15-offline-editor-gates/` |
| App repo | unchanged; only this task's `research/` added by me |

Core is being edited live by other workspaces; I did not revert or touch any of
it.

## Tests actually executed (core terminal/editor suites only)

| Suite | Result |
|---|---|
| `test/terminal_pane_test.dart` | **25/25** |
| `test/editor_run_test.dart` | **16/16** |
| `test/terminal_manager_delegate_test.dart` | **1/1** |
| `test/sandbox_terminal_test.dart` | **25/25** |
| combined 4 terminal/editor suites | **67/67** |
| `test/terminal_compact_focus_test.dart`, `terminal_input_behavior_test.dart`, `terminal_tab_bar_test.dart`, `editor_terminal_touch_test.dart`, `offline_tools_test.dart` | **60/60** |

All green on the current working tree.

## Findings

### F1 (transient, resolved) — shared `editor_page.dart` compile break

During the round, `test/editor_run_test.dart` failed to compile:

```
lib/editor/editor_page.dart:1605:37: Error: Expected 'else' or comma.
    if (widget.project.isCloud &&
```

Cause: a **concurrent worker's uncommitted** offline-gating edit (task
`10-15-offline-editor-gates`) had removed the comma after the `git`
`PopupMenuItem` and left a malformed `}                                    }`.
This was **not Python-owned** and not mine; I did not fix it. The owning worker
corrected it within the round, after which `editor_run_test.dart` passed 16/16
(live evidence of the fix in `lib/editor/editor_page.dart:1591-1620`).
Status: **closed** — no action needed, recorded for traceability.

### F2 — `toolsPageBuilder` does NOT affect the shared standalone terminal

Evidence (source, read-only):

- Python profile sets `toolsPageBuilder: buildPythonToolsPage` but **not**
  `toolsTabBuilder` (`lib/main.dart:31`; `rg toolsTabBuilder lib/` in the app is
  empty).
- `FunctionsTab` (`lib/pages/quick_tools_page.dart:30-48`) falls back to
  `ToolsGrid(onOpenTerminal: ...)` when `toolsTabBuilder == null`. `ToolsGrid`
  renders the 本地终端 card whenever `onOpenTerminal != null`
  (`lib/pages/tools_grid.dart:105-114`).
- `home_page.dart:228-236` supplies `onOpenTerminal` (pushes
  `TerminaxTerminalPage`) unconditionally. The Python `toolsPageBuilder` only
  affects `ContentToolsPage` (`quick_tools_page.dart:94-96`), i.e. the separate
  "专用/功能" page reached from the grid — not the terminal route.

Conclusion: the Python tools page is a **sibling** of the shared standalone
terminal, not a replacement. The standalone terminal remains reachable.

### F3 — both terminal surfaces share one backend/delegate

`terminal_manager_delegate_test.dart` proves the app-level
`TerminaxTerminalPage` wires `StudioProfile.terminalCommandDelegate` into
`TerminalManager` (standalone terminal). `terminal_pane_test.dart` proves the
editor pane uses the same delegate path (Stop control cancels a delegate
command). The Python delegate (`lib/main.dart:pythonTerminalDelegate`) routes
`python|python3|micropython <script>` through the *same* `PythonProgramRunner`
as the Run button — no second backend.

### F4 — run entry, long-press-current-file, transcript, offline commands

- Run button: tap → `_runProject` (configured entry), long-press →
  `_runActiveFile` (current file) — `editor_page.dart:1345-1357`;
  `_runActiveFile` checks `supportedFileExtensions` (Python `.py/.mpy`) and
  project containment before delegating (`editor_page.dart:1160-1192`).
  Covered by `editor_run_test.dart` 16/16.
- Continuous transcript: covered by `terminal_pane_test.dart` (partial output
  line integrity, 500-line bound, scroll retention, session isolation) 25/25.
- Offline tool commands: `offline_tools_test.dart` 33/33 (file-command/common
  tool behavior); sandbox `sandbox_terminal_test.dart` 25/25.

## Blocked / not-run (per coordinator steering)

- The app's `test/offline_regression_test.dart` and full-app `flutter test` were
  **not run** by me after the coordinator's steering: p6 is fixing a Windows
  default-FFI + fake-clock hang and injecting a runner/`runAsync` in that file.
  I did not run it, so I cannot report its result this round. (It imports
  `main.dart`/editor, so it was also affected by F1 while that was broken.)
- My one in-flight `flutter test test/offline_regression_test.dart` was aborted
  by the coordinator; it exited cleanly. Verified: **no qfli_python
  test/build/`flutter_tester` process of mine remains.** I did not kill any
  process (no global kill); the remaining flutter/dart processes belong to
  other workspaces (`cloudterminal`, `qfli_go`, `qfli_rust`, `qfli_dart`,
  `qfli_sql`).

## Conclusion

No shared-core defect owned by this task. The Python `toolsPageBuilder` is
compatible with the shared standalone terminal (no bypass), and the run
entry/long-press/transcript/offline-command paths all pass their core suites.
F1 was a transient concurrent-worker break, already fixed by its owner.
