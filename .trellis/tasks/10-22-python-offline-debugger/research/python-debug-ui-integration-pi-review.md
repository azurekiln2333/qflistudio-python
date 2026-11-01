# Python debug UI integration — read-only review

Date: 2026-10-26. Owner: `/root/python_debug_ui_integration`. Read-only.

Scope: trace the shipped product path from the editor debug UI through the shared
`EditorDebugController`, the Python `StudioDebugger` adapter, the native debugger
C ABI, and the OHOS bridge. Check breakpoints, pause, step into/over/out,
continue, stop, call-stack/locals, log visibility and failure cleanup. Name any
product wiring gap with exact paths and lines.

No source file was edited. No Dart, Flutter, analyzer, native build, SDK, WSL,
HAP, signature, device, emulator or channel publish was started. The only
execution performed was a Python standard-library ELF dynamic-symbol read of the
two already-committed OHOS `.so` files (static file read, no toolchain, no
process beyond the Python interpreter).

This note is the single file this worker owns:
`.trellis/tasks/10-22-python-offline-debugger/research/python-debug-ui-integration-pi-review.md`.
Other workers' files are untouched.

## 1. Wiring chain as it actually exists

| Hop | File:line | What it does |
| --- | --- | --- |
| Profile registration | `lib/main.dart:30` | `debugger: PythonDebugger()` inside `pythonProfile` |
| Profile runtime claim | `lib/main.dart:36-37` | `runtimeKind: 'micropython-native-and-desktop'`, `runtimeStatus: 'available'` (both unconditional) |
| Controller creation | `qfli_studio_core/lib/editor/editor_page.dart:271` | `EditorDebugController(editor: ...)`, provider defaults to `StudioProfile.current?.debugger` |
| Controller listener | `editor_page.dart:276` | `_debugger.addListener(_onDebuggerChanged)` |
| Pause auto-navigate | `editor_page.dart:1712-1724` | on a new pause token, `navigate(selectedFrame)` |
| Start entry | `editor_page.dart:1756-1767` | `_startDebug(bool)` → `_debugger.start(stopOnEntry:)` |
| Debug panel mount | `editor_page.dart:1805-1812` | `_BottomPanel.debug => EditorDebugPanel(...)` |
| Output panel mount | `editor_page.dart:1814-1818` | `EditorOutputPanel(output: _output, debug: _debugger)` |
| Debug console mount | `editor_page.dart:1819-1823` | `EditorDebugConsolePanel(...)` |
| Panel open entry | `editor_page.dart:2026-2030`, `2235-2244` | menu/selector values `output`, `debug`, `debug_console` |
| Gutter mount | `editor_page.dart:3166-3172` | `EditorDebugGutter(debug: _debugger, file: open, notifier: ...)` |
| Start button enable | `editor_debug_widgets.dart:92-104` | enabled when `!busy && !runBusy && debugger != null && file != null` |
| Breakpoint toggle UI | `editor_debug_widgets.dart:143-162`, `232-...` (gutter) | button and gutter tap call `debug.toggleBreakpoint` |
| Command buttons | `editor_debug_widgets.dart:105-133`, `240-250` | continue always; pause/step-over/step-in/step-out gated on capabilities |
| Locals panel | `editor_debug_widgets.dart:219-235` | read-only `frame.locals` |
| stdout/stderr view | `qfli_studio_core/lib/editor/editor_output_panel.dart:104-116` | renders `snapshot.stdout` / `snapshot.stderr` |
| Console/diagnostics view | `editor_output_panel.dart:146-172` | renders `snapshot.console` and `snapshot.message` |
| Controller commands | `editor_debug_controller.dart:532-600` | `canCommand` + `command` (token and thread plumbing) |
| Controller breakpoints | `editor_debug_controller.dart:174-289` | `canToggleBreakpoint`, `toggleBreakpoint` |
| Controller start | `editor_debug_controller.dart:290-470` | saves buffers when snapshots unsupported, then `provider.launch` |
| Launch error surface | `editor_debug_controller.dart:432` | `_error = '无法启动离线调试：$error'` shown by the panel |
| Controller stop | `editor_debug_controller.dart:772-800` | `_requestStop` → `session.stop()` → await `finished` |
| Controller dispose | `editor_debug_controller.dart:735-770` | `_disposeSession` with bounded retry |
| Adapter capabilities | `lib/python_debugger.dart:33-44` | live breakpoints, exit-only output, step in/over/out, stop-on-entry, stack, variables; **no** `supportsPause` |
| Adapter launch | `lib/python_debugger.dart:48-88` | rejects unsaved snapshots and NUL; resolves entry; acquires runtime lease |
| Adapter command | `lib/python_debugger.dart:499-534` | resume=1, stepInto=2, stepOver=3, stepOut=4, `pause` throws |
| Adapter stop | `lib/python_debugger.dart:536-561` | `_handle.command(0, 5)` retried every 200 ms |
| FFI handle creation | `lib/python_debugger_ffi.dart:42-64` | capability gate `capabilities() & 31 != 31` |
| FFI library load | `lib/python_debugger_ffi.dart:255-267` | `_Bindings(openPythonNativeLibrary(path))` wrapped as `QFLI_PY_DEBUG_UNAVAILABLE` |
| Native library choice | `lib/python_native_library.dart:8-33` | OHOS/Android → `DynamicLibrary.open('libqfli_py.so')`; desktop → `qfli_py_ffi.dll` |
| Native debugger ABI | `native/src/qfli_py_debug.c:174-...` | `state_event`, `pause_event`, `qfli_py_debug_command`, `qfli_py_debug_set_breakpoints` |
| Native pause reasons | `native/src/qfli_py_debug.c:608-632` | `entry`, `breakpoint`, `step`; state set to `DEBUG_PAUSED` before `pause_event` |
| OHOS channel | `ohos/entry/src/main/ets/plugins/QfliPyNative.ets:517-560` | handles `available`, `prepareRun`, `cancel`, `run`, `checkSyntax`, `compile`; everything else `notImplemented()` |
| Build inputs | `native/android/CMakeLists.txt:29`, `native/desktop/CMakeLists.txt:25`, `native/CMakeLists.txt:209` | all three compile `qfli_py_debug.c` |

## 2. Capability matrix (as wired, desktop)

| Feature | UI | Adapter | Native | Verdict |
| --- | --- | --- | --- | --- |
| Breakpoints | gutter + button, live mode (`editor_debug_widgets.dart:143-162`) | `setBreakpoints` → `_replaceBreakpoints` (`python_debugger.dart:471-497`) | `qfli_py_debug_set_breakpoints` (`qfli_py_debug.c:261-291`) accepts while running, rejects only when terminated | Wired |
| Verified status | `pending` / `verified` / `rejected` marks (`_DebugGutterPainter`) | sets `verified` only on `reason == 'breakpoint'` at the exact line (`python_debugger.dart:281-292`) | emits `reason:"breakpoint"` (`qfli_py_debug.c:613-615`) | String match is exact; wired |
| Continue | button, always shown (`editor_debug_widgets.dart:105`) | native command 1 (`python_debugger.dart:519`) | `QFLI_PY_DEBUG_CONTINUE`, requires matching generation + observed generation (`qfli_py_debug.c:293-315`) | Wired |
| Step in/over/out | buttons gated on capabilities (`:113-133`) | native 2/3/4 (`:520-522`) | same generation gate | Wired |
| Pause | hidden because `supportsPause` is absent (`python_debugger.dart:33-44`), so `editor_debug_widgets.dart:111` is false | `command(pause)` throws `UnsupportedError` (`:505`) | stop only | Not offered; consistent, but no async pause exists at all |
| Stop | button (`:135-141`) | `_handle.command(0, 5)` (`:545`) | `QFLI_PY_DEBUG_STOP_REQUEST` ignores generation | Wired; generation 0 is accepted by design |
| Call stack | frames list (`:195-217`) | `_frame`, id prefix `<generation>:` (`python_debugger.dart:306-336`) | `frame_snapshot` writes matching ids (`qfli_py_debug.c:484-495`) | Wired |
| Locals | read-only tree (`:219-235`) | `_variable`, dict `key`/`item` mapping (`python_debugger.dart:351-421`) | `value_snapshot` emits the same shape (`qfli_py_debug.c:358-455`) | Wired; schema matches |
| stdout/stderr | Output panel | filled only in `_finish` from the native result (`python_debugger.dart:572-609`) | returns on execute completion | Wired; `exitOnly` is truthful (`editor_debug_widgets.dart:182`) |
| Diagnostics | Debug Console | `_console` tail, 8 Ki (`python_debugger.dart:435-439`) | reasons plus dropped-event notes | Wired |

Additional checks that came out clean (recorded so they are not re-litigated):

- `sessionId` is quoted in the native envelope, so the Dart `_string` decode is
  correct (`qfli_py_debug.c:325`).
- The terminal event carries `exitCode` and `traceDisabled` because
  `session->state = DEBUG_TERMINATED` is assigned before `state_event`
  (`qfli_py_debug.c:698-703`).
- `state_name` only ever returns `created|running|paused|terminated`, matching the
  Dart `_state` whitelist (`qfli_py_debug.c:114-124`).
- Stop while paused is not a generation bug: native ignores `generation` for
  `QFLI_PY_DEBUG_STOP_REQUEST` (`qfli_py_debug.c:293-311`).

## 3. Product wiring gaps

### G1 (blocking, device only): OHOS binaries do not contain the debugger ABI

Evidence, static ELF dynamic-symbol read of the committed device libraries:

- `ohos/entry/libs/arm64-v8a/libqfli_py.so`: 1439 dynamic symbols, **0** matching
  `qfli_py_debug*`; `qfli_py_run` and `qfli_py_execute` are present.
- `ohos/entry/libs/x86_64/libqfli_py.so`: 1434 dynamic symbols, **0** matching
  `qfli_py_debug*`; same run/execute exports.
- `ohos/entry/build/default/intermediates/libs/default/x86_64/libqfli_py.so`:
  same, 0 debug symbols.
- Contrast: `native/build/windows/qfli_py_ffi.dll` and
  `build/qfli_py_ffi-debugger-stable.dll` contain
  `qfli_py_debug_create`, `qfli_py_debug_capabilities`, `qfli_py_debug_command`,
  `qfli_py_debug_poll_json`; `native/build/host/libqfli_py_debug_test.so`
  exports all 12 `qfli_py_debug_*` entries.

Why this is a product gap and not a test gap: `lib/python_native_library.dart:11-12`
opens `libqfli_py.so` on OHOS, then `lib/python_debugger_ffi.dart:262` builds
`_Bindings`, whose constructor performs every `lookupFunction`. A missing symbol
throws there and is reported as `QFLI_PY_DEBUG_UNAVAILABLE` / "could not be
loaded" (`python_debugger_ffi.dart:263-267`). The `capabilities() & 31` gate at
`python_debugger_ffi.dart:45` never even runs.

Critically, the OHOS build has no source CMake under the app:
`ohos/entry/src/main/cpp` does not exist; the device libraries are committed
prebuilts. So the debugger C file is compiled for Android and desktop
(`native/android/CMakeLists.txt:29`, `native/desktop/CMakeLists.txt:25`,
`native/CMakeLists.txt:209`) but the shipped OHOS prebuilts predate or omit it.

This matches the manifest's own open gate ("both OHOS ABI debugger builds" in
`native-debugger-evidence-manifest.json:openGates`). It is still open.

Minimal recommendation (not applied; parent coordinates): rebuild the OHOS
`libqfli_py.so` from the same CMake that includes `src/qfli_py_debug.c`, or ship
a device-side capability probe. Do not claim device debug until the symbols are
present.

### G2 (product-visible): nothing gates or pre-checks debug availability on device

`lib/main.dart:36-37` claims `runtimeStatus: 'available'` with no platform term.
`editor_debug_widgets.dart:92-104` enables 开始调试 whenever `debugger != null`,
and `debugger` is always non-null for this profile. So on an OHOS device the
panel offers Debug, the user presses start, and the only feedback is a launch
error string set by the shared controller (`editor_debug_controller.dart:432`,
`无法启动离线调试：...`) after the adapter load already failed.

Minimal recommendation: surface the `StudioDebugger` availability (for example a
capability probe over `openPythonNativeLibrary` + symbol check) before the panel
enables start, or have the profile expose a device-disabled debugger. This is a
UI/gating decision in the shared core, so it needs parent coordination.

### G3 (device parity): Run and Debug use different transports

- Run on device: `qfli_py/native` MethodChannel → `QfliPyNative.ets` → ArkTS →
  `libqfli_py.so` napi (`QfliPyNative.ets:94`, `:517-620`;
  `python_runner.dart:78`).
- Debug on device: direct in-process Dart FFI `DynamicLibrary.open('libqfli_py.so')`
  (`python_native_library.dart:11-12`), executing the VM on a separate isolate in
  the Flutter engine process.

The device channel exposes only `available`, `prepareRun`, `cancel`, `run`,
`checkSyntax`, `compile` and returns `notImplemented()` for anything else
(`QfliPyNative.ets:559`). So there is no channel fallback for debug. Even if
G1 were fixed, device debug would exercise a path that has never been built or
verified, distinct from device Run. No record claims it.

### G4 (truthfulness, low severity): verified breakpoint status is hit-only

`lib/python_debugger.dart:281-292` upgrades a breakpoint to `verified` only when a
pause arrives at that exact file and line with `reason == 'breakpoint'`. A
breakpoint on a line that never executes stays `pending` forever. Native has no
"resolved but unbound line" reporting (`qfli_py_debug.c:613-615`). The UI shows
待验证 (`editor_debug_widgets.dart:254-262`). This is defensible but should be
read as "not yet hit", not "invalid".

### G5 (documentation mismatch, non-functional)

`editor_debug_widgets.dart:178-183` prints the output-delivery sentence from
`capabilities.outputDelivery`, which for Python is `exitOnly` and therefore
accurate. The gap is only that `lib/python_debugger.dart:35` plus the panel text
are the sole place a user learns there is no live output while paused; the
`console` stream does update during a session but is on a different tab. No code
change implied.

## 4. Failure cleanup trace (as wired)

- Stop request: `editor_debug_controller.dart:772-790` sets `stopRequested`, then
  `session.stop()`; `python_debugger.dart:536-570` dispatches native stop and
  retries every 200 ms while the worker still runs.
- Completion: `DebugSession.done` completes only after
  `_cleanupAndFinish` releases the native handle and the runtime lease
  (`python_debugger.dart:611-637`). A release failure keeps the lease, sets
  `stopping`, and returns without completing
  (`python_debugger.dart:615-628`); `dispose()` retries
  (`python_debugger.dart:639-647`).
- Controller disposal: `editor_debug_controller.dart:735-770` retries a closed
  cleanup up to `_maxCloseDisposalAttempts = 3` with a 50 ms delay, and reports
  `调试器清理尚未完成` rather than faking release.
- Shared UI: `snapshot.isTerminal` is only reachable after real worker return
  (`debug_session.dart:267-269`), which matches `python_debugger.dart:633-635`.

No gap found in the failure-cleanup path. It retains the lease on failure and
never manufactures a terminal state.

## 5. Historical evidence versus current unrun

Historical (recorded before the host restriction; not re-verified now):

- `python-debugger-cost.json`, `python-native-debugger.json`,
  `python-native-debugger-posix.json`, `python-stdlib-with-debugger.json`, with
  the hand-off manifest `native-debugger-evidence-manifest.json` (date 2026-10-23,
  `deviceVerified: false`).
- `product-adapter.md` records one serialized window that passed 28/28 focused
  tests, then states that later source changes (failed-Stop retry, disposal
  cache, four new regressions, FFI arenas) had **not** been run.
- `native-debugger-evidence-manifest.json:artifacts` pins the desktop DLLs by
  SHA256 and lists `both OHOS ABI debugger builds` and `installed OHOS debugger
  verification` as open gates.

Current, unrun by this worker:

- Every Dart/Flutter test, `dart analyze`, the owned-process controls, the
  bounded host runner, native builds, Android/OHOS target builds, HAP/signing,
  and any device or emulator interaction.

So: the desktop wiring above is a source-level reading plus historical test
records. The device picture is source-level plus a static symbol read of the
committed prebuilts. No runtime result is claimed for either.

## 6. What this review did and did not do

Did: read source with line citations; statically parse the ELF dynamic symbol
tables of the two committed OHOS `.so` files and three host binaries with Python
standard library only.

Did not: edit any file; run Dart, Flutter, the analyzer, a native build, an SDK,
WSL, HAP or signature step, a device or emulator; publish any channel message.
