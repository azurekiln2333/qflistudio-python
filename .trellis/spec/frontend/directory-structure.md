# Frontend Directory Structure

## 1. Scope / Trigger

Use when placing Flutter UI, profile, startup or runner work. `qfli_python` is
a small language wrapper around adjacent `qfli_studio_core`; it has no web UI.

## 2. Ownership Map

| Path | Responsibility |
| --- | --- |
| `lib/main.dart` | Python profile, terminal delegate, stores and entry point |
| `lib/app_startup.dart` | Bootstrap and native first-frame/progress handoff |
| `lib/python_tools_page.dart` | Project/file tools and operation state |
| `lib/python_runner.dart` | Execution adapter and result types |
| `lib/python_ffi.dart` | Native bindings and workers, not UI |
| `test/*_test.dart` | Profile, tools, startup and native-boundary regressions |
| `assets/app_icon.png` | App-owned Flutter asset registered in pubspec |
| Platform folders | Native shells and packaging |
| `.trellis/spec/` | Coding contracts and verification guidance |

## 3. Contracts

- Keep Python setup in `pythonProfile`, installed before startup. Use
  `toolsPageBuilder`, `runner` and `terminalCommandDelegate` extension points.
- Shared editor, terminals, navigation, stores and themes live in
  `../qfli_studio_core/lib/`. Coordinate edits there instead of copying pages.
- Curriculum source/assets also live in core. Follow
  [Content Code Import](./content-code-import.md).
- Use `snake_case.dart` filenames, PascalCase public types and `_` private state
  and helpers, as in `PythonToolsPage` and `_PythonToolsPageState`.
- Keep channel/native details inside runner/FFI. Widgets consume operations and
  results instead of loading libraries or constructing native payloads.

## 4. Validation Matrix

| Intended change | Start with |
| --- | --- |
| Python capability/profile | `main.dart` and profile tests |
| Selection/output | Tools page and widget tests |
| Execution/exit/cancel | Runner and backend contracts |
| First-frame handoff | `app_startup.dart` and startup spec |
| Shared navigation/content | Core owner and shared checks |

## 5. Good / Base / Bad Cases

- Good: expose Python tools through `StudioProfile.toolsPageBuilder`.
- Base: shared `QfliApp` receives the actual application stores.
- Bad: implement another terminal to bypass shared profile behavior.

## 6. Checks Required

Read [Python Workflow](./python-workflow.md),
[Native Startup](./native-startup.md) or the content spec for the affected path.
Run `flutter analyze` and `flutter test` here; shared changes also need core
checks. Keep command cwd explicit with several language workspaces open.

## 7. Wrong vs Correct

Wrong: copy generic editor widgets into `lib/` to customize Python execution.
Correct: implement `ProgramRunner` and register it in
[pythonProfile](../../../lib/main.dart), as
[PythonProgramRunner](../../../lib/python_runner.dart) does.
