# Research: Python repository remote publication review

- Query: Review repository publication conventions and signing-material exposure before the coordinator configures and pushes five user-supplied HTTPS remotes.
- Scope: Internal, read-only source inspection; no Git commands, network operations or credential-store reads.
- Date: 2026-10-16

## Findings

- `AGENTS.md` delegates project process to Trellis; no remote naming or publication-target rule was found in the inspected project documentation.
- `.trellis/spec/backend/quality-guidelines.md:64` and `.trellis/spec/frontend/quality-guidelines.md:59` require explicit owned-path staging and serialized Conventional Commits. Existing unrelated worktree edits must stay outside publication commits.
- `README.md:3` defines this application as an independent repository requiring a sibling `qfli_studio_core`; `README.md:11` also requires its `vendor/re_editor`. Publishing this repository does not publish or bundle the sibling core.
- `.gitmodules:3` points the MicroPython submodule at its public upstream HTTPS URL. A normal application push preserves the gitlink and does not publish a separate submodule repository.
- `ohos/build-profile.json5:9` and `ohos/build-profile.json5:11` contain nonempty, long hexadecimal literals consistent with IDE-encrypted signing password material. The same file contains a signing alias and machine-local key/certificate/profile paths. No values are reproduced here. Whether this file and historical versions are tracked must be checked by the coordinator before publication; research was explicitly prohibited from Git operations.
- `android/app/build.gradle.kts:57` signs release with the existing debug signing configuration. `android/.gitignore:12` through line 14 exclude local key properties and keystore/JKS files. No additional private-key marker or access-token pattern was found by the scoped filename-only search outside generated directories and third-party sources.
- `.gitignore:36` excludes build output; `.gitignore:92` excludes local specs by default. Ignore rules do not remove already tracked files or historical secrets.

## Push assessment

The coordinator may configure the five explicit user URLs and publish the latest release branch using ordinary non-force pushes. Publishing that same commit to `main` is safe only after independently confirming the local ancestry and each destination ref is absent or an ancestor of the proposed commit. A remote rejection or unrelated target history must be preserved; do not force, mirror, delete refs or replace remote default branches implicitly. Uncommitted files are outside a normal push, but all reachable committed history is included.

## Related specs

- `.trellis/spec/backend/quality-guidelines.md`
- `.trellis/spec/frontend/quality-guidelines.md`
- `.trellis/spec/backend/android-build.md`

## External references

None consulted; this review performed no network access.

## Caveats / Not Found

- Branch hashes, ancestry, tracked-file status, historical signing material, remote emptiness and remote permissions were not independently verified because this dispatch forbids Git and network operations.
- The signing literals are classified by shape only; their cryptographic protection and recoverability were not established. No key store or signing profile was opened.
- No tracked-source modifications, metadata changes or existing report edits were made. This new research-only report persists the required research output.
