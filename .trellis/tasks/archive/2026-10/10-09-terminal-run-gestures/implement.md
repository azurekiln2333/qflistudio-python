# Implementation Plan

## Ordered Work

- [x] Read Trellis context, relevant frontend/backend specs and existing repository state.
- [x] Create the task after user consent.
- [x] Start pi-python-terminal in the user's right Herdr pane and dispatch read-only research.
- [x] Identify the adjacent shared-core/Java dependencies and pre-existing terminal/gesture changes.
- [x] Record pi's research findings and coordinate shared-core ownership with the Java workspace.
- [x] Current 2026-10-15 user request authorizes all remaining implementation,
  tests, commits and Trellis completion; no repeat approval is required.
- [x] Activate the task for completion bookkeeping under that authorization.
- [x] Dispatch Pi implementation with the PRD/design and manifest context; own only Python runner and focused tests.
- [x] Standardize Python invocation titles and application-owned diagnostics without altering actual output or native behavior.
- [x] Check the existing shared terminal and run gestures; report any shared defect to the owning Java/core coordinator.
- [x] Run focused checks, then required full Python checks: final app 91/91,
  analyzer clean; relevant core terminal/editor suites 25/25 and 16/16.
- [x] Review Pi's final diff and verification evidence; update the Python workflow spec.
- [x] Commit product work in `77f46d5` and `7286cd9`; finish task records and archive.

Final AC mapping is in `completion.md`. Unavailable device observations are
reported under AC6; the latest OHOS hardware gate belongs to the separate
native-runtime/release-readiness tasks and is not silently closed here.

## Validation Commands

Run in qfli_python:
- flutter test test/python_app_test.dart test/python_lifecycle_test.dart
- flutter test
- flutter analyze

Coordinate before running in qfli_studio_core:
- flutter test test/terminal_pane_test.dart test/editor_run_test.dart

If native tests are skipped because a real library is missing, record that explicitly. Do not claim a device or packaged-app test from mocked channel evidence.

## Review Gates

- Never interpret displayed command labels as executable shell commands.
- All runner outcome paths use the same title contract.
- Exact stdout/stderr is preserved.
- Source/bytecode entry path and run/cancel channel payloads are unchanged.
- Long press never also runs the default entry.
- User's existing Python/HarmonyOS, Java and shared-core modifications remain intact.

## Files at Risk

Shared core editor/terminal files are actively modified by another session. Do not edit or commit them in this task. Local primary scope: lib/python_runner.dart, test/python_app_test.dart, test/python_lifecycle_test.dart and narrowly justified integration coverage.
