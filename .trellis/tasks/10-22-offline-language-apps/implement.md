# Ordered execution and evidence

## Before implementation

- [x] Read the complete attachment and relevant Trellis/spec guidelines.
- [x] Publish Python ownership and deny ownership of unrelated explorer WIP.
- [x] Persist parent/child PRD, design, execution plans and context manifests.
- [ ] Present the final planning summary and receive review approval.
- [ ] Start the child owning the next concrete deliverable, not all children.

## Work order

1. Snapshot relevant initial diffs and revisions. Finish exhaustive existing
   catalog/module baseline; keep all failures in the evidence inventory.
2. Implement module/local-package child. Serialize native import/generator
   changes and prove real imports, project isolation and rollback behavior.
3. Repair existing lesson/example/answer/fixture failures. Obtain C allocation
   for Python-only content files and a serialized asset generation window.
4. Build and run the existing full catalog on installed OHOS. Keep a named open
   device gate if hdc has no target; continue independent modules/tools work.
5. Only after that baseline, author and validate 180 new paired topics, then
   rerun exhaustive host and installed-OHOS verification including answers.
6. Implement direct tools and unsaved-source analysis against C's published
   API. Review busy/revision behavior and normal import-to-editor execution.
7. Implement debugger child after the native module batch; integrate the common
   debug contract when delivered. Verify pauses, steps, stops and recovery.
8. Run full Python/shared integration checks and inspect final HAP contents,
   actual offline permissions and all original-scope evidence ledger entries.
9. Update relevant specs, stage explicit owned paths, inspect staged diff and
   create focused Conventional Commits. Push authorized refs without force;
   compare remote branch OIDs and report independent mirror failures honestly.

## Validation commands

From Python root unless stated otherwise:

```text
flutter analyze --no-pub
flutter test --no-pub
node native/tests/ohos_channel_test.cjs
sh native/tests/run_host.sh
dart --packages=.dart_tool/package_config.json tool/python_ffi_smoke.dart native/build/windows/qfli_py_ffi.dll
./native/build.ps1 -Abi arm64-v8a -BuildType Release
python native/tools/check_so_deps.py native/build/cmake-arm64-v8a/libqfli_py.so
python native/tools/inspect_so.py native/build/cmake-arm64-v8a/libqfli_py.so
flutter build hap --release --no-pub --target-platform ohos-arm64
hdc list targets
```

Use available documented Windows/WSL native build equivalents when the shell
prerequisite differs. Run generator/verifier commands only with task-local
reports and serialized core asset ownership; the old verifier writes an older
task report and separates CPython passes, so it is not the new release gate.
Installed-device audit uses the explicit freshly discovered hdc target, final
HAP/library/asset hashes and all inventory IDs; preserve other products' data.
No device operation occurs without checking the current coordination window.

## Review gates and rollback points

- Modules: public API/provenance, byte-for-byte user-file preservation on
  failure, no native ABI break and no network package path.
- Content: original baseline passes before additions; zero missing fixtures or
  unanswered/invalid solutions; exact output; no non-Python/custom-data drift.
- Tools/analyzer: 360x800 and 1200x800 layouts; disposal/project changes;
  compile-only has zero side effects; stale and VM-busy requests are honest.
- Debug: ordinary run unchanged; cancellation while paused; queue/token cleanup;
  next run succeeds after every normal/error/stop/session-disposal path.
- Release: root tests/analyzer, native checks, parity, packaged artifacts and
  actual device evidence are separate gates. No partial result closes parent.

Rollback only reviewed owned commits/transaction staging. Never use broad
`git add -A`, reset, clean, recursive cross-shell deletion or force push.
