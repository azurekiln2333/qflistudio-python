# GitHub-hosted native builds

## Goal

Build the native runtime on GitHub-hosted machines, provide downloadable libraries,
and explain the current project status and local disk use.

## Background

- The user explicitly approved task creation and implementation on 2026-11-17.
- The checkout started clean at 6a859a7 on release/python-storefront-20261015,
  eight commits ahead of its remote branch. There was no GitHub workflow.
- The project embeds MicroPython 1.24.1. Desktop and Android consume the tracked
  embedding package; OHOS regenerates it using the pinned upstream submodule.
- Local build/ occupies about 12.6 GB; native/build/ occupies about 40 MB.
- Native libraries and signed full-app packages are different deliverables.

## Requirements

- R1: Use GitHub-hosted runners for Linux, Windows, Android and OHOS native builds.
  Do not depend on a local self-hosted runner.
- R2: Upload named ABI-specific libraries with checksums and build identification.
  Run existing applicable native smoke checks before publishing passed artifacts.
- R3: Push the current-source workflow to a dedicated GitHub branch and run it.
  Report observed run conclusions and artifact download locations accurately.
- R4: Document artifact contents, local use, retention, and rebuild limitations.
- R5: Report measured disk use and distinguish generated caches from source.

## Acceptance Criteria

- [ ] GitHub records a completed run for the implementation commit.
- [ ] Successful native jobs have downloadable, correctly named ABI artifacts.
- [ ] The downloaded libraries match published checksums and expected file types.
- [ ] Failed or unavailable target checks remain explicit; building is not device validation.
- [ ] The user receives a run URL, artifact list and clear disk-use explanation.

## Out of Scope

Full Flutter app builds, signing, installation, device validation, release publishing,
automatic deletion of local files, and changing the application/runtime ABI.
Apple pod/app integration remains outside this first CI validation.
