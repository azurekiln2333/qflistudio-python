# Python release readiness audit

## Goal

Prepare QFLIPyFlow for storefront submission by verifying the complete local Python workflow, offline product surfaces, substantive curriculum, and Android/OHOS packages. The user explicitly authorized finishing remaining Trellis work, parallel use of the three existing Python Pi panes, fixes, Conventional Commits, builds, and attempted device deployment/testing.

## Confirmed facts

- Repository: `D:/MyNewProjects/qfli_python`, initial branch `main`; working branch
  `release/python-storefront-20261015`. Adjacent shared dependency:
  `D:/MyNewProjects/qfli_studio_core`.
- Verified Herdr workspace: `wA`; coordinator `wA:p1`; Pi workers `wA:p5`, `wA:p6`, `wA:p8`. Inherited `HERDR_WORKSPACE_ID=wY` is stale; never rely on focus or inherited IDs.
- Initial HEAD: `2f5ed81`; core initially clean at `ad17f35`. Existing uncommitted OHOS icons, native SO, EntryAbility, routes and AgreementReader are not automatically owned by this task.
- `pythonProfile.isOffline=true` inherits the core offline capability policy. Prove actual entry-point behavior.
- Initial native/terminal/curriculum tasks were `09-30-native-python-runtime`,
  `10-09-terminal-run-gestures`, `10-12-python-practical-curriculum`, with
  bootstrap guidelines also active. Bootstrap, curriculum and terminal tasks
  are now archived under `archive/2026-10/`; native runtime remains open for
  the latest OHOS device gate.
- Existing Python content contains 120 paired lessons/examples (116 embedded, four explicitly external CPython). Audit live assets before any regeneration.
- Core editor/terminal work is shared with concurrently running language workspaces. Limit edits to Python-owned behavior; coordinate shared defects before modifying core.

## Requirements

1. Verify standalone terminal and editor terminal Python execution, paths, input, stdout/stderr, exit status, syntax errors, imports, artifacts and cancellation. Fix concrete gaps without fake or empty implementations.
2. Hide Git networking, cloud terminals/projects, login/account and other online product surfaces under the existing shared offline policy. Verify release manifests and local startup behavior.
3. Audit all Python tutorials/examples for placeholders and correctness. If legacy placeholders remain, replace only Python built-in catalog data with 100+ substantive progressively ordered paired lessons. Preserve user-created records and every other language's content.
4. Build and test native runtime, Flutter app and relevant shared contracts; build Android and OHOS packages. Attempt deployment only to an explicit available target, preserving other workspaces' devices/sessions. Report authorization or tool/environment blocks accurately.
5. Persist decisions, worker ownership, findings, commands/results and outstanding gates in Trellis. Commit each coherent verified change with Conventional Commits, staging explicit owned paths only.

## Acceptance criteria

- Both terminal surfaces invoke the actual Python backend; supported operations either work or are capability-gated. Platform differences, if any, are explicit and tested.
- Offline storefront users have no reachable Git network, cloud terminal/project or authentication flow through normal app navigation.
- At least 100 real paired Python lessons/examples pass structure and actual declared-runtime execution checks; no changes to non-Python assets or user custom data.
- App analyzer/tests, real native checks and Android/OHOS builds have recorded outcomes and artifact paths; device execution is distinguished from compilation.
- Every owned change is committed; unrelated initial modifications remain identifiable. Unmet hardware/environment gates keep their owning task open.

## Scope boundaries

No changes to sibling language apps, no mass deletion, no blanket Git staging, no remote Git push/store publication. Shared-core modifications require exact file/segment ownership and cross-workspace coordination. Existing custom content is retained.

### Authorized Git publication — 2026-10-16

The user subsequently supplied five Python repository URLs (GitHub, Gitee,
GitLab, GitCode and CNB) and explicitly requested configuration and push.
That instruction supersedes the no-remote-push boundary for these five Python
destinations. Publish the committed release work and a safe fast-forward of
`main`; preserve unrelated dirty files and do not force-push. Configuration
details are in `research/git-mirrors.md`. Store publication and sibling/core
repository pushes remain outside this request.
