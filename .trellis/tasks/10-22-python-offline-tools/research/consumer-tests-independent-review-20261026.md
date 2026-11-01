# Independent consumer test source review

Recorded: 2026-10-26T10:18:46+08:00. Source recheck: 2026-10-26T10:40:26+08:00.
Reviewer: child `/root/review_python_consumer_tests` (`trellis-check`).
Active task: `.trellis/tasks/10-22-python-offline-tools`.

Current status: all three initial Tools findings are resolved in the p6 source snapshot below. No remaining concrete source blocker was identified in the reviewed scope. Lint, type-check, and runtime tests remain NOT RUN. The initial findings below are retained as historical evidence, not current blockers.

## Scope and restrictions

This review compared `test/python_highlighting_test.dart` and the new real Home/root Tools test in `test/python_tools_page_test.dart` with their implementation paths, the shared core APIs, the vendored editor, the local Flutter test binding, and the existing named-workspace fixture. This was a read-only source review. The only authorized write is this report. Pi p6 owns fixes for the three Tools findings. No consumer test, manifest, shared core source, SDK source, or device state was modified by this reviewer.

Highlighting coverage is core `.py` theme rendering, the disabled-highlighting setting, and reopening a minimal real CodeEditor. It does not establish actual application editor-route behavior or Python profile registration. No broader acceptance is claimed.

## Source snapshot

SHA256 values were read from the workspace at the recorded time. Findings refer to this snapshot; later p6 edits require a source recheck.

| Source | SHA256 |
| --- | --- |
| `test/python_highlighting_test.dart` | `bb094416539aecc3f9efe68ad0dc5a66ffbbda4ed3cc9384006dff7a2ba76d24` |
| `test/python_tools_page_test.dart` | `248fba741725af9173aa188c39dd86367d5d93d022bf53f5a979b6e5ba758912` |
| `lib/python_tools_page.dart` | `2b882307dea2152cdcb3d7be275d512b314c71c7709a7943f0089cfbd41540be` |
| `../qfli_studio_core/lib/pages/home_page.dart` | `84cdfc0f3e6fd16c001e2200b45447a470fe66e7eff363bbb54773f02085be3c` |
| `../qfli_studio_core/lib/services/task_activity_service.dart` | `d0675696eba2551360809658bb1a89957ee029bc0fa2f1a989d83f2fb2e18ea7` |
| `../qfli_studio_core/lib/services/app_paths.dart` | `a16eff0376123dc467c7cf638bf55ab19e584305174f80d954ca82a7c20edb69` |
| `D:/ProgramFiles/flutter_ohos/packages/flutter_test/lib/src/binding.dart` | `193c9eff7b4d5a0715c48c130863b7308ec7bae464c859422577c348d985b612` |

## Initial snapshot findings (fixed)

None. Test edits are outside this reviewer's write scope.

## Initial snapshot findings (not fixed at initial review)

### 1. Navigation polling does not advance the animation clock

Location: `test/python_tools_page_test.dart:1150`; new navigation predicates at lines 1026, 1050, and 1056.

The `_pumpUntil` helper repeatedly calls `tester.pump()` without a duration. Core `HomePage._selectPage` animates adjacent destinations with `animateToPage` for 220 milliseconds. The local automated Flutter test binding advances its fake clock in `pump` only when the supplied duration is non-null. The real delay inside `runAsync` advances wall time, not the binding's fake frame timestamp. Consequently, these navigation waits can time out with the animation stationary.

Recommendation to p6: retain bounded real asynchronous polling, and advance animation frames with a duration such as `tester.pump(const Duration(milliseconds: 16))`. Verify all three navigation transitions after a host SDK grant.

### 2. Singleton initialization awaits real filesystem work in the fake async zone

Location: `test/python_tools_page_test.dart:1005`.

The new `testWidgets` body directly awaits `TaskActivityService.instance.initialize()` before entering a `tester.runAsync` block. Its first call enters `_read`, resolves `AppPaths.storageDirectory()`, probes directory writability, and awaits `File.exists()`. Real filesystem completion is not safely serviced by this fake async wait and can stall initialization. The fixture also supplies no temporary path-provider routing for this singleton, so its storage resolution can probe host directories. In contrast, `test/python_named_workspace_test.dart:39` initializes through `setUpAll`, with path-provider storage routed to its temporary fixture before singleton initialization.

Recommendation to p6: establish temporary storage routing before the singleton first resolves its path, and initialize outside the widget fake async zone, either with `tester.runAsync` or the existing isolated `setUpAll` pattern. Preserve cleanup of the path-provider handler and fixture resources.

### 3. Navigation selection does not establish source-file readiness

Location: `test/python_tools_page_test.dart:1036`.

The test asserts the `src/main.py` label after waiting only for navigation selection. `PythonToolsBody.initState` schedules `_refreshFiles` after a frame. `_refreshFiles` then awaits asynchronous `Directory.list` events before publishing `_files`, selecting the entry file, and clearing `_loadingFiles`. A selected navigation destination does not prove this file-discovery work finished. This remains a readiness gap even after fixing animation time advancement.

Recommendation to p6: explicitly await the expected entry-file label and completion of the loading state before asserting loaded Tools controls.

## Highlighting source-review result

No concrete compile/API blocker was found in the reviewed highlighting source. `CodeIndicatorValue.paragraphs`, `DefaultCodeLineNumber.notifier`, `CodeLineRenderParagraph.paragraph`, `IParagraph.getSpanForPosition(TextPosition)`, `SettingsStore.setSyntaxHighlighting`, and `HighlightThemes.themeFor` match the inspected implementation. The four ASCII line lengths and token probe offsets match the fixture. The direct `re_editor` dev dependency is present and resolves through the existing vendored path override in source configuration; dependency resolution was not executed.

The test reads token spans from the real editor notifier and waits for asynchronous highlighting with bounded polling that advances frame time. It unmounts the successful editor before disposing its controller. These source observations do not prove analyzer success, isolate behavior, rendering success, or test completion.

## Verification

- Lint: NOT RUN. No SDK execution grant.
- TypeCheck: NOT RUN. No SDK execution grant.
- Tests: NOT RUN. Runtime remains UNRUN.
- Dart/Flutter/pub commands: NOT RUN.
- Native builds and runtime: NOT RUN.
- OHOS/device commands, installation, launch, daemon changes, and signing changes: NOT RUN.
- Completed: source/API/fixture/async comparison and SHA256 snapshot only.

A fresh authorized host run and a source recheck after p6's fixes remain required. This report grants no execution window and makes no installed OHOS acceptance claim.

## Source recheck after p6 fixes

Recheck timestamp: 2026-10-26T10:40:26+08:00.

| Source | Initial SHA256 | Rechecked SHA256 |
| --- | --- | --- |
| `test/python_tools_page_test.dart` | `248fba741725af9173aa188c39dd86367d5d93d022bf53f5a979b6e5ba758912` | `f12a935188cea6005aea9c368baec3b4f0c71cdffc8a0e2d353df0bc34dea8c1` |
| `test/python_highlighting_test.dart` | `bb094416539aecc3f9efe68ad0dc5a66ffbbda4ed3cc9384006dff7a2ba76d24` | `bb094416539aecc3f9efe68ad0dc5a66ffbbda4ed3cc9384006dff7a2ba76d24` |

### Findings (fixed by p6; independently source-rechecked)

1. Animation time: `_pumpUntil` now accepts an optional `Duration? frame` and passes it to the initial, repeated, and final `tester.pump` calls. All three Home navigation waits explicitly pass 16 milliseconds. This advances the fake animation clock while retaining real I/O polling. Existing callers keep the previous null-duration default.
2. Singleton initialization and temporary storage: the new Home test installs a path-provider method-channel handler before initialization. Support/documents paths resolve to the test's real temporary directory. The test registers handler cleanup. It then enters `tester.runAsync`, requires `AppPaths.storageDirectory()` to equal that temporary directory, and awaits `TaskActivityService.instance.initialize()` there. A previously resolved unexpected storage path now causes an explicit expectation failure rather than silent host-directory use. This addresses the observed fake-async wait and storage-routing defects in this fixture's first-resolution path.
3. File discovery readiness: after reaching the root Tools destination, the test explicitly waits for the platform-correct `src/main.py` label and for the loading indicator to disappear, with 16 millisecond frame advancement, before asserting controls that depend on the discovered file.

### Findings (not fixed / remaining)

No remaining concrete source blocker was identified for these three fixes. The highlighting file is unchanged from its reviewed snapshot. Its claim remains core `.py` rendering, disabled highlighting, and reopening a minimal real editor; it does not establish the actual application editor route or Python profile registration.

### Recheck verification

Only source and SHA256 checks were performed. This reviewer edited no tests, manifest, shared core source, native source, or SDK file. The report is the only write.

- Lint: NOT RUN.
- TypeCheck: NOT RUN.
- Widget tests and actual highlighting isolate behavior: NOT RUN; runtime remains UNRUN.
- SDK/pub/analyzer/build/native/device/control commands: NOT RUN.

The source findings are resolved; runtime acceptance still requires a fresh authorized host run. The initial report's statement that a source recheck remains required is satisfied for the two hashes in this recheck only.
