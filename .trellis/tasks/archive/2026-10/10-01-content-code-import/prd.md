# Tutorial and Example Code Import

## Goal

Keep tutorial and example catalogs simple using Material Design 3. Show code
only after opening an item, then allow importing the displayed code into the
editor or a real project with a custom filename and automatic project opening.

## Requirements

- Catalog rows contain titles and summaries, without code previews.
- Lesson and example details expose code, copy, import to editor, and import to
  project actions.
- Imports accept a custom filename. Project imports support a new local
  project or a selected existing local project.
- Successful imports open the project and select the imported file.
- Edited example code is the source for copy and import; saved edits persist.
- Cancellation, invalid names, replacement confirmation, and I/O errors have
  coherent states and preserve existing files.
- Mobile and desktop layouts follow the existing MD3 theme.

## Constraints

- Preserve existing work in the shared core repository.
- Shared UI and project services remain in qfli_studio_core.
- Verify on Android only. Do not run HarmonyOS devices or emulators.
- Keep unrelated native runtime and agreement changes outside this task.

## Acceptance

- Shared content/import tests and analyzer pass.
- Python app tests and analyzer pass.
- A freshly built APK is installed on an Android emulator; use an isolated
  instance when another session owns emulator-5556.
- Tutorial and example catalogs/details are visually checked.
- Custom-name imports to the editor, a new project, and an existing project
  write real files and open them in the editor.
- Imported Python code runs successfully using the native Android runtime.
