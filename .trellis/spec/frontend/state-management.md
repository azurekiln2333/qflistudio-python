# State Management

## 1. Scope / Trigger

Use for profile, selection, loading, operation or bootstrap state. This app uses
shared ChangeNotifier stores, page-local State and a readiness ValueNotifier;
it does not introduce Redux, Riverpod or Bloc.

## 2. State Ownership

| Owner | State |
| --- | --- |
| `StudioProfile.current` | Process-wide product/language configuration |
| Shared `ProjectStore` | Registered identity, paths and list notifications |
| Shared `SettingsStore` / `AuthStore` | Settings and shared bootstrap integration |
| `_PythonToolsPageState` | Selection, scan generation, working/status/output/cancel |
| `ValueNotifier<bool> ready` | Bootstrap-to-home readiness |
| Native worker/session | One execution's VM lifetime and cancellation token |

## 3. Contracts

- Install `pythonProfile` before startup. Its offline policy/extension points
  configure the shared app. Tab visibility is not a native capability probe;
  avoid independent cached capability flags.
- Create stores once in `main` and pass them through `QfliApp`/profile builders.
  Consume current store data instead of a second persistent project list.
- Derive `_projects` by excluding cloud entries/nonexistent directories. Derive
  active project/file from current lists; removal/project switching must not
  retain an executable stale selection.
- Separate discovery and operation state. `_loadingFiles` protects incomplete
  scans; `_working` prevents duplicate/conflicting operations.
- Clear prior output for a new operation/project, then retain completed status
  and output. Stop request is not completion until native exit arrives.
- Server caches are not app-owned state in this offline product. Preserve shared
  gating instead of adding local login/cloud state.

## 4. Validation & Error Matrix

| Transition | State |
| --- | --- |
| Project removed / list empty | No stale executable selection; loading clears |
| Project changed | File selection and prior output reset |
| Scan superseded | New generation retains ownership |
| Run starts / finishes | Commands disabled / working and cancel released |
| Cancel requested | Stop status visible until actual completion |

## 5. Good / Base / Bad Cases

- Good: store notification refreshes tools without reviving removed files.
- Base: a registered local project and entry become selectable.
- Bad: use `runtimeStatus` as proof a device library loaded, or share unrelated
  projects' tool output through a global singleton.

## 6. Tests Required

Exercise empty states, selection, compile/run/stop and layouts with real temporary
projects in `test/python_tools_page_test.dart`. Profile/runner contracts are in
`test/python_app_test.dart`; readiness/failure in `test/startup_test.dart`.
Pump frames to apply async results before asserting visible state.

## 7. Wrong vs Correct

Wrong: snapshot `store.projects` only during initialization and ignore changes.
Correct: derive current choices and pair the store listener with disposal, as
[PythonToolsPage](../../../lib/python_tools_page.dart) does. Persistence stays
with [shared stores](../backend/database-guidelines.md).
