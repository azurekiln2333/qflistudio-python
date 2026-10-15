# Design

## Boundaries and Ownership

PythonProgramRunner supplies ProgramRunResult to RunnerService. EditorPage resolves either the project entry or active-file override, saves editor buffers, invokes the runner, and hands the result to TerminalPane. TerminalPane owns transcript continuity, lifecycle status and prompts.

The Java workspace already coordinates shared core changes. The Python pi worker owns lib/python_runner.dart and its focused tests. It must not revert others' work, modify shared core without coordination, or change native runtime contracts.

## Presentation Contract

All Python execution outcomes should identify the invoked file with a concise command-style title, for example python main.py or python "src/main 2.py". Prefer a normalized project-relative path for in-project files. The label is display data only and never becomes shell input.

Use one title formatter across legacy and controlled execution and preparation failures. Remove version suffixes from execution titles while retaining probe/version data required by syntax/compilation tools and capability checks.

Application-owned routine runner diagnostics can use short English wording with the existing [qfli] prefix. Preserve raw platform/native error details, output lines and real exit status. Do not strip words from stdout/stderr to achieve cosmetic cleanup.

## Existing Shared Behavior to Verify

- TerminalPane appends invocation, stdout/stderr and inline prompt in one ListView.
- Successful completion adds no exit-zero sentence.
- Nonzero exit and not-started states remain visible.
- EditorPage tap routes to the project's configured/default entry; onLongPress routes to the active runnable file through the same saving/run path.
- Gesture races do not double-run, and preparation/active execution disable conflicting actions.
- Retaining the terminal across editor panel changes preserves transcript history.

## Compatibility

Preserve automatic/FFI/method-channel transport selection, capability probes, cancellation handles, source/.mpy support, finite input.txt behavior, and not-run exit code. Native output remains buffered until completion; this task changes its presentation rather than its delivery guarantees.

## Validation

Exercise legacy and controlled channel paths, unavailable-backend failures, nested/spaced filenames, untouched output and real nonzero/cancellation status. Reuse core widget tests for continuous layout and distinct tap/hold behavior. Run the Python suite/analyzer; run or review the shared tests after coordination to avoid concurrent Flutter locks.

## Rollback

Keep changes scoped to Python presentation/test files. Revert only task-owned hunks if necessary. Do not restore whole shared-core or Java files because they contain unrelated active work.
