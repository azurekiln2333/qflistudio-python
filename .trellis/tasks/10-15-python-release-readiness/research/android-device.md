# Android device evidence — wA:p8

Owner: Android device testing + debug build for task
`.trellis/tasks/10-15-python-release-readiness`.
cwd `D:/MyNewProjects/qfli_python`. No product code changes; no stage/commit.
Target device only: `adb-d361e7a0-gqqQSM (2)._adb-tls-connect._tcp`
(OPD2413, Android 16). The other transport id `192.168.68.236:35991` is the
same physical OPPO; I never used it.
`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`.

## Builds (real, this session)

| Artifact | Result | Size | SHA256 |
|---|---|---|---|
| `app-release.apk` (first, 19:12:37 — **stale, historical**) | `√ Built` | 72,878,894 | `C65082C0…3AB6811`→ see below |
| `app-debug.apk` (first, 19:14:45 — **stale, historical**) | `√ Built` | 154,050,333 | `17AE534E…E558FFE` |
| `app-debug.apk` (**final**, 19:32:53, includes p6 cwd fix) | `√ Built` (19.8s incremental) | 154,050,333 | `362BC9269C7404983C555F91FE782C534EE8B28F6D843ECEA072D315BC9E7860` |
| `app-release.apk` (**final**, 19:37:37, coordinator build) | `√ Built` (93.1s) | 72,878,894 | `2F160DB71DB1D824D413610ADE69B7D7C7570A84526B8B143C1FCD5263AB6811` |

- The **final** debug APK (19:32:53) is newer than every source
  (`python_terminal.dart` 19:18:45, `python_runner.dart` 18:48:51,
  `main.dart` 18:41:22), so it contains p6's final cwd fix. The earlier debug
  APK (19:14:45) predated that fix and is historical only.
- Release first-build hash `C65082C0066350D0E631092B9C5C50EB06F0905119725436983129B857C03F55`
  is **historical**; the final release hash is the `2F160DB7…` row above.
- Release build completed before the debug build started; no concurrent use of
  the shared `build/` directory. No Android build was run after the coordinator's
  final release build.

## Install + launch (debug, final APK)

- `adb -s <target> install -r app-debug.apk` → `Performing Streamed Install` /
  `Success` (exit 0). Logs: `install-debug.log`, `install-debug-2.log`.
- Installed `com.azurekiln.qfli.pyflow` versionName 1.0.0, versionCode 1,
  minSdk 24, targetSdk 36.
- Launched `.MainActivity`; verified real focus
  (`mCurrentFocus=...pyflow/com.azurekiln.qfli.pyflow.MainActivity`).

## Native self-check 46/46 (debug build, real device) — PASS

`QfliPySelfCheck` is debug-only (`src/debug` runs the cases; `src/release` and
`src/profile` are `fun start() = Unit`). Captured live after
`logcat -c -s QfliPyNative:V` + our own force-stop/relaunch (cleared only the
app's own tag; no peer logs cleared):

```
I QfliPyNative: Loaded MicroPython 1.24.1 (ecfdd5d)
… 46 × "I QfliPyNative: PASS <case>"
I QfliPyNative: Native self-check passed 46/46
```

- **46 PASS, 0 FAIL**, tally `Native self-check passed 46/46`, on both the
  first debug APK and the **final** debug APK (with p6 cwd fix).
- Real VM version `MicroPython 1.24.1 (ecfdd5d)`.
- Logs: `native-selfcheck-debug.log`, `native-selfcheck-debug-2.log`.
- (A naive `Select-String FAIL` shows 1 substring false-positive on the case
  name `failed-compile-retains-mpy`, which is itself a PASS.)

## On-device audit project (app-registered; user data preserved)

Real storage resolved from `run-as` (not invented):
`/data/user/0/com.azurekiln.qfli.pyflow/files` → `projects/pythonProjects/<name>/`.

- Pre-existing user project `tttt` (id `hn8ekvy29j-uya`) preserved byte-for-byte;
  `files/projects.json` was never hand-edited.
- `python-release-audit` was created **through the app's New Project dialog**
  (not by editing the registry), so it is properly registered
  (id `hn8f75zfzb-7o1`). The app created `src/main.py`, `history.json`,
  `.qfli/project.json`.
- Fixture then pushed into the app-created project via `run-as`:
  `src/main.py` (`import helper` + `input()` + write `out.txt` + read back),
  `helper.py` (root sibling import), `input.txt` (`Ada\n`).
- Opening it in the UI produced a real editor session: its `history.json`
  records `activeFile: src/main.py` (evidence the editor opened the audit
  project's file).

## Automation limitation (documented, per coordinator)

`uiautomator dump` **intermittently returns "null root node returned by
UiTestAutomationBridge"** on this device. An enabled,
bound accessibility service
`com.rise.automatic.autoclicker.clicker/…MouseAccessibilityService`
(a user-installed auto-clicker) was observed. Its causal role was not isolated;
it is **not mine and was not disabled**.
Consequence: UI element dumps are unreliable; when they succeed they sometimes
capture a **peer's** screen (e.g. the ColorOS `InstallGuideActivity` for
`QFLIWebFile`/webforge, and earlier `sqlab`/`dartwing`). All UI actions were
therefore done with `input tap` at coordinates, and state was verified through
**on-device file artifacts** (`history.json`, `projects.json`)
rather than screen text. Screencaps were captured as evidence.

## Device foreground contention (respecting peers)

Multiple workspaces cycled through `mCurrentFocus` during my window: `sqlab`,
`jvmx`, `dartwing`, `com.oplus.appdetail InstallGuideActivity` (webforge
install). Per the coordinator's guidance I did not repeatedly steal foreground,
did not force-stop peer apps, and did not touch peer data. The coordinator
arranged windows; I used them for: app launch, native 46/46, New-Project
creation, and editor open of the audit project.

## Executed on-device (real)

| Check | Result | Evidence |
|---|---|---|
| debug APK built + installed + launched | PASS | install logs, `mCurrentFocus` |
| native self-check | **46/46** | `native-selfcheck-debug-2.log` |
| New Project registered via UI | PASS | `projects.json` gains `python-release-audit` |
| editor opened audit project file | PASS | audit `history.json` `activeFile: src/main.py` |
| user project preserved | PASS | `tttt` and its existing registry entry preserved; audit project added through UI |

## Bounded final status (turn end)

All evidence above is real and preserved. The device foreground never became
available for a clean pyflow UI run within this turn: the ColorOS
`com.oplus.appdetail InstallGuideActivity` (a **peer** install overlay, for
webforge/`QFLIWeb`-family) owned `mCurrentFocus` continuously after the audit
project was opened, and prior to that `sqlab`/`jvmx`/`dartwing` cycled through.
Per coordinator guidance I stopped focus polling and did not steal or wait
indefinitely.

**Executed and preserved this turn**

- Final debug APK built (19:32:53, includes p6 cwd fix), installed, launched.
- Native self-check **46/46 PASS** (real MicroPython `1.24.1 (ecfdd5d)`) on the
  final APK.
- `python-release-audit` created through the app's New Project dialog and
  registered; audit fixture pushed; editor opened its `src/main.py`
  (`history.json` `activeFile: src/main.py`).
- User project `tttt` and its registry entry preserved; the app registered the
  audit project through UI (the registry was not manually edited).
- Final release APK (coordinator build, 19:37:37) hash recorded
  `2F160DB71DB1D824D413610ADE69B7D7C7570A84526B8B143C1FCD5263AB6811`.

**Pending (UI cases, truthfully not run)**

1. standalone terminal `python --version` (expect stdout/exit 0)
2. standalone terminal `python src/main.py` script run
3. editor Run button
4. editor long-press run current file
5. `input.txt` + import + file-write end-to-end via UI
6. compile to `.mpy`, delete source, run `.mpy`
7. stop a running loop (cancellation)
8. final release `install -r` + launch + JNI usability (pending coordinator's
   last build after the core About identity fix)

These are UI-path coverage only; the native 46/46 already exercises the same C
VM paths (stdin, sibling/package import, file write/append/binary, compile to
`.mpy`, load-after-source-delete, cancel-before/during, token isolation).

**Blocking reasons (accurate)**

- Peer install overlay owned foreground (ColorOS `InstallGuideActivity`) — a
  peer's active operation; not mine to dismiss.
- `uiautomator dump` intermittently returns "null root node" due to an enabled
  user auto-clicker accessibility service; dumps sometimes captured peer screens.
- Coordinator instructed no release install while a system/peer install overlay
  owns foreground, and requested a bounded status rather than indefinite wait.

**Foreground release**: SQL wC:p5 is released — Python no longer needs the
foreground window. No further focus polling or installs will be performed until
root/coordinator confirms the final release build and a free window.

## Final release (post core8b33443) — single bounded check, blocked

- Final release rebuild after core `8b33443`: `√ Built` in 75.8s
  (`build/python-release-android.log`).
- Final release APK: 72,878,894 bytes, built **2026-10-15 20:03:32**,
  SHA256 **`6549B2DF3125526EB944CC0EB2EF1CA983155BE6933D16C4C71A7F6D8AE46059`**.
  (Supersedes the 19:37:37 `2F160DB7…` build, which is now historical.)
- ONE bounded foreground read (no polling loop):
  `mCurrentFocus=com.azurekiln.qfli.webforge/.MainActivity`.
- **Outcome: BLOCKED — peer (Web/webforge) actively owns foreground.** The
  ColorOS install overlay is gone, but a sibling product's window is on top.
  Per instruction ("if system overlay/peer test still owns focus, report blocker
  and stop"), I did **not** install, launch, or steal foreground, and did not
  poll.
- Pending unchanged: final release `install -r` (no uninstall) + launch +
  terminal/editor validation; plus the earlier pending UI cases.
- Historical debug evidence (46/46 native self-check) remains valid above and
  is preserved; it is not superseded by this release blocked state.
- No uninstall performed; all user data preserved; SQL notified of release.
