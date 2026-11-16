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
| Apple | [43942603480](https://github.com/azurekiln2333/qflistudio-python/actions/runs/43942603480) | Success | iOS XCFramework and macOS universal dylib |

The first Apple run, `43940473070`, remained queued for over eleven minutes with
`runner_id=0` for both jobs. A one-line workflow change selected the existing Intel
Mac image with the same Xcode 16.4 installation. The new push cancelled the queued
run through workflow concurrency. This changes the executed macOS test architecture
to x86_64; both output architectures remain required.
The Intel macOS job received a runner after about sixteen minutes, then passed
in 56 seconds. The iOS job passed in 49 seconds. Both jobs completed before
2026-11-17 04:03 Asia/Shanghai (2026-11-16 20:03 UTC).

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
| `native-macos-universal` | 404,219 | 820,824 |
| `native-ios-xcframework` | 800,018 | 2,022,064 (two archives combined) |

The workflow requests 14-day retention. These run artifacts expire around
2026-11-30 19:33-20:03 UTC (2026-12-01 03:33-04:03 Asia/Shanghai).
They are Actions artifacts, not Release attachments or application installers.

Both Apple ZIPs passed CRC and checksum verification after download. The Mach-O
parser checked the actual object files inside the static archives and both slices
of the universal dylib: macOS ARM64/x86_64 platform 1, iOS device ARM64 platform 2,
and simulator ARM64/x86_64 platform 7. XCFramework metadata contains exactly two
library variants. The macOS debugger report records 30 tests, no failures/errors,
and the exact SHA256 of the downloaded dylib. Test execution was on x86_64.
Independent Apple review confirmed exact checksum coverage, source/run metadata,
license and public-header byte parity, all sixteen required public exports per
architecture, and macOS libSystem-only dependencies with the expected install ID.

## Validation boundaries

- Android: native compilation and ELF dependency/alignment checks; no device run.
- OHOS: native compilation, dependency and provenance checks; no device run.
  Cloud SDK is OpenHarmony 6.1.0.31 / API 23. Local DevEco is 26.0.0.105 / API 26.
- Apple: all builds and binary inspections passed. The macOS x86_64 debugger
  suite passed. macOS ARM64 and iOS device/simulator execution were not performed.
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
All selected native cloud jobs and artifact checks subsequently passed. These
results do not close the independent full-application or device acceptance gates.

See `findings.md` for disk inventory and historical runs before the target correction.
