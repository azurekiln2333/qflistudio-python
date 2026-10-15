# Release readiness design

## Boundaries and ownership

The app owns Python profile/runner/tools, native bridges, platform packaging, app tests and task records. Shared `qfli_studio_core` owns navigation, offline policies, terminal widgets and bundled content. Prefer existing extension points and capability probes; do not duplicate shared UI.

- `wA:p5`: Python runner/terminal/native capability audit and implementation. Own `lib/python_runner.dart`, `lib/python_tools_page.dart`, their focused tests, native OHOS bridge sources and matching packaged copy if necessary. Must report native ownership expansion before changes. No core edits or platform application startup changes.
- `wA:p6`: offline storefront and profile integration audit/tests. Own `lib/main.dart`, new offline integration tests and task-local offline research. Report shared-core defects to coordinator before editing shared files. Do not edit runner/native/curriculum.
- `wA:p8`: current Python curriculum full audit with real runtimes and preservation checks; task-local evidence and Python-specific generator/test/source changes only if defects exist. No other language or aggregate JSON overwrites; coordinate any regeneration first.
- Coordinator: platform build/deployment, native build audit, shared coordination, commit serialization, task/spec lifecycle and final integration review.

All workers are sharing live files with each other and other workspaces. Never revert others' changes. Git commits are serialized by the coordinator, with explicit paths and independent review of staged diffs.

### Final ownership updates

- After curriculum completion, `wA:p8` also owns Android debug/device evidence
  (`research/android-device.md`), coordinating foreground access with SQL/Dart.
- Root owns the final OHOS metadata cleanup in `ohos/AppScope/app.json5` and
  `ohos/entry/.../element/string.json`. The ignored stale x86_64 SO was preserved
  in `build/python-release-evidence/initial-stale-x86_64-libqfli_py.so` outside
  packaging, since the selected release target is arm64 only. Existing dirty
  icons/startup/routes remain untouched.
- Shared About identity fix has an explicitly assigned core worker owning only
  `lib/pages/settings_page.dart` and one focused test. Java retained-editor
  owner `wE:p8` was notified. Core offline/editor/code-import changes remain
  with their existing owners; see `research/core-about-identity.md`.

## Runtime contract

Trace UI command -> ProgramRunner -> channel/FFI -> C VM -> native result -> shared terminal. Actual project/entry paths, finite input.txt, stdout/stderr, exit status, cancellation ownership and upstream bytecode serialization must survive this path. OHOS must not claim a capability absent from its bridge. Shared C API is the implementation authority.

## Offline contract

Use StudioProfile.offlineOnly/isOffline and shared feature gating. Audit navigation and adapters, rather than removing shared network code needed by online products. Build-time tool downloads are separate from runtime product networking. Privacy/legal pages remain available.

## Content contract

Use current authored 120-lesson Python pipeline. Verify first; regenerate only for a demonstrated defect. Preserve custom records and non-Python JSON entries. Embedded samples run against the actual native DLL, external CPython lessons run separately with accurate labels.

## Validation and rollback

Run meaningful focused regression checks after each change, then one final complete app test/analyzer pass and platform builds. Keep build outputs/logs under ignored `build/` or `native/build/`, concise tracked evidence under this task. Roll back only owned changes; do not restore whole shared assets or initial OHOS modifications.
