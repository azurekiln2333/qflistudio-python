# Python OHOS signed build evidence — 2026-10-26

Grant: global `qfli-core-release-sync` seq977,
`Python-OHOS-arm64-release-20261026-01`.

## Artifact

- Path: `build/ohos/hap/entry-default-signed.hap`.
- Size: 41,947,851 bytes.
- SHA256: `dafea8c19db2c9086ff1bf3965ae8caa9e5facb9b7097c1fd5a08f426e19b490`.
- Generated at: `2026-10-26T13:41:20.969805Z`.
- Bundle: `com.azurekiln.qfli.pyflow`.
- Version: `1.0.0`, packaged versionCode `1`, debug `false`.
- All three packaged native libraries use ARM64.
- Normal default signing succeeded. Independent SDK `verify-app` returned zero
  and reported digest verification and signature verification success.

## Native binding

The current-source PowerShell7 native build completed before staging.
The staged SO has SHA256
`3d00d2f0b907e29427fc598d7286390e1eababad614b49be626b2636edabb7ff`.
The packaged SO has SHA256
`70b859526eee0de21c4972182cdd19285a0a1a1a7abe623284afb106d90ca791`.
Its bytes match the exact SDK `llvm-strip --keep-section=.permission`
transformation and the Hvigor stripped intermediate. The nine required debugger
exports are defined GLOBAL symbols. This does not verify runtime behavior.

## Input comparison

The final comparison records zero core drift and eight product differences.
All eight paths are ignored generated copies under
`ohos/entry/src/main/resources/rawfile/flutter_assets/`.
Independent `git check-ignore -v` maps them to `ohos/.gitignore:17`.
No file under that generated directory is tracked. The source manifest remains
unchanged, and the differences remain disclosed in the original evidence.

## Process release and budget

Original build tool: `8cf65e`, session `85729`.
Its owning agent observed actual terminal exit zero with poll `19c64b`.
ACK, native, HAP, signature, strip and export roots each have terminal exit zero,
Job active count zero, closed handles and confirmed cleanup.

Final release publication is global seq991. Original publisher tool `31864d`
exited zero. Its exact root is PID55444, creation FILETIME
`134374961615959915`, Job252. The report records terminal zero, Job active zero,
closed handles, confirmed cleanup and no errors. Seq994 corroborates the actual
publisher terminal.

The orchestration entered at `2026-10-26T13:39:13.578414Z`.
Publisher completion was `2026-10-26T13:49:22.158619Z`.
Total elapsed time was **608.580205 seconds**. The 600-second total budget
**failed by 8.580205 seconds**. Artifact verification and resource release passed.
No automatic retry is authorized.

Evidence directory: `build/python-ohos-delivery-20261026/grant977/`.
The independent read-only review also confirmed the current local HAP size/hash.

## Delivery and remaining acceptance

The signed HAP was delivered through HDC to exact target
`192.168.68.207:46551`, model `MRT-AL10`, under fresh global1010.
Destination:
`/data/local/tmp/QFLIPython-1.0.0-arm64-20261026-signed.hap`.
Remote SHA256 and byte count match the verified local artifact.
This record claims no installation, application launch, debugger runtime pass
or original-example acceptance. Native debugger regressions and installed OHOS
acceptance remain open under the existing tasks.

## First transfer preflight and repair

Global998 ended before ACK and before any HDC client invocation.
Original tool `f59246` returned terminal exit1. The read-only server inventory
found HDC PID51932 at a Windows 8.3 executable path. A textual path comparison
falsely rejected that existing server. Global1004 corrected the initial
absence diagnosis. No transfer occurred.

The only owned inventory root, PID48976, FILETIME `134374973030597190`, Job412,
returned terminal zero, active zero, closed handles and confirmed cleanup.
Release publication global1002 used original tool `64df50`, terminal zero.
Its exact root PID8864, FILETIME `134374973345003606`, Job368, also has active
zero and closed handles. Local completion took 32.025266 seconds. C accepted
release independently in global1008, with conservative observed tool timing
33.392174 seconds. The first transfer grant is consumed.

The same ignored transfer runner now compares accessible executable file
identities through `os.path.samefile`. Both the implementer and independent
reviewer confirmed that the actual short and long paths refer to the same
file. Frozen runner SHA256:
`2bccdf04e2fd974a585c1c54a6fcb61c5572e2e08a15566dfcadbf3687896e58`.
Global1006 and global1009 publish source-only readiness for a new transfer
window. No automatic retry or server restart occurred.

## Verified file delivery under global1010

Original transfer tool `3c6610` returned terminal exit zero with no live session.
The transfer entered at `2026-10-26T14:16:15.622611Z` and finished at
`2026-10-26T14:16:20.188909Z`. The runner reports 4.569437 seconds.
Fresh local size/hash, the existing server file identity, exact connected
endpoint and model were checked before the owned ACK. Existing server PID51932
was preserved. One HDC file-send returned zero and reported:

```text
FileTransfer finish, Size:41947851, File count = 1, time:1890ms rate:22194.63kB/s
```

The exact-target remote verification returned zero with:

```text
dafea8c19db2c9086ff1bf3965ae8caa9e5facb9b7097c1fd5a08f426e19b490  /data/local/tmp/QFLIPython-1.0.0-arm64-20261026-signed.hap
41947851
```

All six owned phase roots have terminal exit zero, Job active count zero,
closed handles, confirmed cleanup and no errors. Their exact process identities
and reports remain under `build/python-ohos-delivery-20261026/transfer-1010/`.
No ADB, installation, application launch, server reset or SDK command ran in
this transfer window.

Release publication is global1012. Original publisher tool `92023c` returned
terminal exit zero. Its exact root is PID56012, creation FILETIME
`134374978104240575`, Job388. The publisher report records terminal zero,
Job active zero, closed handles, confirmed cleanup and no errors. It finished
at `2026-10-26T14:16:50.976631Z`, **35.354020 seconds** after transfer entry,
within the 60-second window for this actual final publisher completion.

The promised follow-up terminal corroboration before 60 seconds was late.
Global1013 was posted at `2026-10-26T14:17:29.449Z`, **73.826389 seconds** after
entry. Global1014 corrects that promise. The follow-up proof delay must not be
conflated with the earlier publisher terminal. This record does not claim that
all messages met the 60-second window.

C accepted file delivery and exact-target resource release in global1018 after
independently inspecting the original transcripts. C observed transfer tool
`3c6610` terminal zero at `2026-10-26T14:16:20.237Z` and publisher `92023c`
terminal zero at `2026-10-26T14:16:51.028Z`. The conservative entry-to-publisher
tool-terminal elapsed time was **35.405389 seconds**, below 60 seconds.
That acceptance retains the late global1013 follow-up disclosure. Global1010
is consumed. The target returned to C for separate successor admission.
File delivery and remote hash/size verification are complete. No installation,
retry or runtime acceptance is claimed.
