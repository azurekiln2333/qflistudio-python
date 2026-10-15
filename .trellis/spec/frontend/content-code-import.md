# Content Code Import

## 1. Scope / Trigger

Tutorial/example navigation and snippet import are owned by the adjacent
qfli_studio_core package. Apply this guide when changing that shared flow or
verifying a language app that consumes it through HomePage and StudioProfile.

## 2. Signatures

```dart
typedef CodeImportResult = ({Project project, String path});
CodeImportService.suggestedFileName(String type);
CodeImportService.isValidFileName(String fileName);
CodeImportService.openInEditor({example, fileName, location});
CodeImportService.importIntoProject({project, example, fileName, overwrite});
ProjectStore.createProjectFromExample({name, example, location, fileName});
EditorPage({project, auth, store, settings, initialOpenPath});
```

## 3. Contracts

- Overview rows show titles and summaries; code belongs to detail routes.
- HomePage passes the actual project/auth/settings stores and its persistent
  ExampleCodeStore into offline pages.
- CodeSnippet imports and copies controller.text when examples are edited.
- Editor imports create and register a real snippet project. New projects use
  the custom file as their configured entry and omit the unused default entry.
- Existing projects retain their entry metadata when importing another file.
- Successful navigation passes the absolute imported path to initialOpenPath.
  Restore the editor session first, then select the explicitly imported file.
- Disable duplicate submission during I/O. Failed registration cleans up the
  newly created snippet directory; errors remain in the dialog.

## 4. Validation & Error Matrix

| Condition | Required behavior |
| --- | --- |
| Invalid basename, reserved name or traversal | Reject before creating files |
| Existing file | Ask before replacement; cancellation preserves content |
| Directory or symlink target | Reject replacement |
| Backup/write failure | Preserve the old target; report failure |
| Missing/cloud project or parent outside root | Reject project import |
| Saved example store cannot load | Retain the bundled catalog and show error |
| Save failure | Preserve saved value and allow another attempt |
| Canceled import | No file creation or editor navigation |
| Disposed page/store/controller | No late listener notification or new tab |

## 5. Good / Base / Bad Cases

- Good: edit an example, import it under a custom name into an existing project,
  and select the new file even when an earlier editor session is restored.
- Base: import a lesson as a custom Python entry and run it on Android.
- Bad: importing ../escape.py must leave storage and navigation unchanged.

## 6. Tests Required

Run shared content_code_import_test.dart, content_repository_test.dart,
tutorial_test.dart and structured_content_test.dart. Run flutter analyze lib
test in the shared package, plus flutter test and flutter analyze in this app.
Record root analyzer results separately when vendored examples have unrelated
diagnostics; do not claim a clean root analyzer from a scoped command.

Verify filename, stored code, project registration/entry config and the actual
active editor tab. Cover save persistence, overwrite/cancel, failure cleanup,
and 320/1280px layouts with 2x text. Use real filesystem tests with runAsync.

In this Flutter fork find.byTooltip can find RawTooltip rather than IconButton.
Select buttons by widget type and tooltip property when reading onPressed.
After ensureVisible, pump scrolling/layout before tapping. Dismiss an existing
SnackBar if it covers the action; assert hitTestable and enabled state.

Use an independent Android AVD when another session is manipulating the shared
emulator. Keep its config/data and evidence under ignored build directories.

## 7. Python curriculum maintenance contract

Bundled Python tutorial/example content is authored in a Dart module and emitted
into the aggregate assets; maintain it through this pipeline, not by hand-editing
the large JSON.

- Source of truth: `qfli_studio_core/tool/python_content/` — `python_topic.dart`
  (model, `runtime: embedded|cpython`), `python_topics.dart` (aggregation),
  `topics_basics.dart` (001-016), `topics_containers_functions.dart` (017-040),
  `topics_modules_oop.dart` (041-060), `python_topics_advanced.dart` (061-120,
  owned by the advanced author; only imported here).
- Generate: `dart run tool/generate_python_content.dart` — load-drop-insert into
  `assets/content/{tutorials,examples}.json` (Python rows only) and regenerates
  `assets/tutorials/python.json`. Must report
  `Wrote 120 ... Preserved 1500 non-Python ...`.
- Verify (real runtime): `dart run tool/verify_python_content.dart` — executes
  every `embedded` sample against the real embedded MicroPython DLL
  (`tool/python_content/run_embedded.py`; host default
  `qfli_python/native/build/windows/qfli_py_ffi.dll`) and every `cpython` sample
  in CPython; writes `research/python-content-verification.json`. Must report
  `embedded 116/116`, `CPython 4/4`, `asset mismatch 0`.
- Invariants:
  - Exactly **120 tutorial + 120 example** Python entries, paired 1:1 by id via
    `sourceLessonId == python-tutorial-NNN-lesson`; unique ids/titles/code.
  - Exactly **116 embedded + 4 CPython** pairs (CPython-only lessons 117-120
    carry the `需要外部 CPython 环境` concept label); never count a CPython pass
    as embedded.
  - Declared `output` must match real stdout exactly (dict/set iteration order
    is hash order; `repr` of containers escapes non-ASCII; string step-slicing
    is unsupported; `json.dumps` rejects `ensure_ascii`/`indent`; embedded RNG
    differs from CPython). See `.trellis/spec/backend/native-python-runtime.md`.
  - **Never delete `ExampleCodeStore` `_custom` records.** The refresh is
    refresh-only: re-seed built-in defaults and preserve every persisted record
    (no purge by `type`/`language`). `example_code_store.dart` is unchanged.
  - Non-Python entries must stay byte-for-byte: 15 languages x 100 = 1500 in
    each aggregate asset.
- Focused tests: `flutter test test/python_content_test.dart` (integrity +
  user-data preservation) and `test/python_content_render_test.dart` (both
  offline page data sources render 120).

## 8. Wrong vs Correct

```dart
// Wrong: discards the user's edits or leaves an older tab selected.
importExample(example.code);
openProject(project);

// Correct: capture the displayed code and select the imported file.
final current = example.copyWith(code: controller.text);
final result = await CodeImportService.importIntoProject(
  project: project, example: current, fileName: fileName,
);
EditorPage(
  project: result.project, auth: auth, store: store, settings: settings,
  initialOpenPath: result.path,
);
```
