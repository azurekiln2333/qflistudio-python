# Trilingual README rewrite

Date: 2026-10-26. Owner: documentation worker for
`10-22-python-offline-tools`.

## Scope and ownership

This batch owns `README.md` (Simplified Chinese, default), `README.zh-TW.md`
(Traditional Chinese) and `README.en.md` (English), plus this note. It did not
change `lib/`, `native/`, `assets/`, `tool/`, `test/`, specs, lint rules or any
other worker's files. No staging, commit or push.

The pre-existing uncommitted HarmonyOS HAP section in `README.md` came from
another worker. Its facts are preserved in the rewrite.

## Sources used

- Source: `lib/main.dart`, `app_startup.dart`, `python_runner.dart`,
  `python_tools_page.dart`, `python_terminal.dart`, `python_packages.dart`,
  `python_code_analyzer.dart`, `python_debugger.dart`, `python_ffi.dart`,
  `python_module_catalog.dart`, `python_native_library.dart`.
- Assets: `assets/python_stdlib/manifest.json` and `PROVENANCE.md` (10 bundled
  modules), `lib/python_module_catalog.dart` (17 built-in modules).
- Native docs and build: `native/README.md`, `native/PLATFORMS.md`,
  `native/lifecycle.md`, `native/desktop/build.sh`, `native/linux/CMakeLists.txt`,
  `native/windows/CMakeLists.txt`, `native/build.ps1`,
  `native/desktop/build.ps1`.
- Platform: `ohos/entry/src/main/module.json5`,
  `ohos/entry/src/main/ets/entryability/EntryAbility.ets`,
  `ohos/entry/build-profile.json5`, `ohos/AppScope/app.json5`,
  `ohos/entry/src/main/module.json5` permissions.
- Specs: `.trellis/spec/frontend/{index,python-workflow,python-offline-host,
  native-startup,directory-structure,quality-guidelines}.md`,
  `.trellis/spec/backend/{index,native-python-runtime,python-ffi,
  python-offline-packages,android-build,quality-guidelines}.md`.
- Evidence: `build/python-release-evidence/final-artifacts-platform.json`,
  `build/python-ohos-audit-build.json`,
  `build/offline-platform-review/negative-controls.json`,
  `.trellis/tasks/10-22-python-offline-tools/research/*.md`,
  `tool/test_python_offline_platform.cjs`.

## Structure of the three files

Each file has the same sections in the same order: language interlinks, product
summary, features, engine, platforms and verification status, offline policy,
limitations, bundled and built-in modules, local packages, debug sessions,
build, test and verification commands, layout table, more documentation.

## Accuracy limits encoded

- The engine is upstream MicroPython 1.24.1 (`ecfdd5d`). It is not CPython. No
  pip and no CPython C extensions.
- The platform table separates source implementation from verification. Android,
  Windows and Linux rows say "historical verification". A following sentence
  says the current-source final suite has not been re-run.
- HarmonyOS says acceptance is not complete. It records the 10-22 module HAP,
  states that the HAP predates the current FFI, and says the current-source
  final HAP and device acceptance are not complete. No "device failed" claim.
- The offline policy section records the current tracked source (no
  `ohos.permission.INTERNET`) and the historical 2026-10-15 signed HAP that
  listed `ohos.permission.INTERNET`. It asks for a fresh permission inspection
  after a new HAP install.
- `native/desktop/build.ps1` is described as building only the Windows DLL.
  Linux and macOS use `native/desktop/build.sh`, which drives CMake over
  `native/desktop` with target `qfli_py_ffi`.
- Debug sessions note that ordinary runs still pay the tracing cost and that
  current performance verification is not complete. Device acceptance for
  debugging is not complete.
- Module lists describe the tested scope only and make no CPython-compatibility
  claim.

## Checks run on this host

- `python scripts/ste-lint-zh.py README.md README.zh-TW.md`:
  `README.md` 0 hard violations, `README.zh-TW.md` 0 hard violations, 0 total
  findings.
- Language links resolve: each file links `README.md`, `README.zh-TW.md` and
  `README.en.md`, all present.
- All inline-referenced paths exist: `native/README.md`, `native/PLATFORMS.md`,
  `native/lifecycle.md`, `native/desktop/build.sh`, `native/linux/CMakeLists.txt`,
  `assets/python_stdlib/PROVENANCE.md`, `assets/python_stdlib/manifest.json`.
- Cross-version anchors present in all three files: `1.24.1`, `ecfdd5d`, `46`,
  `34/34`, `65/65`, `4096`, `2 MiB`, `16 MiB`, `16 KiB`, `2026-10-01`,
  `2026-10-15`, `27.0.12077973`, `com.azurekiln.qfli.pyflow`, `arm64-v8a`.
- Traditional file reviewed by hand for simplified-form leakage. The nav label
  was changed to `簡體中文`. Remaining flagged words (`平台`, `移植`, `取消`,
  `快照`, `建置`, `限制`, `政策`, `交易`, `摘要`, `文件`) are shared
  Traditional/Simplified forms, not leaks.
- No `D1`, no "not yet repackaged into OHOS", no "device not passed" wording
  remains in any of the three files.

## Not run

No Flutter, analyzer, test, native build, SDK, HAP packaging or device command
was run for this documentation batch. Those remain coordinator gates. The
documented verification results are historical and are labelled as such.
