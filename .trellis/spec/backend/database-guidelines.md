# Local Persistence (No Application Database)

## 1. Scope / Trigger

Use for registries, settings, saved examples and runtime files. This wrapper
defines no database schema, ORM, SQL queries or database migrations.
The inherited filename does not require introducing a database.

## 2. Existing Interfaces

[main.dart](../../../lib/main.dart) creates shared `ProjectStore`, `AuthStore`
and `SettingsStore` instances and passes them to `QfliApp`.
`ProjectStore(storageFile: registry)` is the real-file test seam in
[tools tests](../../../test/python_tools_page_test.dart).

Shared implementation paths are
`../qfli_studio_core/lib/store/project_store.dart`,
`lib/store/settings_store.dart` and `lib/services/example_code_store.dart`.
Python program files use `native/src/qfli_py_file.c`.

## 3. Contracts

- Core owns `projects.json`, project metadata in `.qfli/project.json`, and
  `settings.json`. Let shared stores own encoding, storage resolution and writes.
- `ProjectStore` serializes writes and replaces its registry through a temporary
  file. Its revision check protects newer state from a delayed reload. Avoid
  competing writers or page-owned persistent copies.
- Tools filter current projects to existing local directories. Refreshing a
  registry must not delete project directories.
- Source and `input.txt` are project files, not registry records. Preserve actual
  root and entry paths at the native boundary.
- Curriculum refresh preserves custom records and non-Python content. Follow
  [Content Code Import](../frontend/content-code-import.md).

## 4. Validation & Error Matrix

| Condition | Existing contract |
| --- | --- |
| Missing registry | Empty project list |
| Corrupt registry at startup load | Shared store permits startup with an empty list |
| Explicit refresh/write fails | Follow shared failure reporting; do not claim success |
| Cloud record or missing directory | Excluded from Python tools |
| Native file failure | Diagnostic returned in execution result |

## 5. Good / Base / Bad Cases

- Good: load a temporary registry and discover its actual project files.
- Base: no projects gives an empty state and disabled execution.
- Bad: refreshing tutorials also clears custom examples or another language.

## 6. Checks Required

Use temporary files and shared-store APIs, as in the tools tests. Shared
persistence changes require owning core tests and app tests. Content changes
require preservation checks in the content spec. No database migration command
applies here.

## 7. Wrong vs Correct

```dart
// Wrong: a page adds a competing registry writer.
await File('projects.json').writeAsString('[]');
// Correct: inject and consume the existing store.
final store = ProjectStore(storageFile: registry);
await store.load();
```
