# QFLI Python terminal presentation and run gestures

## Goal

Give the Python edition a continuous professional editor terminal and predictable run gestures, using the user's right-pane pi worker under Codex coordination.

## Confirmed Background

> **Status/ownership updated at completion (2026-10-15).** The bullets below are the
> original planning record. Where they name panes or status, the current values are:
> the Python-owned gap (the title contract) is complete; the remaining gate is device
> interaction owned by `wA:p8`, plus coordinator build/commit and root review/archive.
> The assigned worker this round is `wA:p5` (Python runner/terminal/native);
> `wA:p2` (former `pi-python-terminal` pane) is historical. The shared-core
> terminal/editor owner is the Java workspace coordinator (`wE:p2` is historical);
> `wA:p8` verified compatibility against core `8731df8`. See `completion.md`.

- The user approved creating this task on 2026-10-09; it entered planning then and its
  Python-owned scope is complete as of 2026-10-15 (`completion.md`).
- Python and Java both depend on the adjacent qfli_studio_core package (pubspec.yaml:13 and ../qfli_java/pubspec.yaml:12).
- The shared core has pre-existing uncommitted terminal/run work, including TerminalPane's inline prompt and EditorPage's run-current-file gesture (../qfli_studio_core/lib/editor/terminal_pane.dart:877; ../qfli_studio_core/lib/editor/editor_page.dart:1056). The Java coordinator explicitly owns those four core product/test files and has reported 22 passing shared widget tests, scoped analysis/format checks, and five visually reviewed render groups. Python must report shared defects to wE:p2 rather than edit those files.
- Python **used to** construct titles such as Chinese Run plus a MicroPython/version
  suffix (previously lib/python_runner.dart:286 and :398), with the runner tests then
  expecting them (previously test/python_app_test.dart:228). **No longer true:** titles
  are now `python <project-relative path>` on every path, and the tests assert that
  contract. The real version is exposed via the public `runtimeInfo()` instead.
- Python native output is buffered until execution completes. Interactive native stdin is not supported by the existing backend contract.

## Requirements

| ID | Required behavior |
| --- | --- |
| R1 | Inspect the Java/shared-core work and reuse its terminal and gesture implementation; preserve unrelated uncommitted work. |
| R2 | Show invocation, output and the next prompt in one continuous scrolling transcript, with no detached input strip or repeated run cards. |
| R3 | Use concise command-style Python run titles, such as python main.py, with the actual selected project-relative path. Remove application-generated success/exit-zero prose and runtime/version labels from the editor transcript; use concise English for Python-owned operational diagnostics. |
| R4 | A normal Run press executes the configured/default project entry regardless of which file is open. A long press executes the active runnable file exactly once after saving pending edits. |
| R5 | Preserve real stdout/stderr, native diagnostic detail, actual exit codes, cancellation and source/bytecode execution. User output that contains Chinese, JDK or version strings must not be filtered. |

## Acceptance Criteria

- AC1 (R1): Report which requested behaviors already exist in the shared core and identify any remaining Python-specific gap.
- AC2 (R2, R3): Repeated Python runs append to one transcript, successful completion returns to a nearby inline prompt, and no application-generated success/exit-zero banner or runtime suffix appears.
- AC3 (R3): Both controlled and legacy native transports display the same concise title; spaces and nested entry paths remain identifiable; source and .mpy execution retain their routing.
- AC4 (R4): With main2.py open, tap executes main.py (or the configured entry); hold executes main2.py once, using saved current contents.
- AC5 (R5): Original stdout/stderr and diagnostic detail remain intact; failed launch, nonzero completion and cancellation remain observable.
- AC6: Python tests/analyze and the relevant existing core terminal/gesture tests pass; any unavailable device evidence is reported.

## Scope Boundaries

This task owns Python runner presentation and focused Python regression coverage, plus compatibility verification of the shared core. Shared terminal/editor ownership is coordinated with the Java workspace. Existing navigation, native VM/FFI/JNI/NAPI implementation, Python tools-page redesign, Java runtime changes and unrelated working changes are outside this task.

## Key Decisions

- Use the existing native runtime and run routing.
- Use a command-like title only as presentation; never build or execute a new shell command from it.
- Keep actual error detail and failure status; suppress only application-generated successful completion chatter.
- Assigned worker this round: `wA:p5` (Python runner/terminal/native). `pi-python-terminal` in the former `wA:p2` pane was the 2026-10-09 planning assignee. The coordinator serializes commits and reviews; the shared-core terminal/editor owner is the Java workspace coordinator.


