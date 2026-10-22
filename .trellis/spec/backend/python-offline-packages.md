# Offline Python modules and project packages

## 1. Scope / Trigger

Read for `lib/python_packages.dart`, `python_module_catalog.dart`, bundled
Python assets, native import paths, and package consumers. The embedded engine
is MicroPython 1.24.1; a successful import or syntax check does not establish
full CPython compatibility. Assets retain provenance, licenses and tested scope
in `assets/python_stdlib/PROVENANCE.md` and `manifest.json`.

## 2. Signatures

```dart
typedef PythonPackageSyntaxCheck = Future<String?> Function(
  String source, String absoluteFilePath);
PythonPackageService({AssetBundle? assets, PythonPackageSyntaxCheck? syntaxCheck});
// Methods: moduleCatalog, ensureBundledModules(projectPath),
// listInstalled(projectPath:), show(projectPath:, name:),
// check/install(projectPath:, sourcePath:, name:, version:, isCancelled:),
// remove(projectPath:, name:, isCancelled:).
Future<PythonSyntaxResult> PythonProgramRunner.checkSource({
  required String projectPath, required String entryFile, required String source,
});
```

The compiler callback returns null only for actual success. A failed native
check with empty diagnostics still needs a nonempty rejection message. Results
expose typed success/compatible, message and issues fields. Operations may
return a package and preservedFiles; preparation returns directory and modules.

## 3. Contracts

- Project paths are explicit absolute existing directories. Package operations
  use a canonical per-project lock shared across service instances. Source may
  be an explicit local `.py`, directory, `.zip` or supported pure-source `.whl`.
  Downloads, build hooks, setup execution and native extensions are unsupported.
- Bundle manifest version 1 declares bundleVersion `v1`, global `files`
  `{path,sha256}`, and modules with name/version/summary/apis/files/license/source.
  The source asset digest must match before writes. Prepare into
  `.qfli/python/bundled/v1`, tracking ownership in
  `.qfli/python/bundled/installed.json`. Identical preparations preserve mtimes;
  missing owned files can be restored, modified or unmanaged files conflict.
- Installed package source/data lives under `lib/`, with digests in
  `.qfli/python/packages.json`. Stage and validate the complete transaction
  before publishing. Cancellation or write failure restores previous bytes and
  manifest. Remove only unchanged manifest-owned files; report preserved edits.
- Reject traversal, absolute/Windows alias paths, links, case collisions,
  unsupported binaries, encrypted archives and corrupt metadata/CRC. Limit
  file count to 4096, each file to 2 MiB and total source to 16 MiB. Bound actual
  output during decompression; declared ZIP sizes alone are insufficient.
- Compile every `.py` through the real compile-only callback. Static import and
  declared API/dependency checks are conservative, not a runtime guarantee.
  Inspect semicolon-separated direct imports after masking literals/comments.
  Upgrade compatibility uses the resulting module set, excluding old owned
  files that this upgrade deletes. Existing project modules override bundle
  metadata; never adopt their files as package ownership.
- Native import order is entry directory, project root, project `lib/`, then
  `.qfli/python/bundled/v1`. Normalize existing directories, tolerate absent
  optional directories, bound joins, preserve source identity and reset VM
  imports each invocation. This order is not a separate filesystem sandbox.
- Runner prepares verified bundles after the native capability probe and before
  execution. Bundle conflicts return not-run status and do not execute source.
  `checkSource` compiles exact unsaved text without saving/preparing/importing.

## 4. Validation & Error Matrix

| Condition | Required result |
| --- | --- |
| Missing syntax callback | Local install/check rejected |
| Native syntax error | Reject; previous package remains usable |
| Missing dependency/known unsupported bundle API | Visible issue; no resolver |
| Invalid bundle digest or edited destination | Preparation failure; no execution |
| Cancellation during publish/remove | Previous bytes and manifest restored |
| Malformed ownership manifest | Failure; do not discard ownership |
| Repeated unchanged prepare | Success without touching file/manifest mtime |
| Removed package leaves an empty directory | Its owned source/API is absent; do not claim namespace import must fail |

## 5. Good / Base / Bad Cases

- Good: install a local package importing supported `statistics.mean`, then
  execute it through the actual runner and automatic bundle path.
- Base: prepare the bundle in a fresh project, run, and repeat with fresh VM.
- Bad: accept source merely because it compiles, then advertise arbitrary pip
  compatibility or substitute host CPython execution for device evidence.

## 6. Tests Required

`python_packages_test.dart` covers ownership, rollback, links, archives,
post-upgrade dependencies, real compiler/no execution and idempotent mtimes.
`python_package_runtime_test.dart` exercises actual asset preparation plus
install/import/update/remove and pre-execution conflicts through the runner.
`python_module_imports_test.dart` tests native precedence, Unicode, freshness,
compile-only and cancellation recovery. `python_source_check_test.dart` checks
exact unsaved CRLF/Unicode text without side effects. In widget tests clear
rootBundle between fake async zones and use bounded runAsync pumping for asset
and filesystem I/O.

`python tool/verify_python_modules.py` verifies manifest digests, all portable
API behaviors and selected differential vectors in the actual VM. Keep legacy
`--explicit-path` reports distinct from automatic imports. OHOS needs current
SO/HAP inspection plus installed module/package execution independently of
host checks. An x64 build never proves ARM64 device execution.

## 7. Wrong vs Correct

Wrong: trust ZIP uncompressedSize, inflate all bytes, then reject an overflow.
Correct: validate metadata and stop the decompression sink when actual bytes
exceed the declared/per-file bound, before adding files to the transaction.

Wrong: `return result.error.isEmpty ? null : result.error` in a syntax callback.
Correct: return null only when `result.success`; otherwise supply its diagnostic
or a nonempty compile-failure message.
