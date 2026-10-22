# Python direct tools and editor diagnostics

## Goal and background

Satisfy parent R5/R6 with usable direct Python tools and genuine checks of
unsaved editor text. Existing `buildPythonToolsTab` adds a second-level card;
`checkSyntax` reads saved text and the native VM serializes checks with runs.

## Requirements

- T1: Show project/file selection and syntax, run, compile, stop, module/package
  inspection and local package operations directly on the root Tools tab.
- T2: Preserve common offline tools and terminal access, real status/exit/output
  and existing direct tools-page entry compatibility.
- T3: Analyze immutable unsaved snapshots with the real compile-only VM path,
  no source writes or execution. Consume C's frozen CodeAnalyzer contract.
- T4: Map native file/line exceptions to validated full-line UTF-16 ranges;
  handle Unicode/CRLF, stale revisions, disposal and VM busy/unavailable states.

## Acceptance criteria

- [ ] The main Tools tab exposes operations without the extra feature menu and
  works at 360x800 and 1200x800 with long paths and larger text.
- [ ] Selection/loading/empty/error/duplicate-action/cancel/disposal scenarios
  preserve the correct project and actual output streams/status.
- [ ] Unsaved valid/invalid buffers are analyzed without disk changes or program
  side effects. An occupied VM produces honest unavailability instead of queued
  obsolete work; later idle checks recover and stale responses are discarded.
- [ ] Native line precision is retained; exact token columns are not fabricated.
  Shared Problems/underlines navigate the current corresponding document.
- [ ] Focused analyzer/widget/native tests, complete Python tests/analyzer and
  installed OHOS tools/editor scenarios pass.

## Boundaries and dependencies

Own `lib/python_tools_page.dart`, new app-only analyzer/service integration,
`lib/python_runner.dart` source-check method, reviewed profile registration and
focused tests. Preserve initial edits. Depend on module service and C's real
analysis API; do not define or edit common editor/panel/schema files.
