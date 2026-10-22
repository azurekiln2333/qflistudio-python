# Independent package-service review

Date: 2026-10-22. Reviewer: `review_python_packages` (`trellis-check`).

Assigned ownership: `lib/python_packages.dart`,
`lib/python_module_catalog.dart`, `test/python_packages_test.dart`, and this
note. Read the complete saved hook context, task PRD/design/implementation plan,
check manifest, quality/runtime specs, and `trellis-check` skill. No shared-core,
runner, native, platform, signing, or preexisting WIP changes were made. No
staging or commits.

## Findings fixed

1. **Upgrade checks accepted a dependency deleted by that same upgrade.**
   `_inspect` previously merged all on-disk project modules with the candidate.
   If version 1 installed `consumer.py` and `retired.py`, version 2 containing
   only `consumer.py` with `import retired` passed and deleted `retired.py`.
   The new-module calculation excludes the current distribution's previous
   ownership before adding the candidate roots. Regression reproduced a
   successful bad upgrade before the fix. Coverage also checks removed package
   initializers and that a separate project-root dependency remains usable.

2. **Imports after semicolons escaped direct dependency checks.**
   `import json; import socket` passed despite unavailable `socket`. After
   masking string literals/comments, the scanner now treats semicolons as
   statement boundaries. The regression failed before the fix and covers
   missing bundled API names plus harmless semicolons in strings/comments.

3. **ZIP expansion limits were enforced after full inflation.**
   Metadata checks bounded declared uncompressed sizes, but
   `ArchiveFile.readBytes()` in archive 4.3.0 uses whole-buffer native zlib
   decoding. A ZIP declaring eight bytes but inflating beyond two MiB reached
   the final size/CRC check only after full allocation. The private read step
   now passes compressed bytes through `ZLibCodec`'s incremental decoder into a
   sink that rejects output beyond the already-validated declared size. The
   regression produces a real deflated oversized member and patches its
   central-directory size; it failed with the old post-inflation diagnostic
   before this fix and now terminates at the output bound. Existing CRC,
   encrypted, symlink, traversal, native-wheel and supported-source cases pass.

No public interfaces or supported archive formats were changed.
`python_module_catalog.dart` was reviewed and remains unchanged.

## Verification

- `flutter test --no-pub test/python_packages_test.dart`: **44 passed, 0
  skipped**. Includes real embedded compile-only validation and host filesystem
  link confinement. Also covers ownership conflicts, edited/unmanaged file
  preservation, preflight/mid-commit failures, cancellation during install and
  uninstall, cross-service project serialization, local dependency constraints,
  and bundle digest/repair/idempotent mtime behavior.
- `dart analyze lib/python_packages.dart lib/python_module_catalog.dart
  test/python_packages_test.dart`: **No issues found** after adding direct
  `dart:typed_data` imports for the new byte sink/fixture metadata edit.
- `dart format` of all three assigned Dart files: **0 further changes** on the
  final pass. `git diff --check` for owned paths: **pass** (these implementation
  files remain untracked, so analyzer/formatter are the substantive file checks).
- Real DLL used by the package compiler test:
  `native/build/windows/qfli_py_ffi.dll`, SHA256
  `2329ef7d374e35dd5159db0f3f056b094effc9a0372ad29fe704af472a6c309f`.

## Remaining scope and recommendations

No further confirmed defect was found within the assigned service/catalog
scope. Static checks deliberately inspect directly written import roots and
the declared bundled API list; they cannot establish dynamic-import,
submodule/symbol, or arbitrary third-party runtime API compatibility. The
existing success text states that actual execution remains required. Do not
turn this result into a CPython/pip compatibility claim or security-isolation
claim.

Root owns complete application gates, runner install-to-import integration,
OHOS builds and installed-device evidence. This host review does not satisfy
those gates. Preserve the separate global device queue and shared-core owner.

When the coordinator updates the runtime/package spec for this new service,
record that compatibility uses the post-upgrade module set and archive output
must be bounded during decompression, rather than trusting ZIP metadata. Spec
writes are outside this review's explicit file ownership.
