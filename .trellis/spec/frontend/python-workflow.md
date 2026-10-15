# Python Workflow

## 1. Scope / Trigger

Use for `lib/main.dart`, `python_runner.dart`, `python_terminal.dart`, `python_tools_page.dart`, and
their tests. Shared navigation/editor behavior belongs to the adjacent
`qfli_studio_core` package. Read the [native contract](../backend/native-python-runtime.md)
before changing the runner or MethodChannel fields.

## 2. Signatures

```dart
Widget buildPythonToolsPage(ProjectStore store);
Future<PythonSyntaxResult> checkSyntax({
  required String projectPath, required String entryFile,
});
Future<ProgramRunResult?> run({
  required String projectPath, required String entryFile,
});
Future<PythonRuntimeInfo> runtimeInfo();
Future<bool> pythonTerminalDelegate(SandboxShellBackend backend, String command,
    {PythonProgramRunner runner, PythonRuntimeProbeSource? probeSource});
```

Register the tool through `StudioProfile.toolsPageBuilder`.
`PythonSyntaxResult` contains `success`, `error`, and `version`.
Register interpreter commands through `StudioProfile.terminalCommandDelegate`;
both the standalone terminal and editor terminal consume this same callback.

## 3. Contracts

- ProjectStore supplies real local project data. Exclude cloud projects and
  paths that no longer exist; show an empty state when none remain.
- Discover `.py` files recursively with `followLinks: false`; labels are
  relative to the project, while runner arguments use actual absolute paths.
- File lists and operation results are page state. Listen to ProjectStore
  and remove the listener on disposal. Scan generations prevent older async
  results from overwriting a newer selection.
- Disable commands while scanning or executing. Keep output and exit status
  visible after completion; diagnostics must remain distinguishable from
  Python stdout in the editor terminal (`[qfli] ` prefix).
- Syntax checks use `checkSyntax`, and execution uses `run`; both first probe
  `available` and pass source, stdin, heap size and real paths.
- Terminal aliases `python`, `python3` and `micropython` use the same runner.
  Simple script commands support `.py`/`.mpy`; interpreter options, extra script
  arguments and interactive REPL are explicitly refused when unsupported.
  Shell pipelines/redirection fall back to the shared sandbox parser.
- Resolve script paths through the sandbox. Prefer an owning `.qfli/project.json`
  inside the sandbox for project-local input/imports; an unmarked terminal run
  uses its working directory. Never adopt an ancestor project outside the sandbox.
- `--version`/`-V` read `runtimeInfo()` from the real native probe: success writes
  the actual MicroPython version to stdout with exit 0; unavailable/failed probes
  write diagnostics to stderr with the not-run status. Never invent a version.
- Run titles are `python <project-relative path>` for source/bytecode and all
  transports; quote display paths with spaces. Preserve program output and real
  status; runtime version does not belong in the repeated transcript title.
- Shared About/settings surfaces must identify `StudioProfile.current.appTitle`.
  Shared offline descriptions follow `offlineOnly`, matching the navigation
  policy. Keep language editions' identity in the shared profile extension;
  avoid an app-local duplicate About dialog. Core `settings_about_test.dart`
  covers offline editions, default identity and explicit online overrides.

## 4. Validation & Error Matrix

| Condition | UI behavior |
| --- | --- |
| No local projects | Empty state, no executable selection |
| No Python files | Empty file list, disabled actions |
| Scan/read failure | Display filesystem diagnostic |
| Compile succeeds | Show success status, no executed stdout |
| Compile fails | Show failure and native diagnostic |
| Run finishes | Show stdout/stderr and actual exit code |
| Missing backend | Show actionable module-unavailable message |
| Wrong source extension / missing entry | Reject syntax check / run returns null |

## 5. Good / Base / Bad Cases

- Good: select a real project file and display its native compilation error.
- Base: a single `src/main.py` is discovered and can be checked and run.
- Bad: switching projects must not submit a file retained from the old project.
  An old directory scan must not restore stale files or leave loading active.

## 6. Tests Required

- Runner tests assert `checkSyntax` uses the correct channel method, source,
  project root and entry path, and returns native errors.
- Widget tests discover files from a real temporary project and exercise
  syntax checking and running at 360x800 and 1200x800 without layout exceptions.
- Real filesystem scans must run with `tester.runAsync`; pump the scheduled
  loading frame before waiting for it to disappear. Use bounded real-time
  polling instead of waiting for I/O under the test's fake clock.
- Run `flutter test` and `flutter analyze`; channel mocks do not establish
  native runtime correctness.
- Terminal channel tests inject a method-channel runner. On Windows the default
  automatic transport selects real FFI, so a MethodChannel mock alone cannot
  control it. Use real async `test()` for backend streams, and `runAsync` for
  actual filesystem work inside widget tests; bounded waits must fail promptly.
- Verify both success/error output streams and `lastExitCode`, nested marked and
  unmarked projects, aliases, rejected arguments, unsupported shell syntax and
  missing backend. Shared terminal/gesture suites verify host UI integration.

## 7. Wrong vs Correct

```dart
// Wrong: ignores project-relative I/O and traceback identity.
await channel.invokeMethod('checkSyntax', {'source': source});
// Correct: forwards the selected file's actual context.
await channel.invokeMethod('checkSyntax', {
  'source': source, 'stdin': '', 'heapKb': heapKb,
  'projectPath': projectPath, 'entryFile': entryFile,
});
```

Use the existing tools-page extension and real empty states. Keep normal
screens free of build instructions and unfinished-runtime messages.
