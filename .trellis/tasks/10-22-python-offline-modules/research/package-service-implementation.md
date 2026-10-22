# Python package service implementation evidence

Date: 2026-10-22. Owner: dispatched `implement_local_packages` worker.

Owned files: `lib/python_packages.dart`, `lib/python_module_catalog.dart`,
`test/python_packages_test.dart`, and this research note. No core, native,
runner, UI, asset, pubspec, staging or commit changes were made by this worker.
The coordinator supplied direct `archive 4.3.0` / `crypto 3.0.7` dependencies
and the runner's `checkSource` integration; Pub was serialized by the coordinator.

## Consumer API

```dart
typedef PythonPackageSyntaxCheck =
    Future<String?> Function(String source, String absoluteFilePath);

PythonPackageService({AssetBundle? assets, PythonPackageSyntaxCheck? syntaxCheck});
Future<List<PythonModuleInfo>> get moduleCatalog;
Future<PythonBundlePreparationResult> ensureBundledModules(String projectPath);
Future<List<PythonInstalledPackage>> listInstalled({required String projectPath});
Future<PythonInstalledPackage?> show({required String projectPath, required String name});
Future<PythonPackageCheckResult> check({
  required String projectPath, required String sourcePath,
  String? name, String? version, bool Function()? isCancelled,
});
Future<PythonPackageOperationResult> install({
  required String projectPath, required String sourcePath,
  String? name, String? version, bool Function()? isCancelled,
});
Future<PythonPackageOperationResult> remove({
  required String projectPath, required String name, bool Function()? isCancelled,
});
```

The syntax callback returns **null only for a successful real VM compile**;
every non-null string, including an empty diagnostic, means rejection. No
callback means installation/check fails visibly. The callback is never used
for bundled preparation. Runner/tools can construct it with:

```dart
syntaxCheck: (source, path) async {
  final checked = await runner.checkSource(
    projectPath: selectedProjectPath, entryFile: path, source: source,
  );
  return checked.success ? null : checked.error;
}
```

All result classes expose `success` and `message`; check additionally exposes
`compatible`, `name`, `version`, `files`, `issues`; operations expose `package`,
`issues`, `preservedFiles`; preparation exposes `directory`, `modules`, `issues`.
Installed packages expose `name`, `version`, local `source`, `installedAt` and
owned project-relative `files` mapped to SHA256. Corrupted manifests cause
`listInstalled`/`show` to throw, rather than pretending there are no packages;
mutation/check entry points return typed failures.

`moduleCatalog` combines the 17 names actually present in the original VM probe
with the injected/shipped manifest. Builtins carry no unverified API claims.
Bundled entries carry manifest version, origin, summary, API scope, source and
license. Project packages are listed separately by the selected project;
unmanaged source files are used for import availability but are never adopted
into installation ownership.

## Disk and transaction contract

- Require an existing, explicit absolute project path. An empty path never
  defaults to the repository/current directory.
- Bundles use `.qfli/python/bundled/<bundleVersion>/` and independent ownership
  `.qfli/python/bundled/installed.json`. Asset bytes must match the manifest's
  SHA256, every module file must match the global manifest, and all paths must
  be confined relative paths. Preparation verifies existing owned bytes; exact
  repeat preparation changes neither source nor manifest mtimes. Missing owned
  files are repaired; edited/unmanaged destinations cause a visible conflict.
- User packages use `lib/` and `.qfli/python/packages.json`, format version 1.
  Every installed byte has a digest. Package names and owned paths must be
  unique, including case collisions across platform filesystems.
- Directory/source/archive inspection and all native compile-only checks finish
  before publishing files. `check` performs no filesystem mutations.
- All writes stage under a random `.qfli/python/.package-transaction-*`
  directory. Existing targets are backed up by rename; new files publish by
  rename; the ownership manifest publishes last. Cancellation or write failure
  removes published files and restores prior bytes. Temporary directories and
  newly created empty parents are removed. If a second filesystem failure also
  prevents rollback, recoverable backups remain in the reported staging path;
  the only copy is never removed in `finally`.
- Updating a package cannot overwrite unmanaged files, another package's files,
  or edited owned files. Obsolete owned files are removed only after verifying
  their original digest. Removal deletes unchanged owned files, leaves modified
  and unmanaged siblings, drops the ownership record, and reports preserved
  paths. A symlink conflict fails safely rather than following it.
- A static per-canonical-project queue serializes calls across distinct service
  instances in the same Dart isolate. Different project keys are independent.
  This is not a distributed/interprocess lock or a hostile-code sandbox.

## Supported input and compatibility limits

Inputs are explicit local `.py`, directories, `.zip`, or compatible source
`.whl`. Directories containing `__init__.py` retain their package folder;
source collections/ZIPs retain their importable top-level layout. There must
be top-level Python module/package source rather than an archive of only data.

Files are UTF-8 Python/text resources with extensions `.py`, `.txt`, `.md`,
`.rst`, `.json`, `.csv`, `.toml`, `.ini`, `.cfg`, `.yaml`, `.yml`, or named
LICENSE/COPYING/NOTICE. Wheel metadata has an explicit additional allowlist.
NUL-containing data, binary resources/extensions, `.mpy`/`.pyc`, links, special
files, traversal, drive/absolute paths, backslashes, Windows path aliases,
case-colliding entries, hidden files, `__pycache__`, wheel `.data` trees and
`setup.py` build sources are rejected. Caps: 4096 entries, 2 MiB/file,
16 MiB expanded/total; ZIPs must have complete single-disk directory metadata,
store/deflate compression, no encryption, consistent local/central filenames,
and valid CRC/expanded sizes. Links and size bounds are checked before decode.

Wheel extraction checks filename and `WHEEL`/`METADATA` name/version consistency,
Wheel-Version 1.0, `Root-Is-Purelib: true`, `py3-none-any` (including
`py2.py3-none-any`), and local dependencies. CPython-specific tags, command
entrypoints/install scripts, `.data` layouts, and CPython minor-version
requirements are rejected. Only broad Python 3 constraints are accepted;
MicroPython is not advertised as a particular CPython release. Wheel metadata
is removed from executable project contents; ownership uses freshly computed
SHA256, not wheel RECORD or a claim of package authenticity.

Optional `qfli-package.json` supplies a local collection/directory package's
`name`, `version`, and `requires` list. Dependencies are checked against locally
installed package/bundle versions; simple dotted numeric `== != >= <= > <`
constraints are supported. Missing dependencies, extras, environment markers,
URL requirements and unevaluable version constraints are explicit errors.
No dependency resolver, download, pip, subprocess, setup/build hook, virtualenv
or second interpreter exists in this service.

Every `.py` is passed to the injected real native compile-only checker. Direct
imports are checked against actual candidate/project modules, shipped bundle
names and the builtins probe. Imported bundled symbols are checked against the
declared API scope, respecting local module/version precedence. Comments and
string literals are excluded from dependency scanning. This is deliberately
not full static analysis: dynamic imports, indirect attribute calls and
arbitrary third-party CPython API semantics still require actual runtime tests.
The successful check message states this limit explicitly.

## Verification performed

From `D:/MyNewProjects/qfli_python`:

```text
flutter test --no-pub test/python_packages_test.dart --reporter expanded
39 tests passed, no skips in this host run.

dart analyze lib/python_packages.dart lib/python_module_catalog.dart test/python_packages_test.dart
No issues found.
```

Tests use real temporary project/source trees and generated ZIP/wheel bytes.
They exercise happy-path check/install/list/show/remove, local package
submodules/resources, dependency constraints, project precedence, no unmanaged
overwrite/adoption, edited file preservation, obsolete owned-file updates,
separate project isolation, failed compile/cancel/write transactions, a real
mid-commit write failure, uninstall cancellation, cross-instance serialization,
archive traversal/case/native/symlink/encryption/CRC/size rejection, corrupt
manifest preservation, real filesystem symlink confinement, digest corruption,
missing bundles and idempotent mtimes.

One test uses the coordinator's actual `PythonProgramRunner.checkSource` and
`native/build/windows/qfli_py_ffi.dll`: valid source installs, invalid syntax
fails while retaining the previous installed bytes, and a source-level
`open(...).write(...)` does not execute during checking. Observed DLL SHA256
after this run:
`b477bc176a55d86a58162e9e25a480ece2706643e93334475140453af23f4f2c`.

This does not prove real VM bundle API behavior or installed OHOS imports.
The coordinator owns actual shipped module/API tests, native default sys.path,
full application analyzer/tests, final native rebuild/hash, OHOS build/device
module/package scenarios, tools integration, spec updates and commits.
