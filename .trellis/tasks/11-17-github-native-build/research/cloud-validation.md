# Cloud validation (2026-11-17, Asia/Shanghai)

## Published source

- Repository: `azurekiln2333/qflistudio-python`.
- Branch: `ci/native-build-20261117`.
- Implementation: `271fff0b314794a6d8033be9fff4a1bee337325a`.
- Apple runner selection: `03ffbb744219f6797a00519265c62f441801592d`.
  This changes only the hosted Mac label to `macos-15-intel`.
- Separate license commit: `c535f60`,
  `docs(license): align GPL-3.0 licensing with qflistudio`.
- The root LICENSE matches `D:/MyNewProjects/qflistudio/LICENSE` byte-for-byte.
  SHA256: `3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986`.
- Pushes used the explicit GitHub URL because origin has multiple push destinations.

## Runs and artifacts

| Workflow | Run | Observed result | Artifacts |
| --- | --- | --- | --- |
| Android | [43940472797](https://github.com/azurekiln2333/qflistudio-python/actions/runs/43940472797) | Success | ARM64, ARM32 and x86_64 |
| OHOS | [43940473063](https://github.com/azurekiln2333/qflistudio-python/actions/runs/43940473063) | Success | ARM64 and x86_64 |
| Apple | [43942603480](https://github.com/azurekiln2333/qflistudio-python/actions/runs/43942603480) | Queued at initial observation | Pending |

The first Apple run, `43940473070`, remained queued for over eleven minutes with
`runner_id=0` for both jobs. A one-line workflow change selected the existing Intel
Mac image with the same Xcode 16.4 installation. The new push cancelled the queued
run through workflow concurrency. This changes the executed macOS test architecture
to x86_64; both output architectures remain required.

All completed Android/OHOS artifacts were downloaded. ZIP CRC, all published
SHA256 entries and ELF machine identifiers passed. OHOS provenance output digests
match the downloaded libraries. Each OHOS ABI records 143 compile commands.
An independent review also compared both license files byte-for-byte with the
checkout, confirmed the exact source commit and full checksum-manifest coverage,
and parsed actual ELF dependencies and LOAD alignment from each downloaded library.
All Android LOAD segments are aligned to 16,384 bytes.

`verified-artifacts.json` records artifact IDs, download URLs, exact byte counts,
expiry timestamps, library digests, ZIP members and inspected binary architectures.
The verification checks the downloaded bytes, not only workflow status.

| Artifact | ZIP bytes | Library bytes |
| --- | ---: | ---: |
| `native-android-arm64-v8a` | 987,180 | 3,020,872 |
| `native-android-armeabi-v7a` | 874,084 | 2,166,772 |
| `native-android-x86_64` | 976,074 | 2,856,592 |
| `native-ohos-arm64-v8a` | 1,265,091 | 2,551,776 |
| `native-ohos-x86_64` | 1,251,591 | 2,422,312 |

The workflow requests 14-day retention. These run artifacts expire around
2026-11-30 19:33-19:35 UTC (2026-12-01 03:33-03:35 Asia/Shanghai).
They are Actions artifacts, not Release attachments or application installers.

## Validation boundaries

- Android: native compilation and ELF dependency/alignment checks; no device run.
- OHOS: native compilation, dependency and provenance checks; no device run.
  Cloud SDK is OpenHarmony 6.1.0.31 / API 23. Local DevEco is 26.0.0.105 / API 26.
- Apple: cloud execution remains pending until a hosted runner is assigned.
- No APK, AAB, HAP or IPA is produced. Flutter app integration/signing and installed
  runtime acceptance remain separate from native library publication.
- Existing local caches, emulator state, app packages and reports were preserved.

## Local checks

Actionlint passed for all three workflows. Bash syntax and embedded Python syntax
checks passed. Apple platform validation passed ten synthetic positive/negative
cases. The GPL license byte comparison and changed Chinese snippet checks passed.
No local full native SDK or Flutter app build was needed for this CI change.
The final full-scope static review found no blocking issue. The Intel runner YAML
passed actionlint, both context manifests validated and `git diff --check` passed.
The pending Apple run remains an independent build/runtime gate.

See `findings.md` for disk inventory and historical runs before the target correction.
