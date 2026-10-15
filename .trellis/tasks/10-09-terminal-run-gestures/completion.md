# 10-09 terminal-run-gestures — completion record

Documentation only. Task owner: `wA:p5` (Python runner/terminal/native scope) under
coordinator review. No source, no commit, no archive by this record. The shared core is
owned by the Java workspace; Python never edited it.

Unless otherwise stated, `research/...` evidence below refers to
`.trellis/tasks/10-15-python-release-readiness/research/`. Final coordinator
checks are full app **91/91**, analyzer **No issues**, real FFI **34/34** and
real C VM **65/65**. Product commits are `77f46d5` and `7286cd9`.
AC6 requires reporting unavailable device evidence, which is done below;
supplemental device observations stay with the release/native tasks. This
terminal presentation/gesture task has no unresolved implementation finding.

## Scope reality (read this with the PRD)

The PRD was written on 2026-10-09 when the terminal/gesture work was expected to be
mostly Python-side. By completion the shared `qfli_studio_core` already provided the
continuous transcript (R2) and the tap/hold Run gestures (R4). The remaining
Python-specific gap was the **title contract** (R3) plus regression coverage. The PRD's
"currently in planning" status and the `wA:p2` pane assignment are historical; see
"PRD corrections" below.

## AC mapping (evidence-backed)

| AC | Requirement | Status | Real evidence |
| --- | --- | --- | --- |
| AC1 | Report what the shared core already provides; identify the Python gap | Met | `research/shared-terminal-compat-wA-p8.md` F2/F3/F4: core `TerminalPane` inline prompt + `EditorPage` tap/long-press already exist; core suites `terminal_pane_test.dart` 25/25, `editor_run_test.dart` 16/16, combined 67/67 + 60/60. Python gap was only the title contract (fixed in `lib/python_runner.dart`). |
| AC2 | Repeated runs append to one transcript; success returns to inline prompt; no app success/exit-0 banner or runtime suffix | Met | Core behavior proven by `terminal_pane_test.dart` (partial-line integrity, scroll retention, session isolation) 25/25 and the core `attachOutput` contract (only nonzero emits `exit code N`; exit 0 stays silent). Python side emits no success prose: `lib/python_runner.dart` `_runControlled`/`_runNative` return `title: fileName` (command label), no version/横幅 suffix — covered by `python_app_test.dart` "标题在受控与旧接线下完全一致（不含版本号）" and "走原生，输出与退出码原样带回". |
| AC3 | Same concise title on controlled and legacy transports; spaces/nested paths identifiable; source and `.mpy` routing retained | Met | `python_app_test.dart`: "标题在受控与旧接线下完全一致（不含版本号）", "标题用项目相对路径，嵌套目录与空格仍然可读" (`python 'pkg/sub dir/my main.py'`), ".mpy 入口使用同一条命令风格标题", "声称支持字节码但没有 runControl 时，.mpy 仍走受控链路". Implementation: `commandLabel()` + `_useFfi || probe.supportsCancellation || isBytecode` routing. |
| AC4 | Tap runs configured/default entry; hold runs the active file once after saving | Met (core-owned) | Core `editor_page.dart` `_runProject` / `_runActiveFile` + `editor_run_test.dart` 16/16 (tap = configured entry; long press = current file, validated for extension + project containment). Python adds no second backend: `lib/main.dart` `_pythonTerminalDelegate` and Run both use `PythonProgramRunner` (wA:p8 F3). No Python-side test duplicates this; it is core-verified. |
| AC5 | Real stdout/stderr + diagnostics + actual exit codes + cancellation; no filtering of Chinese/JDK/version strings | Met | Real native: `python_lifecycle_test.dart` group "real MicroPython lifecycle" (loop/sleep stop → exit 130 + KeyboardInterrupt, pre-start and queued cancellation, token isolation, artifact-without-source run) against the actual Windows `qfli_py_ffi.dll`. Channel/error mapping: `python_app_test.dart` stderr/truncation, `sys.exit(3)`, malformed-result, module-missing. No output filtering is applied anywhere in the runner. |
| AC6 | Python tests/analyze + relevant core terminal/gesture tests pass; unavailable device evidence reported | Met with a device gate | Python focused: `flutter test test/python_ohos_bridge_test.dart test/python_app_test.dart test/python_tools_page_test.dart test/python_lifecycle_test.dart test/python_ffi_test.dart` → **56/56 passed**; `flutter analyze` on owner files → No issues; `node native/tests/ohos_channel_test.cjs` → **20/20**. Core suites per wA:p8 → 67/67 + 60/60. **Not verified:** on-device tap/hold interaction and OHOS device execution — device interaction is pending `wA:p8`; OHOS async worker/cancel/`.mpy` needs the coordinator's fresh `native/build.ps1` + signed HAP + hilog self-check. |

## Tests referenced

Python (`qfli_python`):
- `test/python_app_test.dart` — title contract (controlled/legacy parity, relative/nested/
  spaced paths, `.mpy`), stdout/stderr, exit codes, `input.txt`, module-missing, `runtimeInfo`.
- `test/python_lifecycle_test.dart` — real MicroPython cancellation, token isolation,
  artifact/bytecode execution.
- `test/python_tools_page_test.dart` — compile/stop/syntax workflows at 360x800 and 1200x800.
- `test/python_ffi_test.dart` — FFI loader failure, NUL/overflow rejection, transport choice.
- `test/python_ohos_bridge_test.dart` — only the byte-identical ArkTS copy check.
- `node native/tests/ohos_channel_test.cjs` — real ArkTS handler behavior (20/20).

Core (`qfli_studio_core`, read-only, run by `wA:p8`):
- `test/terminal_pane_test.dart` 25/25, `test/editor_run_test.dart` 16/16,
  `test/terminal_manager_delegate_test.dart` 1/1, `test/sandbox_terminal_test.dart` 25/25,
  plus 60/60 in the compact/input/tab/touch/offline suites.

## PRD corrections (stale → current)

1. **Status.** Confirmed Background says "it is currently in planning". Current: the
   Python-owned work (R3 title contract + focused regressions) is complete; the remaining
   gate is device interaction owned by `wA:p8`, plus coordinator build/commit/archive.
2. **Pane ownership.** Confirmed Background and Key Decisions name `wA:p2` (a former
   `pi-python-terminal` pane) as the assigned worker, and `wE:p2` as the core owner. The
   live assignment for this round is `WA:p5` (Python runner/terminal/native) with the
   coordinator serializing commits, and the shared-core terminal/editor owner is the Java
   workspace coordinator (wA:p8 reported compatibility against core `8731df8`). Treat the
   `wA:p2` / `wE:p2` labels as historical.
3. **"Python still constructs Chinese Run + version titles" (lib/python_runner.dart:286,
   :398; test/python_app_test.dart:228).** No longer true. Titles are now
   `python <project-relative path>` on all paths, and the runner tests assert that
   contract; the cited lines/assertions were replaced. The version number is no longer in
   the title — it is exposed via the public `runtimeInfo()` for surfaces that want it.
4. **Native stdin buffered / no interactive stdin.** Still true and unchanged; not a gap
   for this task (R5 only requires preserving real stdout/stderr, exit codes and
   cancellation, which the lifecycle tests cover).

## Out of scope / left to others

- On-device tap/hold and standalone-terminal interaction: `wA:p8` (device interaction
  pending; Android UI currently active there).
- Fresh OHOS `.so` copy, signed HAP, native device self-check: coordinator/root.
- **Final HAP packaging (root-owned).** Root's final audit found an old untracked
  `ohos/entry/libs/x86_64/libqfli_py.so` with no cancellation exports, included in the
  arm64 HAP although there is no x86_64 Flutter/app payload. Root owns the packaging fix
  and metadata cleanup; this task does not touch any native/SO artifact and does not
  claim the HAP is correct until root repackages. The arm64 `libqfli_py.so` built from
  the frozen sources carries the cancellation/bytecode exports.
- Commit and Trellis archive: root.
