# Current-source Windows and POSIX native build readiness

Date: 2026-10-26. Owner: Python read-only preparation for
`10-22-python-offline-debugger`. Source and document only.

Nothing was executed. No compiler, CMake, Ninja, GCC, Python, Git, Flutter,
Dart, SDK, WSL, native test, HAP, signing, device or channel command ran, and no
tool version was printed. Only file lookups, file sizes, SHA256 hashes and reads
of maintained scripts, CMake caches and recorded reports were used. No script,
source, product file or build profile was changed. Only this note was written.

This covers the desktop Windows and POSIX/Linux current-native libraries, the
native test suites and the ordinary-run cost comparison. The OHOS ABI path is
the separate note `current-ohos-native-build-readiness-20261026.md`. Real builds
need a later distinct C build grant; nothing here authorizes a build or run.

## Status, in three layers

- **Build-source readiness: prepared, pending a grant.** Both standalone drivers
  exist, both compile `src/qfli_py_debug.c` into the library, and the tracked
  `native/micropython_embed` package is present. No build ran.
- **Build output: not produced for the current source.** No current-source
  Windows DLL and no POSIX `.so` exist. Today's libraries are frozen prebuilts
  that predate the current source.
- **Test, cost, acceptance: open.** `ordinary100`, `debugger28` and the A/B cost
  comparison are real commands with recorded reports, but every recorded report
  predates the current source and none was re-run here.

## Prerequisite tool paths (file lookup only)

From the last configure caches and the maintained README, not from execution.

| Role | Path | Source |
| --- | --- | --- |
| C compiler (Windows) | `D:/ProgramFiles/Dev-Cpp/MinGW64/bin/gcc.exe` | `native/build/windows/CMakeCache.txt` |
| CMake / Ninja (Windows) | `D:/ProgramData/Android/Sdk/cmake/3.22.1/bin/{cmake,ninja}.exe` | same cache |
| Generator / build type (Windows) | `Ninja` / `Release` | same cache |
| CMake (POSIX) | `/usr/bin/cmake` | `native/build/linux/CMakeCache.txt` |
| C compiler (POSIX) | `cc` | same cache |
| Embedding package | `native/micropython_embed` | required by both desktop CMake lists |
| POSIX host Python | `python3` on `PATH` | `native/tests/run_debugger_host.sh` |
| Prior POSIX WSL distro | `qfli-java-build` | `native-debugger-implementation.md` |

Missing or not resolvable (accurate gaps):

- `native/build/linux/CMakeCache.txt` records `CMAKE_MAKE_PROGRAM-NOTFOUND`.
  `build.sh` only picks Ninja when `command -v ninja` succeeds, else Make. A
  POSIX window cannot assume Ninja.
- No POSIX baseline library exists for the A/B cost comparison (only a Windows
  baseline). A POSIX A/B run is impossible until a POSIX baseline is produced.
- No maintained Windows script exists for `ordinary100` (`smoke.c` is POSIX-only,
  see below).
- No desktop provenance manifest tool exists: `tool/python_native_provenance.py`
  is OHOS-ELF only and is wired into the OHOS driver, not either desktop driver.

## Frozen artifacts that must survive

| Path | Bytes | SHA256 |
| --- | --- | --- |
| `native/build/windows/qfli_py_ffi.dll` | 745758 | `52e7400fdcd50cb03d94026ad6331c3b27770e2795e3418259d54e4d3a79a54e` |
| `build/qfli_py_ffi-debugger-stable.dll` | 745758 | `52e7400f…` (identical) |
| `build/qfli_py_ffi-module-foundation-2329ef7d.dll` | 714418 | `2329ef7d374e35dd5159db0f3f056b094effc9a0372ad29fe704af472a6c309f` |
| `native/build/host/libqfli_py_debug_test.so` | 557432 | `e77addddd488c8a49dc8f47edfb63b221c4c74e7a5682a7883341d34eb27da4f` |

## Exact isolated builds

**Windows** — `native/desktop/build.ps1` (CMake 3.15+, Ninja, MinGW GCC; no
Visual Studio or Flutter). Its default `BuildDir` is `native/build/windows`,
whose output is the frozen stable DLL, so `-BuildDir` is mandatory:

```powershell
.\native\desktop\build.ps1 -BuildType Release `
  -BuildDir build\current-native-<GRANT>\windows `
  -CMake D:\ProgramData\Android\Sdk\cmake\3.22.1\bin\cmake.exe `
  -Ninja D:\ProgramData\Android\Sdk\cmake\3.22.1\bin\ninja.exe `
  -Compiler D:\ProgramFiles\Dev-Cpp\MinGW64\bin\gcc.exe -Jobs 2
```

Artifact: `build/current-native-<GRANT>/windows/qfli_py_ffi.dll` (driver prints
its absolute path and fails if absent). It resolves tools (explicit > `PATH` >
Android-SDK `cmake`), prepends the compiler dir to `PATH`, configures with
`-S native/desktop`, builds target `qfli_py_ffi`. `desktop/CMakeLists.txt` sets
`PREFIX ""`, `_WIN32_WINNT=0x0601`, and `-static-libgcc` on MinGW; it does not
regenerate the embedding package.

**POSIX** — `native/desktop/build.sh`; isolate with `QFLI_PY_BUILD_DIR`:

```sh
QFLI_PY_BUILD_DIR="$PWD/build/current-native-<GRANT>/linux" \
QFLI_PY_BUILD_TYPE=Release QFLI_PY_JOBS=2 sh native/desktop/build.sh
```

Artifact: `build/current-native-<GRANT>/linux/libqfli_py_ffi.so`. It maps the
kernel to `linux`/`macos`, picks the generator, configures `-S native/desktop`,
builds target `qfli_py_ffi`. Non-Windows adds `MICROPY_GCREGS_SETJMP=1`,
`MICROPY_NLR_SETJMP=1`, PIC, and links Threads + `m`.

## Native test suites

**ordinary100** — POSIX only. `sh native/tests/run_host.sh` compiles
`native/tests/smoke.c` with the embedding package plus `src/qfli_py_debug.c`
into `native/build/host/qfli_py_smoke` and runs 100 ordinary cases through the
legacy `qfli_py_run` ABI, printing `Native host smoke: 100/100 passed`. Exit 0
only when all pass. Recorded in `native-debugger-implementation.md`. `smoke.c`
uses `<dirent.h>`/`<unistd.h>` and `/proc/self/fd`, so **no Windows script is
maintained**; do not claim a Windows 100/100. There is no JSON reporter.

**debugger28** — `native/tests/debugger.py`, a `unittest` suite (`DebuggerTests`)
with exactly 28 `test_*` methods, portable via `ctypes`:

```powershell
python native\tests\debugger.py `
  build\current-native-<GRANT>\windows\qfli_py_ffi.dll `
  --report build\reports\python-native-debugger-current-<GRANT>.json
```

POSIX wrapper: `sh native/tests/run_debugger_host.sh` builds
`native/build/host/libqfli_py_debug_test.so` then runs the same script with
`--report ../build/reports/python-native-debugger-posix.json`. The report binds
`library` (absolute path), `sha256`, `kind: real-native-controller-thread`,
`tests: 28`, `passed`, `failures`, `errors`. Recorded prior results: 28/28
Windows and 28/28 POSIX, both predating the current source.

**A/B cost** — `native/tests/debugger_cost.py`, baseline first then current,
`--report` required. No debug session or callback; 9 samples/library after 2
warmups, identical-output assertion, then an allocation probe:

```powershell
python native\tests\debugger_cost.py `
  build\qfli_py_ffi-module-foundation-2329ef7d.dll `
  build\current-native-<GRANT>\windows\qfli_py_ffi.dll `
  --report build\reports\python-debugger-cost-current-<GRANT>.json
```

Report carries both libraries' `path`/`sha256`/`bytes`/`version`, all timings,
medians, `output`, `allocations` and `currentToBaselineMedianRatio`. Recorded
prior comparison (`2329ef7d…` vs `52e7400f…`): 714,418 → 745,758 bytes; median
0.0025912 → 0.0028340 s; allocation 1,760/2,144 initial and 32/32 incremental;
output `14901345\n`; **ratio 1.0937017601**. D1 strict ordinary-cost preservation
remains open; this note claims no improvement.

## Provenance that applies — and does not

- `tool/python_native_provenance.py` (`capture`/`finish`/`verify`) is **OHOS-ELF
  only**: it requires `kind == completed-python-native-build`, an OHOS triple and
  a `\x7fELF` output at machine 40/62/183. It is **not** wired into either
  desktop driver and rejects a PE DLL. Do not use it for desktop.
- `native/tools/check_so_deps.py` (ELF `DT_NEEDED`) and
  `tool/prepare_python_debugger_audit.py` (ELF64 + five `qfli_py_debug_*` exports)
  are ELF only; not desktop checks.
- Desktop provenance is therefore: caller SHA256 pinning before and after, plus
  the per-run reports that embed the exact library identity, plus
  `native/tools/debug_overlay_test.py` (overlay pinnedness, recorded 4/4) and
  `python tool/verify_python_modules.py --library <dll> --report …`.

Expected reports (all bind the library they ran; a current-source DLL must
produce **different** bytes than the recorded copies, so compare counts/schema):

| Report | Producer |
| --- | --- |
| `python-native-debugger-current-<GRANT>.json` | `debugger.py --report` |
| `python-native-debugger-posix.json` | `run_debugger_host.sh` |
| `python-debugger-cost-current-<GRANT>.json` | `debugger_cost.py --report` |
| `python-stdlib-with-debugger.json` | `tool/verify_python_modules.py --report` |
| (none) | `run_host.sh` (printed count + exit code only) |

## Isolation and provenance hazards

| # | Hazard | Mitigation |
| --- | --- | --- |
| H1 | `build.ps1` defaults `BuildDir` to `native/build/windows`, overwriting `52e7400f…` | Always pass `-BuildDir`; re-hash both `52e7400f…` copies afterward |
| H2 | `build.sh` defaults to `native/build/<platform>` | Always set `QFLI_PY_BUILD_DIR` |
| H3 | `run_debugger_host.sh` rebuilds `libqfli_py_debug_test.so` (`e77adddd…`) | Copy aside first, or record the intended replacement |
| H4 | `run_host.sh` hardcodes `build/host/qfli_py_smoke` | Accept; it is not a pinned artifact |
| H5 | Cost argument order baseline→current; passing one library twice yields a ~1.0 ratio | Use distinct, hash-checked paths; verify the report's two `sha256` differ |
| H6 | Cost output must match between libraries | Treat a mismatch as a behavior bug, not a cost result |
| H7 | `python_native_provenance.py` is OHOS-only | Do not run it on a DLL; use pinned hashes plus embedding reports |
| H8 | Windows has no maintained `ordinary100` script (`smoke.c` is POSIX-only) | Do not claim a Windows 100/100 |
| H9 | POSIX generator depends on `ninja` on `PATH` | Use a fresh build dir or set `QFLI_PY_GENERATOR` explicitly |
| H10 | Prior POSIX evidence used WSL `qfli-java-build` | Confirm the distro in the window; do not substitute silently |

## Maintained-script hashes (read-only, for binding)

| File | Bytes | SHA256 |
| --- | --- | --- |
| `native/desktop/build.ps1` | 3190 | `36871c44c86826e8c05d03fa6db3ccb15eeb312e592fcff9adcbb4ca4d3f78d5` |
| `native/desktop/build.sh` | 769 | `ee47be99d3fef69f7d132f45e0b7a52b62de91a53b119404c85201c421ecd574` |
| `native/desktop/CMakeLists.txt` | 3231 | `58af32405f829125202377546dba11e57f1319defe9ac348d5e7f013c3ab9aa3` |
| `native/CMakeLists.txt` | 13392 | `ab5e0d1a18597711df6dfc4c18eaf7f3cb8a989e3a96c53328650ea5544c6d28` |
| `native/tests/run_host.sh` | 586 | `81746111299788efbe0e09552fb1e84c14384492cd5ed469ef3e9922d86a8e84` |
| `native/tests/run_debugger_host.sh` | 794 | `7a8ecaf7338883d30f601e21e8201c24170be0fa28745bbe94a30186bdfa3f4e` |
| `native/tests/debugger.py` | 30543 | `23e479e0b927e70eba19c14c406ee71efe560e01545872798501619b56467959` |
| `native/tests/debugger_cost.py` | 4065 | `ffd90dae55c34cc0105b55221cce11d4e2ae5d58efe887e97614f71694cd362c` |

`native/CMakeLists.txt` matches the value in the sibling OHOS note, confirming
both notes read the same tracked file.

## Not run

No compiler, CMake, Ninja, GCC, Python, Git, Flutter, Dart, SDK, WSL, native test,
HAP, signing, hdc, device or channel command ran, and no version was printed.
Only file lookups, sizes, hashes, cache reads and report reads were used. No
file under `native/`, `ohos/`, `lib/`, `tool/`, `test/` or `qfli_studio_core/`
was created or modified. Only this note was written. Every command above is for
a later distinct coordinated C grant.