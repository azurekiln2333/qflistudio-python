# Research and ownership record

## pi research

Worker: pi-python-terminal, Herdr wA:p2, 2026-10-09. Two read-only research rounds verified:

- Python runner owns all execution titles, and shared TerminalPane only prepends its project prompt; it does not add a python command prefix.
- Shared TerminalPane already hides exit-zero chatter and uses an inline prompt in the transcript.
- Shared EditorPage already supports tap for the project entry and hold for the active file.
- Python profile lives in lib/main.dart and already prefers main.py/src/main.py and supports source/bytecode entries.
- Python runner titles still include Chinese operation prose and MicroPython labels in controlled and legacy paths; not-wired/failure paths use Chinese run titles too.
- Existing test/python_app_test.dart assertions deliberately expect the old titles. Controlled and .mpy titles need explicit regression coverage when changing them.
- Desired title in the proposed plan: python followed by a readable project-relative file path, quoted for display when required. It is never an executable shell command.

## Shared-core coordination

Java main coordinator wE:p2 explicitly confirmed ownership of:

- ../qfli_studio_core/lib/editor/terminal_pane.dart
- ../qfli_studio_core/lib/editor/editor_page.dart
- ../qfli_studio_core/test/editor_run_test.dart
- ../qfli_studio_core/test/terminal_pane_test.dart

The Java coordinator reports 22 passing shared widget tests, four-file scoped analysis and format checks, five visually inspected real render groups, and 20 passing Java tests. These are peer-reported checks, not Python-local execution evidence. Product code is stable; the peer is reviewing commit scope. Existing unrelated dirty changes remain.

Our scope is Python runner/tests and Python compatibility checks. Do not edit or commit the peer-owned core files; send any concrete defect evidence back to wE:p2 for correction. Do not format the whole repository.
