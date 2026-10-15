# Flutter Component Guidelines

## 1. Scope / Trigger

Use for app-owned widgets, especially Python tools. Shared editor/navigation
components stay in core. The application uses Flutter Material widgets.

## 2. Signatures

```dart
Widget buildPythonToolsPage(ProjectStore store) => PythonToolsPage(store: store);
class PythonToolsPage extends StatefulWidget {
  const PythonToolsPage({
    super.key,
    required this.store,
    this.runner = const PythonProgramRunner(),
  });
  final ProjectStore store;
  final PythonProgramRunner runner;
}
```

The builder plugs into `StudioProfile.toolsPageBuilder` in `lib/main.dart`.

## 3. Contracts

- Use immutable typed constructor fields and inject the real store/runner.
  Keep operation state in `State`; do not create stores during `build`.
- Use theme colorScheme/textTheme and Material controls. Tools use scrolling
  `ListView`, max-width 760, expanded dropdowns, `Wrap` actions and selectable
  monospace output for phone and desktop.
- Distinguish empty-project, empty-file, loading, status and output states.
  Disable controls during scans/operations or when no eligible file exists.
- Display relative paths and submit absolute paths. Keep dropdown `ValueKey`
  identity aligned with project/file initial-value changes.
- Label dropdowns/actions; refresh, compile and stop icons have tooltips.
  Preserve copyable output and visible exit status.
- Keep routine screens useful to learners; developer build commands and runtime
  implementation progress belong in development records.

## 4. Validation & Error Matrix

| State | UI |
| --- | --- |
| No existing local project | Empty state, no executable selection |
| Scan running | Progress and disabled file/actions |
| `.mpy` selected | Run available; source-only operations disabled |
| Operation fails | Visible status and diagnostic |
| Operation finishes | Output and real exit remain visible |

## 5. Good / Base / Bad Cases

- Good: long nested names fit a narrow page without overflowing actions.
- Base: select and run an actual local project file.
- Bad: fixed-width actions overflow a phone or an unlabeled icon hides stop.

## 6. Tests Required

Use [tools tests](../../../test/python_tools_page_test.dart) for real temporary
projects and 360x800 / 1200x800 layouts. Check disabled controls, visible status
and `tester.takeException()`. Real scans need `runAsync`; pump the scheduled
loading frame before interpreting completion. Run full analyzer/tests afterward.

## 7. Wrong vs Correct

Wrong: invoke MethodChannel from a widget and recreate result decoding.
Correct: call the injected runner and render results, as `_execute` and
`_compile` in [PythonToolsPage](../../../lib/python_tools_page.dart) do.
