# README independent review (Pi)

Date: 2026-10-26. Reviewer: trellis-check reviewer (Pi). Direct review; no
subagent was spawned.

Verdict: **committable**. No blocking issue. The three READMEs agree with the
tracked source and with each other. Four low-severity wording notes appear below.

## Scope and method

Read-only review of the three delivered READMEs against the tracked source:

- `README.md` (Simplified Chinese, default)
- `README.zh-TW.md` (Traditional Chinese)
- `README.en.md` (English)

Checked the command list, the 17 built-in plus 10 bundled module counts, the
local-package limits, the split between historical verification and current
acceptance, and factual agreement across the three languages. No README, source,
spec or test file was edited. No Flutter, native, SDK, HAP, WSL or device command
was run. Only file reads, one Python text-comparison script and the Chinese
mechanical lint ran.

Date fix applied first: `research/native-provenance-pi-review.md` now reads
`Date: 2026-10-26`.

## Conclusion

The three READMEs are factually consistent with the tracked source. No blocking
error was found. The documentation batch is safe to commit.

## Commands

Every referenced path exists: `tool/python_ffi_smoke.dart`,
`tool/verify_python_modules.py`, `tool/test_python_offline_platform.cjs`,
`native/tools/inspect_so.py`, `native/tests/run_host.sh`,
`native/desktop/build.ps1`, `native/desktop/build.sh`, `native/build.ps1`,
`native/README.md`, `native/PLATFORMS.md`, `native/lifecycle.md`,
`assets/python_stdlib/PROVENANCE.md`, `assets/python_stdlib/manifest.json`.

Shown command forms match the source:

- `dart --packages=.dart_tool/package_config.json tool/python_ffi_smoke.dart
  native/build/windows/qfli_py_ffi.dll`: `tool/python_ffi_smoke.dart` accepts an
  optional single `[library]` argument. `.dart_tool/package_config.json` and
  `native/build/windows/qfli_py_ffi.dll` both exist.
- `python tool/verify_python_modules.py`: defaults `--library` to
  `native/build/windows/qfli_py_ffi.dll`, which exists.
- `node tool/test_python_offline_platform.cjs`: runs with no arguments
  (`process.argv.length <= 3`, optional source path).
- `python native/tools/inspect_so.py`: positional path is optional
  (`sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SO`).
- `native/desktop/build.ps1 -Compiler <gcc.exe> -CMake <cmake.exe> -Ninja
  <ninja.exe>`: the parameter names `-CMake`, `-Ninja` and `-Compiler` exist and
  the script builds target `qfli_py_ffi`.
- `sh native/desktop/build.sh`: configures `native/desktop` and builds target
  `qfli_py_ffi`. `native/linux/CMakeLists.txt` does `add_subdirectory(../desktop)`
  and re-exports `$<TARGET_FILE:qfli_py_ffi>`.
- `flutter build hap --release --target-platform ohos-arm64`: the same
  `--target-platform ohos-arm64` form appears in tracked task evidence (which also
  passes `--no-pub`).
- `adb -s emulator-5556 ...` and `hdc shell hilog -z 5000 -T QfliPyNative`:
  standard tool forms. The Android application id `com.azurekiln.qfli.pyflow`
  matches `android/app/build.gradle.kts`, and the NDK `27.0.12077973` matches
  `ndkVersion`.

## Modules 17 + 10

- Built-in 17: `lib/python_module_catalog.dart` defines exactly 17
  `PythonModuleInfo` entries in the order sys, math, cmath, json, random, time,
  re, binascii, heapq, array, collections, struct, io, errno, micropython, gc,
  builtins. The README lists match this order in all three languages.
- Bundled 10: `assets/python_stdlib/manifest.json` has `formatVersion` 1,
  `bundleVersion` v1, 10 modules and 10 files: base64, bisect, contextlib, copy,
  csv, functools, itertools, statistics, string, textwrap. The README lists match.

## Local-package limits

`lib/python_packages.dart` declares `_maxFiles = 4096`,
`_maxFileBytes = 2 * 1024 * 1024` and `_maxTotalBytes = 16 * 1024 * 1024`. It
accepts `.py`, directories, `.zip` and pure-source `.whl` (rejects a wheel unless
`Root-Is-Purelib` is `true`). It compile-checks each file through the injected
`syntaxCheck` (the app's VM), and a failed transaction rolls back (the manifest
moves last). The README limits and the accepted-type list match this source.

## Historical versus current acceptance

The platform table marks Android, Windows and Linux as historical, HarmonyOS as
"acceptance not complete", and iOS/macOS as "not verified". A following sentence
says the historical checks come from earlier builds and the current-source final
suite has not been re-run. The HarmonyOS paragraph states the 10-22 module HAP was
built, that it predates the current FFI, and that the current-source final HAP and
device acceptance are not complete. The debug section states current performance
verification and device acceptance are not complete.

The quoted historical numbers are backed by tracked evidence:

- `34/34`: `native/PLATFORMS.md` (2026-10-02 Windows MinGW standalone Dart FFI
  smoke).
- `65/65`: `native/PLATFORMS.md` (Linux CMake `libqfli_py_ffi.so`, filesystem
  effects and resource cleanup).
- `46/46` JNI self-checks: `.trellis/tasks/10-15-python-release-readiness/research/android-device.md`.
- `ANDROID_PROJECT_OK android Ada:42`, exit 0, 2026-10-01 x86_64 emulator:
  `native/README.md` and `.trellis/tasks/09-30-native-python-runtime/implement.md`.
- 2026-10-15 signed HAP listing `ohos.permission.INTERNET`:
  `build/python-release-evidence/final-artifacts-platform.json` (`checked_at`
  2026-10-15, HAP metadata lists `ohos.permission.INTERNET`).
- 10-22 module HAP: `build/python-ohos-audit-build.json` (`startedUtc`
  2026-10-22, `entry-default-signed.hap`).

Offline claims match source: `lib/main.dart` sets `isOffline: true`;
`ohos/entry/src/main/module.json5` requests only `ohos.permission.READ_PASTEBOARD`
and no `ohos.permission.INTERNET`; `EntryAbility.ets` sets `OFFLINE_ONLY = true`
and refuses `openAgreement`, `openUrl` and `login`.

Build-profile claims match: `ohos/entry/build-profile.json5` has
`"abiFilters": ["arm64-v8a"]` and excludes `**/x86_64/**` and
`**/armeabi-v7a/**`. Android `abiFilters` lists `armeabi-v7a`, `arm64-v8a` and
`x86_64`, matching the README's three-ABI statement.

Debugger claims match: `lib/python_debugger.dart` advertises
`supportsStepInto/StepOver/StepOut/StopOnEntry/StackFrames/Variables`, validates
breakpoints, and throws `UnsupportedError('请先保存文件；Python 调试器尚不支持未保存的源码快照。')`
for unsaved buffers.

## Trilingual consistency

A mechanical comparison found, and the root check independently confirmed:

- 12 `##` headings per file, in the same order. Text differs only by language.
- 9 fenced code blocks per file: the 7 command blocks are byte-identical, the
  directory tree is identical, and the engine diagram differs only by `或` vs
  `or`. The root report counts the same 7 command blocks.
- The three language links (`README.md`, `README.zh-TW.md`, `README.en.md`) are
  present in every file and resolve to existing files.
- 61 inline code tokens per file, with identical sets. No path, module name,
  number or identifier appears in one language and not another.
- Anchor counts agree across all three files: `1.24.1` 2, `ecfdd5d` 1, `46` 1,
  `34/34` 1, `65/65` 1, `4096` 1, `2 MiB` 1, `16 MiB` 1, `16 KiB` 1,
  `2026-10-01` 1, `2026-10-15` 1, `27.0.12077973` 1,
  `com.azurekiln.qfli.pyflow` 1, `arm64-v8a` 2, `x86_64` 3, `armeabi-v7a` 1,
  `libqfli_py.so` 4, `isOffline` 1, `OFFLINE_ONLY` 1, `input.txt` 2, `.mpy` 3,
  `ANDROID_PROJECT_OK` 1.
- Platform table rows agree row by row. The 17 and 10 module lists agree item by
  item. The local-package paragraphs agree on 4096, 2 MiB and 16 MiB.

## Chinese mechanical lint

`python scripts/ste-lint-zh.py README.md`: hard violations 0, baseline 0, findings
0 (1859 characters). `python scripts/ste-lint-zh.py README.zh-TW.md`: hard
violations 0, baseline 0, findings 0 (1935 characters). The console encoding
garbled the glyphs, but the counts are 0 for both files.

## Observations (not blocking)

- The 10-22 module HAP in `build/python-ohos-audit-build.json` is `x86_64`, while
  `ohos/entry/build-profile.json5` compiles only `arm64-v8a`. The README does not
  assign an ABI to the 10-22 HAP, so it makes no false statement. A future edit
  that touches this paragraph could name the audit build separately from the
  production build-profile to remove the surface ambiguity.
- `python tool/verify_python_modules.py` defaults to the Windows DLL. The README
  lists it without that prerequisite. The file exists, so the command is correct;
  a note would help non-Windows readers.
- The `flutter build hap` line omits `--no-pub`, which the tracked evidence used.
  It is an optional flag, not a wrong command.
- "该 HAP 早于当前 FFI" cannot be checked from tracked source alone, because the
  tree is uncommitted and has no usable history. It is consistent with the
  "acceptance not complete" framing.

## Commit decision

Yes. The documentation batch is factually consistent with the tracked source and
is safe to commit. The four observations above are low-severity wording notes, not
correctness blockers.

## Not run

No Flutter, analyzer, test, native build, SDK, HAP packaging, WSL or device
command ran. The README's documented verification results remain historical and
were checked for consistency with tracked evidence, not re-executed. This review
does not establish installed-app behavior.
