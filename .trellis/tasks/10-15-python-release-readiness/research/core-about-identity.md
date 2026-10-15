# Shared-core About product identity

## Scope and result

Coordinated ownership with the Python coordinator and the Java retained-editor
owner. Changes are confined to `qfli_studio_core/lib/pages/settings_page.dart`
(`showQfliAbout`) and new `test/settings_about_test.dart`. No shared task metadata,
other product code, dependency resolution or build outputs were changed.

The About dialog previously always identified itself as QFLIStudio+ and advertised
the developer community. It now reads `StudioProfile.current.appTitle`, falling
back to `StudioProductCatalog.qfliStudio`. Products with `offlineOnly == true`
show a local-project/code/tutorial description; online products retain the
existing description. The implementation is language-independent and preserves
the existing version, icon and standard Flutter About/license dialog behavior.

## Validation

Executed in `D:/MyNewProjects/qfli_studio_core`:

- `flutter test --no-pub test/settings_about_test.dart --reporter expanded`:
  **4/4 passed**. Real About dialog coverage includes offline Python and Java,
  the null/default profile, and an explicit online profile. The differing
  `isOffline`/`offlineOnly` cases verify that the network capability policy owns
  the description.
- `dart analyze lib/pages/settings_page.dart test/settings_about_test.dart`:
  **No issues found**.
- `dart format lib/pages/settings_page.dart test/settings_about_test.dart`:
  complete; no unrelated formatting changes.
- `git diff --check -- lib/pages/settings_page.dart test/settings_about_test.dart`:
  passed (only the repository's existing LF-to-CRLF advisory).

No staging or commit was performed by this worker. The coordinator owns review,
explicit-path Conventional Commit and final application builds. Full core/app
test results and device evidence remain the coordinator's separate gates.

Coordinator reviewed and committed the two exact core paths as **`8b33443`**
(`fix(settings): show active product identity in About dialog`). Java retained
editor owner `wE:p8` acknowledged the ownership and relayed it to `wE:p4`.
After this core commit, the full Python analyzer again reports No issues
(5.6 seconds) and all **91/91** app tests pass. Both release packages are
rebuilt against this core snapshot; final hashes belong in `verification.md`.
