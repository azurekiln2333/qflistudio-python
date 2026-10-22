# Research: Python tools and offline editor contracts

- Query: Inspect Python profile/tools/runner/terminal and shared extension contracts; plan direct tools, unsaved diagnostics, real offline debugging and meaningful verification without overlapping the C coordinator's core ownership.
- Scope: mixed; read-only repository audit and primary documentation, with this research file as the only write.
- Date: 2026-10-22
- Active task: `.trellis/tasks/10-22-offline-language-apps` (planning).
- Author: dispatched `python_tools_research`; no product code, shared-core code, task activation, git operation, build, test, installation or device action performed.

## Findings

### 1. Source requirements and ownership

The original attachment was read before the audit: `C:/Users/lichengyu/.codex/attachments/f25c5895-1de8-4941-b863-6bfa0b63cb3c/pasted-text-1.txt`. Relevant requirements are direct language tools on the tools tab, visible editor error marks and useful Problems/Output/Debug Console/Terminal/Ports equivalents where feasible, actual offline operation, and real OHOS acceptance. Existing host mocks or a stop button cannot establish breakpoint debugging or OHOS execution. The original all-product goal remains larger than this Python tools research.

The coordinator's existing `ownership-message.txt` assigns Python runtime/modules/content/tools/terminal/adapters to Python and shared editor/workspace/content-filter/diagnostic UI to C coordinator w1R:p1. `D:/MyNewProjects/qfli-core-release-sync.md` confirms exclusive core ownership. Do not modify shared-core files while implementing the plan below. C's provider contract publication is a dependency; its source implementation was still absent at the last read.

### 2. Files found and code patterns

Paths below are relative to `D:/MyNewProjects/qfli_python` unless prefixed with `../qfli_studio_core`.

| File and anchor | Current role / evidence |
| --- | --- |
| `lib/main.dart:22` | Const Python `StudioProfile`; Python-only templates and native runner. |
| `lib/main.dart:27` | Registers `toolsTabBuilder` and `toolsPageBuilder`; `:29` declares offline; `:34` supports `.py`/`.mpy`; `:41` registers the terminal delegate. |
| `lib/python_tools_page.dart:15` | Tools tab returns a shared `ToolsGrid`, but its sole Python card at `:23` pushes `PythonToolsPage` at `:27`; language operations remain behind a second page. |
| `lib/python_tools_page.dart:48` | Page-local selection, scan generation, operation/output/cancel state. |
| `lib/python_tools_page.dart:61` | Filters cloud/missing projects; `:128` recursively discovers `.py`/`.mpy` with `followLinks:false`; `:144` rejects stale scans. |
| `lib/python_tools_page.dart:153` | Syntax/run actions; syntax through injected runner at `:164`, execution at `:174`. |
| `lib/python_tools_page.dart:187` | Collects stdout/stderr separately, then concatenates stdout followed by stderr after exit at `:190`; the display loses channel distinction and actual interleaving. |
| `lib/python_tools_page.dart:214` | Bytecode compilation; result refreshes file list at `:235`. Stop waits for native completion (`:248` plus run `finally`). |
| `lib/python_tools_page.dart:268` | Full Scaffold/AppBar page, max width 760 and scrolling ListView. Action Wrap begins `:356`; source-only controls reject `.mpy` at `:363` and `:375`. |
| `lib/python_runner.dart:29` | App-owned `ProgramRunner`; automatic FFI selection on desktop/Apple at `:39`, channel on OHOS/Android. |
| `lib/python_runner.dart:71` | Saved-file `.mpy` compile; existing native artifact capability guard at `:81`. |
| `lib/python_runner.dart:113` | Saved-file syntax check: validates file existence and reads disk at `:120-126`; submits source/project/entry with empty stdin at `:135-141`. It cannot analyze unsaved editor text. |
| `lib/python_runner.dart:176` | Saved-file run, runtime probe, `.mpy` routing and input.txt; controlled path at `:209`. |
| `lib/python_runner.dart:250` | Controlled run returns streams/cancel before native completion. `_completeControlled` awaits native response at `:322`; HAL output becomes Dart streams only afterward (`:327-331`). |
| `lib/python_runner.dart:429` | Runtime info is an actual probe, including cancellation/artifact support and transport; no debugger capability currently. |
| `lib/python_runner.dart:470` | Shared private native invocation path for source, compile-only, paths and transport; reuse this instead of another MethodChannel in widgets. |
| `lib/python_runner.dart:574` | Syntax result has success/error/version only; compilation adds artifactPath at `:586`. |
| `lib/python_terminal.dart:17` | `python`, `python3`, `micropython` route to one embedded backend. |
| `lib/python_terminal.dart:49` | Simple command parser/delegate; real version probe at `:73`; no REPL, `-m`, `-c`, options or extra script arguments (`:84-122`). |
| `lib/python_terminal.dart:127` | Sandbox path resolution, existing-file/extension validation; runner result channels/cancel forwarded at `:151-166`. |
| `lib/python_terminal.dart:192` | Project root reconstruction respects nearest in-sandbox `.qfli/project.json` and cwd fallback. Preserve it for local package operations. |
| `../qfli_studio_core/lib/services/studio_profile.dart:134` | Full tools-page builder; `:148` provides inline tools-tab body with real store and terminal callback. |
| `../qfli_studio_core/lib/pages/quick_tools_page.dart:39` | Shell owns tools Scaffold/AppBar; inline product body is called at `:48`. Product body must not nest another Scaffold. |
| `../qfli_studio_core/lib/pages/tools_grid.dart:8` | ToolDefinition permits a builder or onTap. `:38` exposes commonTools metadata. `:96` is whole scroll body; `:119` adds common tools; private card grid pushes pages at `:175`. No current slot for arbitrary inline project controls. |
| `../qfli_studio_core/lib/services/studio_profile.dart:235` | DocumentToolRequest has in-memory text and save callback, but replaces a full document editor rather than providing diagnostics. EditorFileTool `:255` accepts only file/project paths and yields message/success, so it is not the unsaved diagnostic API. |
| `../qfli_studio_core/lib/services/studio_profile.dart:279` | WebPreviewSession.debugStream is Web preview console forwarding only. It is not a Python debugger session. |
| `../qfli_studio_core/lib/services/studio_profile.dart:297` | ProgramRunner API remains only `run(projectPath,entryFile)`; ProgramRunResult `:321` exposes stdout/stderr/exit/cancel, no breakpoint/step/evaluate. |
| `../qfli_studio_core/lib/editor/open_file.dart:39` | Live editor controller; `:44-46` retains dirty state/revision/pending save. |
| `../qfli_studio_core/lib/editor/editor_controller.dart:129` | Actual content edits increment revision and call onContentChanged; selection-only changes are rejected at `:124-127`. |
| `../qfli_studio_core/lib/editor/editor_page.dart:51` | Current bottom-panel enum is none/terminal/ai. `:978` saves open files before Run, but this is unsuitable as automatic analysis behavior. |
| `../qfli_studio_core/lib/editor/terminal_pane.dart:979` | Generic run stdout/stderr/exit/cancel attachment; channel distinctions at `:1006` and `:1013`. `:1043` appends Web console lines. |
| `../qfli_studio_core/lib/editor/terminal_pane.dart:440` | Editor terminal uses profile command delegate. Standalone terminal uses same extension at `../qfli_studio_core/lib/pages/terminax_terminal_page.dart:42`. |
| `native/ohos/QfliPyNative.ets:526` | Native capability probe currently advertises available/version/runControl/bytecode; `:557` accepts run/checkSyntax/compile and `:573` makes checks compile-only. |
| `native/src/qfli_py_bridge.c:221` | Entry-directory then project-root sys.path, argv[0], __file__; `:241` gives source real entry identity. |
| `native/src/qfli_py_bridge.c:254` | Native parser compiles submitted source directly; `:259` writes artifacts only when specifically requested; `:262` executes only when compile_only is false. |
| `native/src/qfli_py_bridge.c:388` | Whole-VM runtime mutex; all invocations serialize. `:427-428` creates fresh VM state; `:448` returns buffered output. |
| `native/src/qfli_py_hal.c:29` | 256 KiB stdout and 64 KiB stderr buffers; truncation is tracked. This is buffered output, not live native streaming. |

### 3. Frozen shared diagnostic contract (published during this audit)

Authoritative design: `../qfli_studio_core/.trellis/tasks/10-22-offline-editor-analysis/design.md:3` and `:8-42`. Global release sync now publishes the same schema. At last audit, `lib/services/code_analysis.dart` was not yet present and StudioProfile did not yet contain codeAnalyzer, so publication is a frozen plan, not a verified compiled API.

- Public module: `package:qfli_studio_core/services/code_analysis.dart`; optional `StudioProfile(codeAnalyzer: CodeAnalyzer?)`; existing runner unchanged.
- `CodeAnalyzer.analyze(CodeAnalysisRequest)` returns `Future<CodeAnalysisResult>`.
- Request carries normalized absolute projectPath, activeFilePath, language, active revision, and immutable `List<CodeDocumentSnapshot>` with exact path/text/revision for active and other open root buffers (`design.md:18-24`).
- `CodeDiagnostic` carries filePath, zero-based UTF-16 half-open startOffset/endOffset, message, severity, source and code (`:27-35`). Empty insertion ranges are allowed. CRLF must remain unchanged.
- `CodeAnalysisResult.unavailableReason == null` means analysis actually completed; nonnull means unavailable/error, not clean syntax (`:37-41`).
- Providers use isolated analysis, overlay unsaved snapshots where files are required, never overwrite user files or execute user programs or use network (`:45`). Python's compile-only entry can consume exact text directly in a fresh temporary VM without an on-disk source overlay because it does not import or run code. Preserve snapshot path only as diagnostic identity. If project-wide/import analysis later reads files, add an isolated overlay and explicit mapping back to snapshot paths.
- C core captures snapshots, debounces, rejects stale/root-mismatched responses, ignores selection-only changes, catches unavailable providers, clears outdated markers and owns wavy spans/Problems/navigation (`:47-49`). Core uses existing spanBuilder rather than a vendor fork.

Python adapter must wait for the actual published module to compile, add only `PythonCodeAnalyzer` and profile registration in app-owned files, then run app plus C-owned integration tests. Do not create a parallel diagnostic schema in core.

### 4. Unsaved syntax diagnostics and line/column accuracy

Minimal app implementation:

1. Add a source-based runner operation such as `checkSource(projectPath,entryFile,source)`. Reuse `_invokeNative('checkSyntax', ...)`, `stdin:''`, no artifactOutput, existing capability/result normalization. Saved-file `checkSyntax` should read disk then delegate to it. The source-based path must not require the entry file to exist: a newly created editor buffer can have a valid owned identity without saved bytes.
2. Implement PythonCodeAnalyzer against the frozen schema. Find active .py snapshot by normalized absolute path; compile its exact text and retain request revision. `.mpy` is not source syntax analysis. Native source compilation does not resolve imports, so explicitly distinguish syntax checking from import/module availability checks in tools and acceptance.
3. Parse only compile diagnostics. MicroPython stores traceback triplets file/line/block (`native/micropython_embed/py/objexcept.c:51`, `:579`), syntax parser records source_name and tok_line only (`native/micropython_embed/py/parse.c:1354-1356`), and renders `File "...", line N` (`native/micropython_embed/py/obj.c:149`). There is no reported token column to convert. Do not claim exact character errors from this output.
4. Recognize anchored traceback frame lines, supporting CRLF, Windows drive/backslash paths, spaces, Unicode paths and optional `, in ...`. Associate the SyntaxError/IndentationError message with the matching requested file. Never split paths on `:`. Do not parse arbitrary stdout as diagnostics.
5. Convert the native 1-based line to the exact snapshot's UTF-16 line start/end by scanning original line terminators; do not normalize CRLF or count UTF-8 bytes. Highlight the reported complete line (an honest line-level diagnostic); for blank/end-of-file positions use the allowed insertion range. Preserve original error message/code/source. Reject invalid/out-of-range locations rather than inventing line 1 or a token column. If a native failure has no trustworthy source location, return unavailableReason or unlocated operational output; it cannot support a precise CodeDiagnostic.
6. Backend missing, malformed response and transport failure return unavailableReason. Empty diagnostics is reserved for a successful real compilation. Compile-only must not create files, consume input, print user stdout or resolve imports.

Busy handling is required for correctness, not just UI polish. A normal infinite run holds the same native mutex that syntax checking needs (`bridge.c:388-393`). Current checks have no independent cancellation token. A debounced request can otherwise wait indefinitely behind a program or create a queue of obsolete VM calls.

- Use a Python-only execution coordinator shared by production runner, tools, terminal and analyzer; distinct const/default runner instances must share its actual native-operation lifetime. This is app-owned state, not a cross-product global analyzer lock.
- Acquire an analysis slot only while the Python VM is idle; at most one compile is in flight and one latest snapshot is pending. New edits supersede the pending snapshot. If a user run/debug session is active, return a nonnull busy/unavailable reason promptly and schedule the newest analysis after it ends.
- A controlled `run()` returns a handle before completion. Release busy state on its real exit/native-finally path, not when the handle is returned. Preserve cancellation and recovery on malformed responses, exceptions and page disposal.
- The core already handles stale response rejection; provider-side single-flight prevents wasted native queueing. Never cancel a user run merely to analyze text.
- If native calls can originate outside this coordinator (for example startup self-check racing with usable UI), add a native nonblocking analysis/try-lock capability with a typed busy result. A wall-clock timeout alone does not remove a queued native call and is not a scheduling solution.

### 5. Direct tools-tab plan within Python ownership

The current preexisting ToolsGrid card addresses the generic '专用/功能' labels but still pushes a second-level Python page. It therefore does not satisfy the attachment's stronger direct-operation requirement.

- Extract the controls/state/result rendering into an app-owned reusable PythonToolsBody/Panel without Scaffold/AppBar. `buildPythonToolsTab` embeds it directly in the existing shell tools body, preserving a visible local project/file context, syntax/compile/run/stop controls and status/output.
- Add directly usable sections for actual runtime/module inventory and local package/import operations; coordinate their APIs with the Python modules child. Do not introduce generic 'Python functions' cards that push the entire workbench. Long actions may use an ordinary chooser/dialog for input; the functional controls remain on the main tools page.
- Preserve a full-page wrapper only for existing callers of toolsPageBuilder. Both wrappers consume the same state/controller/runner instead of copying operation logic.
- Shared ToolsGrid currently owns its full scroll and private grid with no inline header slot (`tools_grid.dart:96`, `:152`). No core write is required to ship an app-owned ListView with inline panel and a non-scrolling shrink-wrapped responsive GridView of exported commonTools using shared ToolCard/ToolsTheme. Avoid nesting a freely scrolling ToolsGrid in a ListView. Alternatively ask C to publish a small leading-sliver slot; do not implement it unilaterally. Reuse tool metadata and shared computation/widgets, not duplicate generic implementations.
- Retain shared terminal callback and all common offline utilities. Local selection excludes cloud/missing projects, preserves scan generations, uses actual absolute operation paths and visible relative labels, and disables competing operations.
- Keep stdout, stderr, compiler diagnostics and app operation log visibly distinguishable. Current buffered native transport cannot promise live progress output while a program runs; a streaming extension is separate native work.

The existing `.trellis/spec/frontend/python-workflow.md` specifically describes the old card opening PythonToolsPage. Parent should update that convention after accepting the user-required inline design; old specs do not override the attachment.

### 6. Problems / Output / Debug Console / Terminal / Ports

| Surface | Current fact | Minimal truthful offline integration / owner |
| --- | --- | --- |
| Problems | No current diagnostic model/Problems tab in source; C contract is published. | Python provides real compile diagnostics from snapshots. C owns underlines, counts, panel, stale-result invalidation and jump/navigation. |
| Output | Native stdout/stderr and runner status exist; tools merge them. | Python tools separate run output, compiler errors and operation log, retain real exit/truncation and copy/clear. A common editor Output tab requires C-owned integration, not an app-owned duplicate terminal. |
| Debug Console | Existing appendDebug is Web console forwarding, not Python evaluation. | Show actual debug events only once a real Python native debug session exists; no fake expression evaluator or relabeled stdout. Frame-aware evaluate requires an additional explicit runtime capability. |
| Terminal | Both surfaces already use the Python delegate and runStreams. | Preserve offline aliases, sandbox path/root, stdout/stderr/exit/cancel semantics. Add only real offline local-package commands when implemented; no network pip workflow. |
| Ports | Python runner starts an in-process VM and exposes no managed listener/server session. | Do not add remote forwarding, sign-in or dev tunnels. If later local servers exist, track their app-owned listener registry only. An empty invented Ports control does not add a current Python capability. C can share a local-only panel only with real providers. |

Primary documentation checked on 2026-10-22: MicroPython documents custom-build settrace; VS Code documents Debug Console as debugger output/expression evaluation, and Ports forwarding as internet sharing through dev tunnels with GitHub sign-in. These descriptions establish the reference feature meanings, not implementations available in this OHOS product. URLs and retrieval details are below.

### 7. Real offline Python debugging is feasible but requires implementation

Do not dismiss debugging solely because there is no existing shared API. The repository already contains an upstream mechanism suitable for an in-process offline implementation:

- `native/micropython_embed/py/mpconfig.h:1517-1518` defaults MICROPY_PY_SYS_SETTRACE to 0. Neither app port config enables it. Current builds therefore do not expose tracing.
- `native/port/mpconfigport.h:58-63` already enables persistent bytecode load/save and VM cancellation hooks. `native/micropython_embed/py/profile.c:34-37` requires persistent-code-save for tracing, so this prerequisite is already represented in app configuration.
- Upstream profile is included by globbed py/*.c (`native/CMakeLists.txt:159-161`, `native/tests/run_host.sh:7-9`) and source contains call/line/return/exception events (`profile.c:351`, `:403`, `:410`, `:421`). Enabling the macro and regenerating all port/qstr/source artifacts is necessary; changing only an ignored generated header is insufficient.
- Frame attributes include f_back/f_code/f_globals/f_lasti/f_lineno (`profile.c:220-247`); code metadata includes filename/function name (`:160-167`). This supports accurate frame/line/stack identity.
- f_locals is absent. `profile.c:197` itself marks its dict_locals assignment as incorrect, and `co_names` currently returns that dictionary (`:169-170`). Do not treat it as reliable named local-variable inspection. `mp_code_state_t.state` contains VM slots (`py/bc.h:232-254`), but reliable name/slot mapping needs compiler debug metadata and tests. This remains concrete additional work for named locals and frame-aware expression evaluation.

Recommended implementation scope to plan as a separately verifiable Python debug deliverable:

1. Compile the pinned runtime with tracing support consistently across OHOS, Android and desktop; ensure normal run behavior and .mpy compatibility remain correct. Use an app-native trace callback installed before module execution, not source rewriting that shifts user line numbers.
2. Introduce an app-owned native debug session ID/control object with bounded event queue and commands. Maintain explicit states preparing/running/paused/stopping/finished. Commands cover breakpoint set updates, pause, continue, step into/over/out and stop. Track frame depth for step policies. Breakpoints use normalized owned file+1-based executable line; distinguish unbound lines from actual hits.
3. At a real bytecode line event, evaluate step/breakpoint policy and pause the VM worker using a condition/event wait. Keep ArkTS/UI thread free. Pause wait must wake on stop/disposal; reuse cancellation semantics and release every token/session exactly once. Native command handling must not require the runtime execution mutex held by the paused VM, or continue/stop will deadlock.
4. Return line/frame/stack metadata and bounded safe snapshots of available globals through a separate poll/event transport. Never serialize raw frame/VM pointers to Dart or access live VM objects from the UI/platform thread. Avoid arbitrary user repr/evaluation merely to display a value; cap depth/size and handle cycles.
5. Add named-local metadata and a carefully defined paused-frame evaluator if those capabilities are included. Existing settrace alone does not implement them. Do not advertise locals/watch/evaluation until host and OHOS evidence proves them; do not silently substitute globals for locals.
6. Preserve ProgramRunner for ordinary execution. Python adds native/FFI/channel debug capability reporting and session adapter; C owns any shared gutter/toolbar/panel contract. App-owned tools can expose real debug session controls inline while shared editor UI is coordinated. A real debug console consumes real events/evaluation responses; a run log remains a run log.

No host process spawning, external debugpy/CPython daemon, network sockets or internet service is required by this design. It is an engineering inference from vendored upstream tracing and the existing async native VM transport, not a tested feature. A native proof must validate line-loop behavior (the upstream line event is emitted when line changes at `profile.c:415`), generator/coroutine/exception stepping and .mpy trace metadata before committing to release capabilities. Same-line tight loops and blocking native I/O must retain responsive stop even when they do not emit new line events.

### 8. Meaningful validation plan

No checks below were executed in planning. They are gates for implementation, with host/UI/device evidence kept separate.

Existing regression anchors:

- `test/python_app_test.dart:178-209`: saved-file syntax channel source/project/entry and native compiler error propagation.
- `test/python_tools_page_test.dart:49`: existing 360x800 and 1200x800 matrix. Current `:79-100` explicitly expects secondary-page navigation and needs replacement by direct tools assertions.
- `test/python_tools_page_test.dart:115`: compile/stop, with actual filesystem artifact discovery and cancellation completion; `:203` exercises syntax/run.
- `native/tests/smoke.c:122-129`: real compile-only no-file-side-effect and compile-error checks.
- `native/tests/ohos_channel_test.cjs:292`: native/platform doubles assert exact source/input/heap/paths and syntax compileOnly. This is channel evidence, not device execution.
- `test/python_lifecycle_test.dart:111`: real-library cancellation/cleanup/artifact group, conditional on real library; keep skip counts explicit.

Required new coverage:

| Gate | Cases that establish behavior |
| --- | --- |
| Source analysis/channel | Disk contains valid text but unsaved snapshot is invalid, then reverse; assert exact source text/path/project and compileOnly; unsaved nonexistent entry; empty source; `.mpy` excluded; backend missing, malformed result and error produce unavailableReason. |
| Native syntax/side effects | Real native compiler catches multiline syntax and indentation errors at actual reported line; source containing open/write/print/input/import side effects does not execute or resolve imports; original files/input unchanged. |
| Offset parser | Windows drive/path spaces, OHOS absolute paths, Unicode, astral emoji before error, LF/CRLF/CR preserved, blank/last/trailing-newline/EOF lines, missing/out-of-range line, malformed traceback, messages with colons, multiple frames; full-line UTF-16 ranges match exact snapshot; stdout resembling traceback ignored. |
| Revision/races | Complete old invalid analysis after newer valid snapshot; switch projects/files, close/reopen, edit dependency buffer and dispose while pending; core rejects stale results and clears markers. Selection-only changes do not compile. |
| Busy/lifetime | Start a real long run; diagnostics return busy promptly without native queue growth, and latest text is analyzed once after exit/stop. Early run handle does not release VM gate. Run failure, cancel, completion and disposal release exactly once; analyzer never cancels user program. |
| Tools narrow/wide | 360x800 and 1200x800 using real temporary projects, long project/file/module names; actions work on the tools tab without pushing PythonToolsPage; exactly one Scaffold/AppBar; project identity/file selection, visible status and separate stdout/stderr/diagnostic output; no render exceptions. Also large text scale and keyboard-inset/short viewport. |
| Tools state | Empty/missing/cloud projects; no files; bytecode disables source checks but permits run; scan generation/selection races; operation disablement; stop pending until real completion; module import/install errors; shared offline utility and terminal callback remain reachable. |
| Shared editor | C owner verifies wave styles preserve syntax highlighting, Problems jumps to correct snapshot offsets, narrow/wide panel fit, terminal touch/focus/session/cancel regressions and no online fallback. App verifies real Python analyzer registration rather than testing only a fake provider. |
| Debug native | Actual breakpoint halts before target statement; continue, pause, step into/over/out across nested functions, imports, generators and exceptions; stack identity; non-executable breakpoint state; stop from running and paused; no event overflow deadlock; second run succeeds; ordinary runs remain unaffected; .mpy compatibility. Named locals/watch/evaluation require independent true-value tests if advertised. |
| Debug transport/UI | Commands remain responsive while native VM is paused; expired/unknown/duplicate IDs rejected; stale events cannot update new sessions; cleanup after native throw/disposal; 360x800/1200x800 real controls and paused-line marker. Native stdout buffering must not be mistaken for a hang or fake live stream. |
| Offline | No login/network/install-from-URL/dev-tunnel paths added; local package/module actions use sandbox files and actual embedded VM; missing backend cannot trigger online fallback. |
| OHOS acceptance | Build final native library/HAP, verify ArkTS source parity, install final signed artifact on real target; exercise unsaved invalid source underline/Problems navigation, inline tools/check/compile/run/stop, local module imports, and any real debug session. Record artifact/library hashes, device/runtime identity and individual results. Host DLL/channel/widget tests cannot close this gate or all-example acceptance. |

Focused commands after implementation: `flutter test --no-pub test/python_app_test.dart test/python_tools_page_test.dart test/offline_regression_test.dart`; source/parser/debug tests added by implementation; `node native/tests/ohos_channel_test.cjs`; real native `sh native/tests/run_host.sh`; then `flutter analyze --no-pub` and `flutter test --no-pub`. Use project-approved Flutter/OHOS executable paths, and serialize Pub/build operations per package. Debug native work needs regenerated runtime builds before tests; a stale generated embed is not current source evidence.

### 9. Preexisting dirty work and provenance

Parent supplied this dirty-state inventory during research: `lib/main.dart` already registers toolsTabBuilder; `lib/python_tools_page.dart` already has the ToolsGrid card; `test/python_tools_page_test.dart` already adds its navigation regression; `test/startup_test.dart` has preexisting startup changes; native startup docs/EntryAbility/Index/AgreementReader are dirty. Parent explicitly reported `lib/app_startup.dart` unchanged. These are parent-reported HEAD-diff facts, not independently established by this researcher; the researcher role prohibits git operations.

Current content/metadata observed without git:

| File | Last write (local) | SHA256 at audit |
| --- | --- | --- |
| `lib/main.dart` | 2026-10-18 21:54:21 | `308B0C310B1D62E1F639328F6F695036A34079A11D2F85E6487FE9B1757084EB` |
| `lib/python_tools_page.dart` | 2026-10-18 21:53:24 | `42F4242F385F2E74729915472E9FF3BFEAAFCF41EDB53DC5C1295A9D01252D43` |
| `lib/python_runner.dart` | 2026-10-15 18:48:51 | `FCEA8D69F306967216DE983F24EE8BCA7B16486ED9422A8229A872D8285CEB50` |
| `lib/python_terminal.dart` | 2026-10-15 19:18:45 | `2FB319A807E26C84D356D28AF1BC13B245CE266C877A9A90DE8733A415A5C7DF` |
| `lib/app_startup.dart` | 2026-10-01 07:29:54 | `F73DB7732F5536DB86F101DFCA3A2A00729AACCC2C3A66A841CE3C9FCA12438A` |
| `test/python_tools_page_test.dart` | 2026-10-18 21:55:04 | `69180514A054852FD2433DC068C26B8E61B49AF628DBB335E6D393DC4897B18C` |
| `test/startup_test.dart` | not separately inventoried | `8B04BA8F3E762299412C279F079DA0BEA679AF19AEA9C639BAA8A6BB9A73D90A` |

The four queried shared paths `file_explorer.dart`, `project_history.dart`, `file_explorer_state_test.dart`, `project_history_concurrency_test.dart` all had last-write 2026-10-22 10:22:10. A timestamp cannot identify their writer. This research agent and its parent session did not write them (parent ownership-message confirms that). Preserve existing narrow persistence changes and let C coordinate attribution rather than reverting them.

### 10. External references and related specs

Primary documentation was retrieved read-only through Invoke-WebRequest after web search/open returned empty tool content:

- MicroPython versioned sys docs, `https://docs.micropython.org/en/v1.24.0/library/sys.html`: settrace traces bytecode and needs a custom MICROPY_PY_SYS_SETTRACE build; documentation warns of performance impact. Local pinned v1.24.1 equivalent: `native/third_party/micropython/docs/library/sys.rst:46-53`. This project pins MicroPython 1.24.1/ecfdd5d (`native/README.md:3`); do not silently upgrade to latest while enabling debug.
- VS Code debugging guide, `https://code.visualstudio.com/docs/debugtest/debugging`: Debug Console displays debugger output/evaluates expressions; breakpoint/toolbar behavior provides a comparison target, not an available Python adapter in this project.
- VS Code port forwarding guide, `https://code.visualstudio.com/docs/editor/port-forwarding`: Ports forwarding uses dev tunnels/internet sharing and can require GitHub sign-in. Those network flows conflict with standalone offline requirements; a future local listener inventory is a different, app-owned capability.

Related local specs read: `.trellis/workflow.md` (planning gate), `.agents/skills/trellis-brainstorm/SKILL.md`, `.trellis/spec/frontend/index.md`, `directory-structure.md`, `python-workflow.md`, `component-guidelines.md`, `state-management.md`, `quality-guidelines.md`, `type-safety.md`, and backend `index.md`, `python-ffi.md`, `native-python-runtime.md`. Lifecycle `hook-guidelines.md` was searched for disposal/async contracts. The native runtime spec explicitly differentiates channel/host evidence from installed OHOS acceptance and requires paired ArkTS parity.

## Caveats / Not Found

- Planning only. No implementation, analyzer/debug build, tests, actual native execution or current OHOS device verification was performed by this researcher.
- Shared diagnostic API was newly frozen during the audit and source implementation was absent at last inspection. Recheck published source before adapter implementation; C owns integration.
- Upstream settrace makes in-process debugging technically plausible, not already working. Runtime config/generated artifacts, control/event transport, bounded safe snapshots, core UI and device proof remain implementation work. Named locals and paused-frame evaluation lack a reliable current API.
- Native syntax positions are line-only. The frozen shared offset API can truthfully represent a full reported line, but exact token columns require new structured parser/lexer location support, not a guessed column.
- Python's VM mutex and completion-buffered output are real scheduling/UX constraints. Stale result checks alone do not solve queued checks behind an active run, and Stream<String> alone does not prove live native output.
- Existing parent-reported dirty diffs are preserved. Current snapshots/metadata do not establish git ownership. No attempt was made to attribute another session's shared-core modifications from timestamps.
- Full curriculum expansion, common modules/local pip-compatible package design and all-example OHOS verification are parallel Python research/child responsibilities. This file supplies their tools/runner contracts and integration gates; it does not claim those deliverables complete.
