# Direct Python tools implementation evidence

Date: 2026-10-22. Owner: `implement_python_direct_tools`.

## Owned changes

- `lib/python_tools_page.dart`: retains the existing tools-tab registration and
  `PythonToolsPage(store:, runner:)` route API, and exposes `PythonToolsBody` for
  the root Tools tab. One scroll body displays project/file selection, syntax,
  compile/run/stop, separate stdout/diagnostics, runtime/module inspection, and
  local package management. The terminal callback and common offline tools use
  public `ToolsGridSliver`; the root tab adds no Scaffold/AppBar or extra menu.
- `test/python_tools_page_test.dart`: preserves and updates initial profile/tab
  coverage, and adds package/lifecycle/catalog/layout regressions.
- This note only. No main/profile, shared-core, runner, service, native, asset,
  signing or generated-platform changes. No staging or commits.

## Integration and state contracts

`buildPythonToolsTab(ProjectStore, VoidCallback)` remains unchanged. The public
body accepts the same store and runner plus optional `packageService` and
`onOpenTerminal`. The wrapper accepts optional `packageService` for dependency
injection. Production source operations create the existing
`PythonPackageService` with a captured project path and `runner.checkSource`;
no duplicate installer, network fetch, setup script, pip claim or fake compiler
is added.

Project ID/path, file scan, package list and operation generations reject stale
results. A store/project switch or disposal cancels package transactions and
running/late-arriving native handles. Actions are disabled during active work;
package cancellation retains the service's rollback semantics. Package results
show compatibility scope, installed metadata/digests and preserved modified
files. Internal `.qfli` modules are not presented as user entry scripts.

The system file picker supports local paths and document URIs. URI files are
copied to an owned temporary directory, capped at 16 MiB, consumed by the same
service, and removed on body disposal. Directory-only document URIs cannot be
enumerated through the existing picker contract; the UI honestly requests an
already-imported sandbox directory path. Desktop directory paths are accepted.

A real regression found during verification involved `ExpansionTile` storing
its boolean state in a shell scroll-offset bucket used by editable text. A
local PageStorage scope without inherited storage keys prevents the type
collision. Expansion and file/operation state remain owned by the body.

## Verification

- `flutter test --no-pub test/python_tools_page_test.dart`: **18 passed, zero
  skips** on this Windows host. Full log: `build/tools-widget-tests.log`.
- Three tests use the actual FFI VM: directory package/submodule installation,
  subsequent Run importing bundled `statistics`, detail/remove with edited-file
  preservation at 360x800 and 1200x800; plus a real pure-source wheel selected
  through the URI picker boundary, installed, imported and run to `[4, 9, 16]`.
- Other tests verify direct root access/common tools/terminal, compile/stop,
  syntax, missing dependency/path errors, duplicate prevention, cancellation
  and retry, disposal, late run handles, project switches during package checks,
  runtime catalog scope, late runtime probes, empty states and 1.7x text with
  long project/file/path labels on both target sizes. Channel doubles establish
  transport/lifecycle behavior only; they are not counted as native execution.
- Actual DLL SHA256:
  `2329ef7d374e35dd5159db0f3f056b094effc9a0372ad29fe704af472a6c309f`.
- `flutter analyze --no-pub lib/python_tools_page.dart test/python_tools_page_test.dart`:
  no issues.
- `dart format --output=none --set-exit-if-changed lib/python_tools_page.dart test/python_tools_page_test.dart`:
  no changes.
- `git diff --check -- lib/python_tools_page.dart test/python_tools_page_test.dart`:
  clean.

The Flutter SDK and DLL verification windows were released to the coordinator
after these checks. Full app analysis/tests, signed final HAP and installed
OHOS Tools/editor/picker acceptance remain coordinator gates; host results do
not close them.
