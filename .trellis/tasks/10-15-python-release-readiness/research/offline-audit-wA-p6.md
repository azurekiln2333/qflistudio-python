# Offline storefront & terminal audit (wA:p6)

Scope owner: offline storefront/profile integration audit and tests.
Owned paths: `lib/main.dart`, new offline regression/integration tests,
task-local offline research, minimal OHOS manifest offline cleanup
(coordinate update 2026-10-15).
Read-only: `D:/MyNewProjects/qfli_studio_core`, sibling `qfli_*` apps.

## Confirmed offline policy chain

- `pythonProfile.isOffline = true` (lib/main.dart) → `offlineOnly` defaults to
  `true` (qfli_studio_core/lib/services/studio_profile.dart:111).
- Gating verified at:
  - home tabs: Projects tab scopes drop `_ProjectScope.cloud`
    (home_page.dart:307-309); cloud refresh early-return (home_page.dart:700);
    cloud project filter (home_page.dart:547-551); "new cloud project" popup
    hidden (home_page.dart:430).
  - content tabs: `LocalTutorialsTab` instead of the networked `TutorialsTab`
    (home_page.dart:102, 162-164).
  - profile: login header, account stats, check-in/points, admin pages, ICP
    footer all omitted (profile_page.dart:81, 97-104, 217-228).
  - editor: AI assistant and online terminal menu items hidden
    (editor_page.dart:1625, 1646); cloud sync skipped (editor_page.dart:203);
    online-run fallbacks disabled (editor_page.dart:1001, 1092, 1116);
    `onlineEnabled: false` on TerminalPane (editor_page.dart:1881).
- Startup is local-only: `AppBootstrap.run` loads ProjectStore/AuthStore/
  SettingsStore from local JSON (splash_screen.dart:46-79). `AuthStore.load`
  reads `auth.json` and only ever stores a token from the official origin
  (auth_store.dart); it issues **no** network request at load time. Confirmed
  no release-time egress on the normal path.

## Findings

### F1 (owned, fixed) — Python never registered a terminal command delegate
`pythonProfile` set no `StudioProfile.terminalCommandDelegate`, while both
terminal surfaces resolve language tools exclusively through it:
- standalone terminal: termax_terminal_page.dart:42, 109
- editor terminal: terminal_pane.dart:431-440
Effect: typing `python main.py` in either terminal fell through
`SandboxShellBackend.runExternal` to the honest-but-wrong
"内置终端不支持该命令" message; Python tools were **not reachable** from the
terminal. Fixed in `lib/main.dart` by registering `_pythonTerminalDelegate`.

### F2 (shared core, reported — not edited) — Git menu item not offline-gated
`qfli_studio_core/lib/editor/editor_page.dart:1586-1596` exposes the `Git`
popup menu item **unconditionally** (only `ai` and `online_terminal` at
1625/1646 are gated). `_openGit()` (editor_page.dart:590) pushes
`GitPage`, which on desktop runs the real `git` CLI
(`git push`/`pull`/`remote add`, git_service.dart:66-71) — a real network
egress surface reachable from a normal offline Python app navigation path.
Cloud projects are filtered out of the offline store (F-chain above), so the
cloud branch of GitPage is not reachable, but the local desktop branch is.
Suggested minimal fix (coordinator-owned shared file):
  wrap the `PopupMenuItem(value: 'git', ...)` block in
  `if (StudioProfile.current?.offlineOnly != true)`.
No core edit performed.

### F3 (shared core, reported — cosmetic) — About dialog hardcodes QFLIStudio+
`settings_page.dart:352` `showQfliAbout` hardcodes applicationName
`QFLIStudio+`; the offline Python app shows the wrong product name. Local
text only, no network. Suggested: read `StudioProfile.current?.appTitle`.

### F4 (owned, coordinated) — OHOS release manifest offline cleanup
`ohos/entry/src/main/module.json5`:
- `requestPermissions` includes `ohos.permission.INTERNET`
  (line 43).
- ability metadata `client_id = REPLACE_WITH_AGC_CLIENT_ID` (line ~25).
Evidence:
- The placeholder `client_id` is read by **no** compiled code. The Huawei
  Account Kit path (EntryAbility.ets huawei channel) uses
  `provider.createAuthorizationWithHuaweiIDRequest()` and never consults this
  metadata; the channel is only reachable from `LoginPage`, which the offline
  profile hides. Removing it is safe and removes a storefront red flag.
- INTERNET's only potential consumer is the `AgreementReader` webview (another
  worker's change). `userAgreementUrl`/`privacyPolicyUrl` are empty strings
  (qfli_studio_core/lib/config/agreement_config.dart), so no https agreement
  URL is currently reachable; the ICP footer is hidden offline.

Resolution applied:
- Removed the unused `client_id` metadata block (no code reads it).
- Kept `ohos.permission.INTERNET`, re-formatted to a clean JSON5 literal.
  Rationale: the only consumer is the preserved `AgreementReader` legal-page
  webview, and removing the permission would silently break that surface the
  moment `userAgreementUrl`/`privacyPolicyUrl` are published. No offline
  product surface can reach the network today (verified above), so the
  permission is latent, not a reachable egress. This is a deliberate decision
  point for the coordinator if a stricter privacy posture is preferred —
  removing it is safe *only* while the legal URLs remain empty.

### F5 (owned, verified — no change needed) — Android release has no INTERNET
The coordinator's merged release manifest contains **no** INTERNET permission:
`build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml:29`
lists only the auto-generated
`com.azurekiln.qfli.pyflow.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`.
`android/app/src/main/AndroidManifest.xml` declares no `uses-permission`, and
no release plugin manifest adds one. INTERNET appears only in `src/debug` and
`src/profile` (dev-only, for hot reload). Therefore an
`android/app/src/release/AndroidManifest.xml` with `tools:node="remove"` is
**unnecessary** and was not created (it would be dead configuration).

## Legitimate offline surfaces preserved
- Terminal, offline tools grid (Unicode/Base64/URL/Regex/JSON/Hash/Timestamp/
  UUID/Color), local statistics/audit, recovery, settings, About, local
  tutorials/examples. Privacy/agreement reader code remains intact.

## Terminal hook details (F1 fix)

Implemented in `lib/python_terminal.dart` (owned, new) and registered from
`lib/main.dart` via `terminalCommandDelegate`.

- Claims `python` / `python3` / `micropython` + exactly one script operand.
  Both terminal surfaces (standalone `terminax_terminal_page.dart` and editor
  `terminal_pane.dart`) resolve the hook from the profile, so one registration
  covers both.
- Uses `PythonProgramRunner.run` — the same probe→run path as the Run button,
  including cancellation and `input.txt`.
- **Project root**: `projectRootForScript(script, backend.sandboxRoot,
  workingDirectory: backend.cwd)` walks up from the script to the nearest
  `.qfli/project.json`, **never above `sandboxRoot`**, so a nested `src/main.py`
  reads the project-root `input.txt` while an unrelated project's marker outside
  the sandbox is never adopted. If no in-sandbox marker exists (an unmarked
  folder the user `cd`-ed into), the **current directory (`backend.cwd`)** is the
  root — matching ordinary Python semantics (`cd project; python src/main.py`
  reads `input.txt` from `project/`) and matching the Run button. The cwd is
  adopted only when inside `sandboxRoot`; otherwise the script's own directory is
  the last resort. A marker always wins over cwd.
- **Extra operands are refused**, not dropped: there is no `sys.argv` contract
  in the backend, so `python main.py arg` reports `暂不支持脚本参数` and points at
  `input.txt` rather than running with silently missing argv.
- `-m` / `-c` → honest `暂不支持` message.
- REPL (`python` with no script) → honest message (the backend is pass-anyway, no
  interactive stdin).
- `--version` / `-V` → real version from `PythonProgramRunner.runtimeInfo()`
  (p5's public probe API). Success prints `MicroPython <version>` on **stdout**
  and exits 0; unavailable / probe error / empty version prints the honest
  diagnostic on **stderr** and exits `kProgramNotRunExitCode` (127). No
  fabricated `Python 3` prefix and no invented version. `_report` routes stdout
  vs stderr explicitly and derives the exit status from the channel, so a
  failure can never be rendered as success.

### Test-injection contract
`pythonTerminalDelegate(backend, command, {runner, probeSource})` accepts named
overrides. Production passes neither (default `PythonProgramRunner()` +
`runner.runtimeInfo`). Tests inject
`PythonProgramRunner(transport: PythonNativeTransport.methodChannel)` so the
Windows FFI path is never taken, plus a fake `probeSource` to pin the version
output. Terminal regression tests assert the actual output **channel**
(`stdout` vs `stderr`) and `backend.lastExitCode`, not just matched text, and
are plain `test()` bodies (real async) rather than `testWidgets`, avoiding the
fake-clock hang; widget tests wrap real file IO in `tester.runAsync` with
bounded polling.

## p5 coordination

- Requested and received: p5 added the public `PythonProgramRunner.runtimeInfo()`
  / `PythonRuntimeInfo` API (lib/python_runner.dart). `python_terminal.dart` now
  consumes it and copies **no** private probe logic. No edit was made to
  `python_runner.dart` (p5-owned, concurrently modified).
- Windows `flutter test` for this task runs only owner tests
  (`test/offline_regression_test.dart`) until the FFI/fake-clock fix is in.
