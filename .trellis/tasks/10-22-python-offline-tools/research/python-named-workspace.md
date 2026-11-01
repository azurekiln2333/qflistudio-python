# Python named workspace regression

Date: 2026-10-24. Owner: `/root/python_debugger_adapter`.

## Scope and ownership

This batch owns only `test/python_named_workspace_test.dart` and this research
note. It does not modify the Python product profile, package dependencies,
runtime, shared-core code, or another worker's tests. The parent coordinator
owns execution scheduling and release evidence publication.

The UI fixture follows the already published Java regression in
`../qfli_java/test/java_named_workspace_test.dart`, particularly its real
`QfliApp` mount, retained editor promotion wait, queued persistence drain, and
store recreation. Java's prior result is a fixture reference, not Python test
evidence.

## Authored coverage

The first test uses the unchanged `pythonProfile` with actual `QfliApp`,
`EditorPage`, `FileExplorer`, `ProjectStore`, `ProjectHistory`, and the singleton
`WorkspaceStore`:

1. Open a real local Python project from Home and use the actual workspace
   toolbar/dialog to name and save two real project roots.
2. Assert the workspace metadata file exists, membership is ordered, and the
   retained `EditorPage` has received the saved workspace identity.
3. Expand a nested directory under each root, open same-name README files from
   both roots, make both buffers dirty, and hide/show the explorer.
4. Assert the same editor object, both unsaved buffers, both dirty flags, and
   both directory expansions survive without writing source bytes.
5. Restore the in-memory texts and set distinct actual editor cursors, then
   unmount and await the real ordered persistence operations.
6. Assert saved document owners, active file and per-root expansions, unchanged
   independent project history, and unchanged source files.
7. Force-reload workspace metadata, dispose/recreate the actual application
   stores, and reopen the named workspace through Home's workspace tab.
8. Assert a new editor object restores both owner names/paths, Python project
   types, file contents, active owner, cursor positions, and tree expansions.
9. Assert the actual product key remains `pyflow`, the product remains offline,
   the saved-workspace capability is the real profile value, and Home exposes
   no cloud project/community entry or language filter chips.

The second test saves and resolves another actual two-root workspace whose
projects both contain `main.py`. It uses the real profile analyzer and real
native FFI transport, with a recording delegate that forwards every request
unchanged and retains each real provider future for cleanup:

- A malformed unsaved first-root buffer produces no diagnostics while the
  saved second-root buffer is active. The request contains only the second
  root's document.
- Making the second-root buffer malformed produces its own real MicroPython
  `SyntaxError` and full-line range.
- Switching to the first root produces only that root's diagnostic, with the
  expected Unicode/CRLF line location and first-root document snapshot.
- Both buffers remain dirty and both saved sources remain byte-identical.

## Test boundary

Only the operating system storage lookup channel is supplied with a temporary
directory; the test asserts `AppPaths.storageDirectory()` resolves there before
mounting. This avoids adding `path_provider_platform_interface` as a new direct
dependency. Cursor mutation uses the existing selection's typed `copyWith`,
without importing the transitive editor package or suppressing lints.

No workspace capability is overridden. No native Python method-channel handler,
runtime stub, analyzer result stub, network response, or synthetic product
profile is installed. The UI uses README buffers so workspace lifecycle checks
are independent of native analysis; the separate diagnostics case requires a
working real native library. These host regressions do not establish installed
OHOS behavior or replace the separate offline platform/network-policy checks.

## Validation status

**UNRUN**: formatter, analyzer, focused tests, complete tests, builds, and device
commands have not been executed for this batch. The parent explicitly reserved
all Dart/Flutter/compiler/build/device processes for a NEW named execution
window. Source was reviewed against the current shared-core APIs and the proven
peer fixture; that review is not a passing test result.

Commands for the parent to run in its next granted host window, from
`D:/MyNewProjects/qfli_python`:

```text
dart format test/python_named_workspace_test.dart
flutter test --no-pub test/python_named_workspace_test.dart
flutter test --no-pub
flutter analyze --no-pub
```

The diagnostic case must run against the current real host native payload. A
missing/busy/failed native analyzer is expected to fail the `checked` assertions,
not silently skip or report a clean result.
