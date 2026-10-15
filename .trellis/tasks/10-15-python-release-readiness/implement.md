# Execution plan

1. [x] Verify repository, branch, dirty baseline, shared dependency and all three Herdr Pi paths.
2. [x] Capture the user's full authorization and exact worker boundaries in PRD/design.
3. [ ] Dispatch the three verified Pi panes; research native and platform validation commands in parallel.
4. [ ] Audit/fix standalone and editor terminals, native capabilities and offline navigation; add focused regression coverage.
5. [ ] Re-run complete Python curriculum checks and verify all declared outputs and non-Python preservation.
6. [ ] Independently review resulting changes against specs and run full app `flutter analyze` and `flutter test` plus relevant core checks.
7. [ ] Build real Windows/native test library and run native/FFI lifecycle tests; compare packaged/source bridge hashes.
8. [ ] Build Android APK(s), inspect packaging/dependencies/alignment; attempt explicit authorized device/emulator test if available.
9. [ ] Build signed OHOS HAP and inspect library dependencies; attempt explicit OHOS device validation if available.
10. [ ] Resolve remaining existing Trellis tasks based on real evidence; improve applicable concrete specs and record unavailable gates as open.
11. [ ] Serialize explicit-path Conventional Commits after each verified logical change. Record final commits, artifact paths and limitations.

## Validation entry points

- `flutter analyze`, `flutter test` in qfli_python; actual native tests must not silently skip missing libraries.
- `dart run tool/python_ffi_smoke.dart`; native builder/tests as documented in native/README.md and native/tests.
- Shared Python content generator verifier/tests in qfli_studio_core, with cwd explicitly selected and no parallel Pub operations in the same package.
- `flutter build apk --release` and `flutter build hap --release` after discovering local SDK/signing contracts. Preserve logs and distinguish build/device results.
- `adb devices -l`, `hdc list targets`; never assume a serial or change a peer's emulator state.

## Approval and scope

The user's current instruction explicitly authorizes all remaining implementation, tests, local commits and attempted device deployment. Do not add a redundant planning permission stop. The initial OHOS dirty baseline remains excluded unless a concrete fix requires an individually reviewed overlap.
