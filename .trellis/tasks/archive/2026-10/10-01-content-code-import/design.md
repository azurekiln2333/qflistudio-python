# Design

## Ownership

The adjacent qfli_studio_core package already contains the requested UI and
import implementation. Verify and repair concrete gaps in those files without
duplicating the shared workflow in the Python app.

## Data Flow

HomePage supplies its ProjectStore, AuthStore, SettingsStore, and owned
ExampleCodeStore to the content catalogs. Catalog items push detail routes.
CodeSnippet captures the displayed code and shows an MD3 import dialog.

Editor import creates and registers a snippet project. New-project import uses
ProjectStore.createProjectFromExample with a customized entry filename.
Existing-project import uses CodeImportService and confirms replacement before
writing. Import results include the real project and absolute file path.
EditorPage.initialOpenPath selects that file after navigation.

## Storage and Failure Contracts

- Validate filenames before any write and prevent project path traversal.
- Preserve the existing project's entry configuration for additional files.
- Report write/registration failures inside the dialog.
- Confirm replacement and preserve the existing file through backup.
- Prevent duplicate submissions while importing and avoid notifications after
  disposal.

## Compatibility

Use existing template, project config, editor, localization, and MD3 theme
APIs. No new runtime channel or platform-specific import interface is needed.
