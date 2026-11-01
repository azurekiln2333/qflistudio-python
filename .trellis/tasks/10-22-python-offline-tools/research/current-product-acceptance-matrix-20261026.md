# Current product acceptance matrix — 20261026

- Active task: `.trellis/tasks/10-22-python-offline-tools`
- Owner of this file only. No wrapper, no code, no test edit.
- Method: read-only source and test inspection. **No** test, analyze, toolchain,
  version, SDK, native, device, control or channel command was run.
- Scope boundary: this repo (`lib/`, `test/`) only. Shared-core internals
  (`../qfli_studio_core`) are cited only to say an area is delegated, never audited.

## Baseline: what "focused5" is defined to run

**Correction (root review).** No current test file has been launched under any live
host grant. Grant 704 is retired and 732 supersedes it. Specifically:

- the five focused files below were **never launched** under 704;
- the named-workspace tests are **unrun** against the current source;
- the historical "28 tests" result is **prior evidence for earlier source**, not
  evidence for the files recorded in this matrix.

So everything in this matrix is **prepared and unrun**. Nothing here is a pass, and
nothing here may be quoted as current-source evidence.

`FOCUSED_SUITES` + `NAMED_WORKSPACE_SUITE` in
`run_python_host.py` = 5 files:

1. `test/python_debugger_test.dart`
2. `test/python_debugger_native_test.dart`
3. `test/python_debugger_audit_test.dart`
4. `test/python_content_audit_test.dart`
5. `test/python_named_workspace_test.dart`

Everything below marked **beyond focused5** is current source that focused5 does
not execute.

## Acceptance matrix

| # | Area | Current source (this repo) | Current coverage | Status | Gap |
| --- | --- | --- | --- | --- | --- |
| 1 | Direct root Tools | `lib/python_tools_page.dart` (`buildPythonToolsTab`, `PythonToolsBody`), `lib/main.dart` `toolsTabBuilder` | `python_tools_page_test.dart` "tools tab exposes Python controls directly at 360/1200" — asserts `FunctionsTab` renders `PythonToolsBody`, `PythonToolsPage` absent, `onOpenContentTool` never called, terminal hook, controls present; `offline_regression_test.dart` "Python tools 页面由档位提供且可构建"; **new (authored, unrun)** "real Home opens the root Tools tab without pushing PythonToolsPage" | Covered at body level and now at app level **beyond focused5** | App-level gap closed by the new authored test, which is **unrun**. Nothing else known at source level |
| 2 | Local packages | `lib/python_packages.dart`, package controls in `python_tools_page.dart` | `python_tools_page_test.dart` "real VM directory package check install show remove" (real VM, both widths); `python_packages_test.dart` (zip/wheel, manifest, ownership, case-collision, symlink, cancellation); `python_package_runtime_test.dart`; `python_module_imports_test.dart` "entry, root and local packages precede bundled modules" | Covered **beyond focused5**, service layer strong | No UI-level assertion that a *failed* compatibility check leaves no partial bundle |
| 3 | Unsaved diagnostics / Problems | `lib/python_code_analyzer.dart` (compile-only, snapshot-first, never rereads disk), `lib/main.dart` `codeAnalyzer` | `python_editor_analysis_test.dart` (360/1200: unsaved buffer diagnostic reaches Problems, tap seeks to the line, clean buffer shows 本地检查未发现问题, file not executed, disk bytes unchanged); `python_code_analyzer_test.dart` (UTF-16 ranges per newline, indentation errors, second dirty buffer retained, runtime-missing recovery); `python_named_workspace_test.dart` 2nd test (dirty same-name files isolated by workspace owner) | Covered **beyond focused5** for unsaved buffers | No Problems-panel case for a **saved** file's diagnostic; no multi-diagnostic (2+ errors) ordering case |
| 4 | Runtime leases | `lib/python_runtime_activity.dart` (single-VM gate, 4 ops, never queues), consumed by `python_runner.dart` | `python_runtime_activity_test.dart`: stale lease cannot release newer owner; late native exit + stop request stay busy; analysis claims before its async probe; run owns VM before delayed probe; bundle prep retains then releases on failure; late throw and malformed result both release; real VM run rejects analysis then recovers (skipped when DLL absent) | Covered **beyond focused5** | Only `run`/`analysis` labels are exercised; `compile` and `debug` busy/acquire paths are unasserted |
| 5 | Named multi-root explorer | Core `FileExplorer`/`WorkspaceStore`; repo binds via `pythonProfile.supportsSavedWorkspaces` (default true) and non-main-studio product key | `python_named_workspace_test.dart` (real UI: create+s save named 2-root workspace from the explorer, dirty buffers survive tree collapse, metadata never saves dirty sources, reload restores per-root documents/selections/expanded dirs, offline-only) | Covered in focused5 | No 3+ root case; no workspace rename/delete under the Python profile |
| 6 | Highlighting | Core owns `HighlightThemes.themeFor`, `HighlightSettingsPage`, `SettingsStore.syntaxHighlighting`, the highlight worker and vendored `re_editor`. The repo consumed none of it before this batch | `test/python_highlighting_test.dart` (**authored by p5, unrun**): builds the real `CodeEditor` with the theme resolved by `HighlightThemes.themeFor`, reads rendered spans from the public `CodeIndicatorValue.paragraphs`, and asserts keyword/string/comment colours match the resolved theme, real line lengths, exact span text (`def`, `"hello"`), suppression when `setSyntaxHighlighting(false)`, and stability after re-open | Authored by p5 **beyond focused5**; not covered here | **Unrun.** Existence is not acceptance. Also note: the file imports `package:re_editor/re_editor.dart` directly and its own docstring says pub resolution and the lockfile entry await a grant, yet `pubspec.yaml` already lists `re_editor: ^0.10.0` in `dev_dependencies` and `pubspec.lock` maps it to `../qfli_studio_core/vendor/re_editor`. That docstring line looks stale. No pub was run to prove resolution |
| 7 | App startup | `lib/app_startup.dart` (`runWithAppStartup`: deferred first frame on android/ohos, splash→home, optional progress channel), `lib/main.dart` | `startup_test.dart`: android+ohos deferred frames and progress 1/3,2/3,1 before home; slow bootstrap settling; failed store load + channel errors still reach home; delayed progress never holds the first frame; unexpected bootstrap failure releases the gate; other platforms use the Flutter fallback; OHOS first engine frame contains the real `HomePage` with the channel present and missing | Covered **beyond focused5** | Android has no equivalent real-store + real-progress variant (only OHOS does) |

## Exact later command scope

Beyond focused5 there are 16 remaining current test files. Full product set is now
**21** files, confirmed by listing `test/*.dart` after p5 delivered
`test/python_highlighting_test.dart`.

Stage A — **prepared, NOT run**: the 5 focused files (see the correction above).

Stage B — recommended single merged run for the next bounded grant
(`--no-pub --concurrency=1`, one command, 16 files):

```
test/offline_regression_test.dart
test/python_app_test.dart
test/python_code_analyzer_test.dart
test/python_editor_analysis_test.dart
test/python_ffi_test.dart
test/python_highlighting_test.dart
test/python_lifecycle_test.dart
test/python_module_audit_test.dart
test/python_module_imports_test.dart
test/python_ohos_bridge_test.dart
test/python_package_runtime_test.dart
test/python_packages_test.dart
test/python_runtime_activity_test.dart
test/python_source_check_test.dart
test/python_tools_page_test.dart
test/startup_test.dart
```

Stage C — full current product acceptance: Stage A + Stage B (all 21 files) in one
merged invocation.

p5 delivered `test/python_highlighting_test.dart` (9680 B, 3 `testWidgets`). It now
counts as the 21st current file, so Stage B grew from 15 to 16. This matrix still
does not author or modify that file. Highlighting stays **unrun**, so no area moved
from unclaimed to covered by its arrival alone.

Analyze scope for a later grant (this repo only, never shared-core internals):

```
dart analyze lib test
```

`run_python_host.py` currently defaults to a 2-file scope
(`tool/python_debugger_ohos_audit.dart`, `test/python_debugger_audit_test.dart`).
Passing `lib test` is the exact broadening needed for product acceptance; it stays
inside this repo.

## Real VM / DLL prerequisites

- Default transport is `PythonNativeTransport.automatic`, which resolves to **FFI**
  on Windows/Linux/iOS/macOS (`python_runner.dart` `_useFfi`). On this host the
  native library is `native/build/windows/qfli_py_ffi.dll` (present, 745758 B).
- These need that real DLL, or they skip/fail honestly:
  - `python_editor_analysis_test.dart` — real analyzer through Problems.
  - `python_runtime_activity_test.dart` — its real-VM case is `skip:`-guarded on
    `Platform.isWindows && File(library).existsSync()`.
  - `python_tools_page_test.dart` — package install/run case.
  - `python_packages_test.dart`, `python_package_runtime_test.dart`,
    `python_module_imports_test.dart`, `python_source_check_test.dart`,
    `python_ffi_test.dart`, `python_lifecycle_test.dart`.
- Method-channel–only tests need no DLL (`python_app_test.dart` mocks
  `qfli_py/native`; `python_runtime_activity_test.dart` mocks the channel for all but
  the one real-VM case).
- `python_ohos_bridge_test.dart` is a byte-identity check on the two `QfliPyNative.ets`
  copies; it needs the files, not a device.
- No test here asserts real OHOS device behaviour. OHOS acceptance stays separate and
  is not replaced by any host run.

## Concrete missing behavior tests

1. **Saved-file diagnostics in Problems.** Only unsaved buffers are asserted through
   `EditorProblemsPanel`. A saved-file case would separate "snapshot-first" from
   "disk reread" behaviour on the same panel.
2. **Multiple diagnostics ordering.** All current analyzer cases assert a single
   problem. Two independent syntax errors in one project would prove ordering,
   `location()` mapping and stable list identity.
3. **`compile` and `debug` lease paths.** `busyReason` has four branches; tests cover
   only `run` and `analysis`. A `debug` lease blocking analysis, and a `compile` lease
   rejecting a run, are unasserted.
4. **Failed compatibility check leaves no bundle.** The service has cancellation and
   syntax-failure tests. The Tools-tab path that fails 检查兼容性 before 安装到项目 has
   no UI-level "no files, no manifest" assertion.
5. **3+ root workspace, and workspace rename/delete** under the Python profile
   (current coverage is exactly two roots, create-only).
6. **Root Tools tab from the real `QfliApp` Home.** Today's assertion mounts
   `FunctionsTab` directly, so the Home→Tools tab wiring is assumed, not proven.
7. **Non-OHOS Android startup with real stores.** OHOS is the only platform with a
   real-store first-frame test.

Highlighting is deliberately absent from this list: it is a shared-core concern and
this repo contributes no source or test for it.

## Authored, unrun (current source)

Two authored tests exist for this suite. **Neither has been compiled, analyzed or
executed under any grant.**

### 1. Root Tools navigation (authored in this batch)

Appended to the existing `test/python_tools_page_test.dart`. It creates no new file,
so the total stays 21 with p5's file as the 21st.

`real Home opens the root Tools tab without pushing PythonToolsPage`

- Mounts the **real** `QfliApp` with the repo's existing real fixtures: the
  `ProjectStore` from the file's `setUp` (real temp registry, real `src/main.py`)
  plus real `AuthStore`/`SettingsStore` bound to files under the same temp directory.
  No fake app home and no new production surface.
- Routes only the OS storage lookup into that same temp directory, using the
  named-workspace fixture pattern: a mock handler on
  `plugins.flutter.io/path_provider` returns the temp path, `AppPaths.storageDirectory()`
  is forced to it before any singleton resolves it, and
  `TaskActivityService.instance.initialize()` then runs inside `tester.runAsync`.
  This keeps machine storage out of the test and avoids a fake-zone await that can
  never complete.
- Sets `StudioProfile.current = pythonProfile` and clears `AppRestoreGate.status` so
  `QfliApp` mounts `HomePage` rather than `RestoreCompletePage`.
- Asserts **navigation state**, not text: `NavigationBar.selectedIndex` starts at 0,
  becomes 1 after tapping the real `NavigationDestination` at index 1, and returns to
  0 when tapping index 0.
- Asserts the tab is not a pushed route: `HomePage` stays mounted and
  `PythonToolsPage` is `findsNothing` before, during and after navigation.
- Asserts direct Python controls on the tab body: `检查语法`, the `运行`
  `FilledButton`, the `编译` tooltip, and the file label from the real temp project.
- One concrete harmless operation: expands the local package manager
  (`本地源码包`), then requires the `python-package-source` field and the empty
  package state to appear. No network, no system dialog, no native build, no program
  execution. `HomePage`'s `refreshIfDue` returns immediately because
  `pythonProfile.offlineOnly` is true and the empty `AuthStore` has no token, so no
  request leaves the process.

Three defects were found by an independent native review and fixed in the test only:

1. **Zero-elapsed pumps could not drive the page animation.** `_pumpUntil` pumped with
   no duration, so the fake clock never advanced and `HomePage`'s 220 ms
   `animateToPage` could not progress. `_pumpUntil` now takes an optional `frame`
   duration. The default is `null`, which is exactly a bare `pump()` for the other 35
   call sites in this file, so none of them changed. This test passes 16 ms on its 5
   calls and still polls real I/O between frames.
2. **A fake-zone await on real filesystem I/O could stall, and the singleton would
   read machine storage.** `TaskActivityService.instance` is constructed without a
   `storageFile`, so its `_read()` calls `AppPaths.storageDirectory()`. The direct
   `await initialize()` was removed from the test body. Storage is now routed to the
   temp directory and the cache is warmed inside `tester.runAsync` before
   `pumpWidget`.
3. **A selected index did not prove the async directory listing finished.** A
   dedicated wait now requires both the `src/main.py` label and an empty
   `LinearProgressIndicator` before any control assertion.

Static source checks performed only: balanced braces and parentheses, exactly one
occurrence of the test name, five `frame:` call sites all inside this test with none
added to existing callers, and symbol existence for every referenced API (`QfliApp`,
`HomePage`, `AppRestoreGate.status`, `AppPaths.storageDirectory()`,
`AuthStore(storageFile:)`, `SettingsStore(storageFile:)`,
`TaskActivityService.instance.initialize()`, `PythonToolsBody`, `python-package-source`,
`本地源码包`, `运行时与模块`). Confirmed against source: `home_page.dart` uses
`animateToPage` with 220 ms, `QfliApp` gates only on readiness (no login gate),
`AppPaths` is referenced nowhere in `lib/`, and `pythonProfile` sets `isOffline: true`.

Root Tools therefore moves from **missing at app level** to **authored, unrun**.
It does not move to covered.

### 2. Highlighting consumer integration (authored by p5)

`test/python_highlighting_test.dart`, 3 `testWidgets`. Read here for scope only. This
matrix does not own, edit or re-run it.

- Real interfaces only: `HighlightThemes.themeFor` builds the theme, the real
  `CodeEditor` renders it, `Highlight` runs in an isolate, and assertions read the
  public `CodeIndicatorValue.paragraphs`. No fake renderer, no hardcoded spans.
- Asserts `.py` resolves to the `python` language profile with three distinct
  keyword/string/comment colours, plus per-line lengths and exact leaf span text.
- Asserts `setSyntaxHighlighting(false)` suppresses the theme and leaves every probe
  at the base colour, after a 120 ms grace window for late styling.
- Asserts token colours survive closing and re-opening the editor.

Highlighting therefore moves from **no acceptance test in this repo** to
**authored, unrun**. It does not move to covered, and the product must not claim
highlighting acceptance until this file has actually run and passed.

## Evidence ledger (historical vs current)

The two evidence classes stay separate and are never combined:

| class | what it is | counts as current-source evidence? |
| --- | --- | --- |
| Historical | the earlier "28 tests" result, produced against **earlier source** | **No.** Different bytes and different assertions |
| Current | the 21 files in `test/` as they stand now, plus the two authored tests above | **No.** Nothing has been executed |

The historical number is retained only to explain an earlier claim. It says nothing
about the current files, and this matrix does not reuse it.

## 中文摘要

测试目录现有 21 个文件。
第 21 个文件由 p5 编写。
该文件名是 `python_highlighting_test.dart`。
该文件用真实 `CodeEditor` 观察 token 样式。
该文件尚未运行。
本矩阵不改动该文件。
根 Tools 导航测试由本工作编写。
该测试尚未运行。
历史证据只覆盖旧源码。
当前证据为零。
全部结论等待新授权后验证。

## Non-claims

- **No test in this matrix has been run.** The five focused files were never launched
  under grant 704, the named-workspace tests are unrun against current source, and
  the historical "28 tests" result belongs to earlier source. Everything here is
  prepared/unrun.
- Nothing here says any area passed. No command was executed.
- Nothing here weakens a requested behaviour or substitutes a host check for OHOS
  device acceptance.
- Highlighting and the shell Problems/Explorer widgets are core-owned. This matrix
  records only the Python repo's obligations.
