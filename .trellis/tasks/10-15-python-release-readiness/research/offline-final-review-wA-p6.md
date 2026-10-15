# Offline final review (wA:p6)

Documentation-only recheck of the Python product's offline storefront posture
against the current tree. Read-only on `qfli_studio_core`; no product files were
edited for this review, nothing staged or committed.

Verified at: `qfli_python` HEAD `189d589` (my terminal work is committed at
`7286cd9`); adjacent `qfli_studio_core` working tree includes other agents'
in-flight changes, which this review treats as read-only.

## 1. Python profile / offline policy — PASS

`lib/main.dart` `pythonProfile`:
- `isOffline: true`, and no explicit `offlineOnly`, so the shared default
  derives `offlineOnly = isOffline = true`
  (`qfli_studio_core/lib/services/studio_profile.dart:111`).
- No `toolsTabBuilder`, no editor AI tools; `toolsPageBuilder` is the local
  Python tools page; runtime is the embedded MicroPython backend.
- `terminalCommandDelegate` registered (offline Python commands work in both
  terminal surfaces, committed at `7286cd9`).

## 2. Core offline gating — PASS (recheck) and prior findings now resolved

Gating points confirmed present in the current core working tree:
- Project scopes drop cloud when `offlineOnly == true`
  (`home_page.dart:307-309`); cloud refresh early-returns
  (`home_page.dart:700`); cloud projects filtered from lists
  (`home_page.dart:550`); "new cloud project" entry gated
  (`home_page.dart:430`); home header account actions gated
  (`home_page.dart:324,343`).
- Content tabs: `LocalTutorialsTab` under offline (`home_page.dart:102`).
- Profile: login header, account stats, check-in/points, admin pages and ICP
  footer omitted (`profile_page.dart:85,101-107,200,221,232`); settings entry
  passes `showAi: false` (`profile_page.dart:68`).
- Editor: cloud sync skipped (`editor_page.dart:203`); online-run fallbacks
  disabled (`editor_page.dart:1001,1092,1116`); terminal `onlineEnabled: false`
  (`editor_page.dart:1895`); `ai` / `online_terminal` popup items gated
  (`editor_page.dart:1639,1660`).
- Background task activity is offline-guarded
  (`task_activity_service.dart:232,246,257,265,311,338,342`).
- Terminal shortcut bar hides network shortcuts offline
  (`shortcut_bar.dart:227,394,433,451`).

**Resolved since the earlier wA:p6 audit (no action needed):**
- The editor `Git` popup item is now wrapped in
  `if (StudioProfile.current?.offlineOnly != true)`
  (`editor_page.dart:1595-1598`), and `cloud_pull` likewise
  (`editor_page.dart:1611-1614`). The desktop `git push/pull` egress surface I
  reported as reachable in offline mode is therefore **no longer reachable**.
- `SandboxShellBackend.helpText` no longer names `java`/`javac`; it now reads
  "语言工具链命令由宿主应用提供，支持范围取决于当前平台。"
  (`sandbox_shell_backend.dart:108`). The generic unknown-command message is
  likewise delegate-conditional (`sandbox_shell_backend.dart:239`). The
  hardcoding I relayed to the Java coordinator is fixed in core.
  Remaining `java`/`javac` mentions are comments only
  (`local_shell_io.dart:26`, `sandbox_shell_backend.dart:318`,
  `terminal_manager.dart:14`) and are not user-facing.

## 3. Android release has no INTERNET — PASS

`android/app/src/main/AndroidManifest.xml` declares **no** `uses-permission`;
the release merge therefore carries none. `android.permission.INTERNET` appears
only in `android/app/src/debug/AndroidManifest.xml` and
`android/app/src/profile/AndroidManifest.xml` (dev-only, hot reload), which are
not part of a release APK. No `src/release` overlay is needed.

## 4. OHOS INTERNET retained for AgreementReader — INTENTIONAL

`ohos/entry/src/main/module.json5` (committed): the unused
`REPLACE_WITH_AGC_CLIENT_ID` metadata was removed; `ohos.permission.INTERNET`
is retained and reformatted. It is reserved for the in-app agreement/privacy
reader (`ohos/entry/src/main/ets/pages/AgreementReader.ets`, an ArkWeb view of
the published https legal pages), which is a legitimate local feature that must
be preserved. No offline product surface can reach the network today:
`userAgreementUrl` / `privacyPolicyUrl` are empty strings
(`qfli_studio_core/lib/config/agreement_config.dart`), and login is hidden
offline. Decision and evidence recorded in `offline-audit-wA-p6.md`.

## 5. About identity finding (resolved after review)

**Shared-core cosmetic: the About dialog shows the wrong product name offline.**

- Evidence: `qfli_studio_core/lib/pages/settings_page.dart` `showQfliAbout`
  hardcodes `applicationName: 'QFLIStudio+'` and a multi-language description
  ("轻量代码编辑器与开发者社区…"). The Android app label is `QFLIPyFlow`
  (`android/app/src/main/AndroidManifest.xml`) and the profile title is
  `QFLIPyFlow` (`lib/main.dart`), so an offline Python storefront user opening
  "关于" sees a different product identity than the icon/shelf entry.
- Severity: cosmetic/local text only; **no network egress**, no functional
  block. It is the only storefront-visible offline inconsistency found.
- Suggested minimal fix (core, coordinator/Java-owned): read
  `StudioProfile.current?.appTitle ?? StudioProductCatalog.qfliStudio` for
  `applicationName` and the profile id for the description. Not edited here —
  read-only core per assignment.

Coordinator follow-up: the scoped core worker implemented this fix and its
four real About dialog widget cases. Root committed only `settings_page.dart`
and the new test as **`8b33443`**. Offline descriptions now follow `offlineOnly`;
the active product name comes from the profile. Default/online behavior is
covered separately. Focused 4/4, analyzer clean, then Python full 91/91 and
analyzer clean. See `core-about-identity.md`; this finding is closed.

Nothing else unmet: no other reachable network surface, no fabricated runtime
version, no dormant online entry, and the platform permissions match the
intended offline posture.

## 6. Status of prior reports

| ID | Item | Status |
|----|------|--------|
| F1 | Python tools unreachable in both terminals | Fixed, committed `7286cd9` |
| F2 | Editor `Git` item not offline-gated | Resolved in core |
| F3 | About dialog hardcodes QFLIStudio+ | Fixed in core `8b33443`, 4/4 tests |
| F4 | OHOS unused `client_id` metadata | Removed, committed |
| F5 | Android release INTERNET | Verified absent; no change needed |
