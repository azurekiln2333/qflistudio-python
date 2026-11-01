# Native provenance Pi review

Date: 2026-10-26. Reviewer: native provenance implementer (Pi). Exclusive
scope: `tool/python_native_provenance.py`, `test/python_native_provenance_test.py`
and the provenance hook in `native/build.ps1`. No subagent was spawned.

## Scope, constraints and conclusion

The task was to check the saved provenance work against the real configured
build, hash the real tools, rules, host Python and SDK inputs, keep the
regen/reconfigure/clean-first hook, run the light synthetic Python tests, and
report facts plus un-run items. This review must not run a compiler, Flutter,
the SDK, WSL, HAP packaging or a device, and must not commit.

The saved implementation matches the real configuration. Two defects were found
and fixed inside the owned files. No other owned behavior changed. No compiler,
SDK, build, Flutter, HAP or device command was executed.

## Verified facts from the real configured build

The real directories are `native/build/cmake-arm64-v8a` and
`native/build/cmake-x86_64`. Both use `CMakeFiles/3.28.2/`.

### Cache has no compiler or sysroot entry

Both `CMakeCache.txt` files contain no `CMAKE_C_COMPILER:` entry, no
`CMAKE_CXX_COMPILER:` entry and no `CMAKE_SYSROOT:` entry. They do contain
`CMAKE_AR:`, `CMAKE_RANLIB:`, `CMAKE_LINKER:`, the `CMAKE_C_COMPILER_AR:` /
`CMAKE_C_COMPILER_RANLIB:` variants and their CXX twins, plus
`OHOS_ARCH:UNINITIALIZED=arm64-v8a` or `x86_64`. The tool sets
`CMAKE_C_COMPILER_AR` apart from `CMAKE_C_COMPILER` by splitting the cache key
at the first `:` and then at `=`, so these variants never stand in for the
compiler. The generated compiler metadata wins over the cache for every role.

### Compilers and implicit directories come from the generated metadata

`configured_variables()` reads only `CMakeFiles/*/CMakeCCompiler.cmake` and
`CMakeFiles/*/CMakeCXXCompiler.cmake`. On the real files this resolves:

| ABI | role | configured path |
| --- | --- | --- |
| both | cCompiler | `.../native/llvm/bin/clang.exe` |
| both | cxxCompiler | `.../native/llvm/bin/clang++.exe` |
| both | linker | `.../native/llvm/bin/ld.lld.exe` |
| both | ar | `.../native/llvm/bin/llvm-ar.exe` |
| both | ranlib | `.../native/llvm/bin/llvm-ranlib.exe` |

All five paths exist. `resolve_roles()` rejects a role whose configured path is
missing.

`CMAKE_C_IMPLICIT_INCLUDE_DIRECTORIES` on the real files lists the clang
resource dir, `sysroot/usr/include/<triple>` and `sysroot/usr/include`, but not
libc++. `CMAKE_CXX_IMPLICIT_INCLUDE_DIRECTORIES` adds
`llvm/include/libcxx-ohos/include/c++/v1`. `sdk_directories()` unions the C and
CXX lists, so the extensionless libc++ headers are inside the captured
boundary. The arm64 build resolves to these four include directories and four
link directories (deduplicated and resolved):

- include: `llvm/include/libcxx-ohos/include/c++/v1`,
  `llvm/lib/clang/15.0.4/include`, `sysroot/usr/include`,
  `sysroot/usr/include/aarch64-linux-ohos`
- link: `llvm/lib/aarch64-linux-ohos`,
  `llvm/lib/clang/15.0.4/lib/aarch64-linux-ohos`, `sysroot/usr/lib`,
  `sysroot/usr/lib/aarch64-linux-ohos`

The x86_64 build resolves to the same shape with `x86_64-linux-ohos`. No
`CMAKE_SYSROOT` is needed, because the implicit lists already carry the sysroot
paths. The sysroot branch in `sdk_directories()` stays inert on this cache.

### Hash of real tools, rules, host Python and SDK inputs

Hashing used the tool's own `identity()` and `sdk_identities()` and read files
only.

Toolchain (identical bytes for both ABIs, since both use the same NDK):

| role | bytes | sha256 |
| --- | --- | --- |
| clang.exe | 106704824 | `3688d7912c1559c7fa7842e1a7ecb90aca32898eaed1f51ca449b9d49577d2ba` |
| clang++.exe | 106704824 | `3688d7912c1559c7fa7842e1a7ecb90aca32898eaed1f51ca449b9d49577d2ba` |
| ld.lld.exe | 65278904 | `27628fed00f2bca9d1528391bdb6c08a933e254a62d4493a5072c12fe352f11a` |
| llvm-ar.exe | 16797112 | `e30f494ff4bb165e65f85241f6a1abe0ce9ad73e5ea3bd4956c1958d5add84db` |
| llvm-ranlib.exe | 16797112 | `e30f494ff4bb165e65f85241f6a1abe0ce9ad73e5ea3bd4956c1958d5add84db` |

`clang.exe` and `clang++.exe` are byte-identical. `llvm-ar.exe` and
`llvm-ranlib.exe` are byte-identical. Content hashing still identifies each
configured path, and a swap to a different binary changes the digest.

Build tools and host Python:

| input | bytes | sha256 |
| --- | --- | --- |
| `build-tools/cmake/bin/cmake.exe` | 11936736 | `60513fa0fa68f7a339c0eecf59d903f4207634d624830bf243149dfd3148406e` |
| `build-tools/cmake/bin/ninja.exe` | 638904 | `10c6cb1c87c9c523e9f620c18a2437247eae72531e86a58d2b3676f5c5786500` |
| `build/cmake/ohos.toolchain.cmake` | 17384 | `0584729091676af239535182d9133761217cfff0f8599acf2ea2c9e394025731` |
| DevEco host `python.exe` | 91648 | `c8adb437f425902d32ed34e3c747c82f401e3a20ba4562d57142f84511c8a95d` |

Build rules and generated configure inputs:

| file | ABI | bytes | sha256 |
| --- | --- | --- | --- |
| `CMakeFiles/rules.ninja` | arm64 | 3615 | `7f9f92fd7404a6ee5fe08f5de3018d42ada9075e98c12decf89f3f0b7776c205` |
| `build.ninja` | arm64 | 146670 | `624ab7739acee87fd2851bab4c15e421951bc29044302a859785efb30bcec5e9` |
| `CMakeCache.txt` | arm64 | 18909 | `66418b162da736474807fd3a7e212659a0397a4c405a20b98941a892679d5a39` |
| `CMakeFiles/3.28.2/CMakeCCompiler.cmake` | arm64 | 3522 | `7a6b170182e25ebac529faee4cbfca1f7cd19d0bf700ac5bb3ca942adf88ec11` |
| `CMakeFiles/3.28.2/CMakeCXXCompiler.cmake` | arm64 | 6581 | `ea9cdb96e0886839c8377e31c19fdaea7e9008513020492fc779dceacbe880fd` |
| `CMakeFiles/rules.ninja` | x86_64 | 3609 | `c8389490b33e3cf7863ba3ed638edb426762dab8784506924fda3e91406acc2a` |
| `build.ninja` | x86_64 | 146639 | `33354960f372e0306edda3d22cbd781c8dc0f23d92221e6c07cf985c2f00cad9` |
| `CMakeCache.txt` | x86_64 | 18894 | `63a48f909f5032f7fadb8a5bfd0eb24571dc8ecd3bdf482c90af3da4c6b249a2` |
| `CMakeFiles/3.28.2/CMakeCCompiler.cmake` | x86_64 | 3518 | `0105160e5a9e9f69a22a54fc5a57584c7d3f6f8433e45c22ff9ee5147e9fbeb5` |
| `CMakeFiles/3.28.2/CMakeCXXCompiler.cmake` | x86_64 | 6577 | `aa512681f7c0309b4f6f5c9886242b69a52cc955b44aae861aa77ce0df56fb64` |

SDK closure as `sdk_identities()` computes it (every file under the include
directories, plus every `lib*.a` / `lib*.so*` under the link directories):

| ABI | files | bytes | aggregate sha256 |
| --- | --- | --- | --- |
| arm64-v8a | 3530 | 157044472 | `7fca0aa227c3dbaebf7822d8384caea6905b09df259e9eaaf2868184022cf21b` |
| x86_64 | 3533 | 158145920 | `705da13af6e4a271dfb4d4496f2a7ad0c5a21912b3dec07c65472f4f417f70f4` |

The aggregate hashes each sorted `path + digest` pair. Extensionless libc++
headers inside the libc++ `v1` directory number 141 in both ABIs. Examples:
`__assert` `dd7420a617f51fb9b909117403fd435fb665cf23d3bb71327f758e1ed284e8e9`,
`__availability` `8d072444914e86615426195b473fab1d3860fbde74063c41efe2939396dca293`,
`__bit_reference` `1546d08c85c87033c102d44f7e06b0886b635dae06f7f5e0db6510d60dc202c6`.
Static libraries matching the link filter number 65 (arm64) and 67 (x86_64).
Examples: `llvm/lib/aarch64-linux-ohos/c++/libc++_static.a`
`2bf91128280175dd8448fba8eee77770edb44f1a1996807e7520f0fea9dadd0c` and
`libc++experimental.a` `0935b5ae6c9cf23a1cd145c1b03fcb3def516ea8f8963378bb968e085c38b1e4`.
The runtime guard therefore has real inputs to pass: at least one extensionless
libc++ header and at least one `.a` file are present in both closures.

### Generated inputs are not Ninja outputs

`build.ninja` has zero edges whose output is an `embed/genhdr` file.
`qfli_py_regen` is a phony target whose `CUSTOM_COMMAND` declares no file
output. Therefore `cmake --build --clean-first` will not delete or regenerate
the fingerprinted `embed/genhdr/*` headers between capture and finish. This
matters because `embed/genhdr/mpversion.h` embeds
`MICROPY_BUILD_DATE "2026-10-08"`: a regeneration inside the build window would
change a captured digest. The current hook regenerates once, before capture, so
capture and finish observe the same bytes within one run.

## The build.ps1 hook

`git diff native/build.ps1` adds `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON` to the
shared `$configureArgs`, then, in order: `qfli_py_regen` target, reconfigure
with the same args, `capture`, `--clean-first --target qfli_py`, dependency
check, `finish`, then the existing copy. The regen/reconfigure/clean-first
sequence is preserved. `capture` passes `--python $Python` and
`--tool $Cmake --tool $Ninja --tool $Toolchain`, so the host Python, CMake,
Ninja and toolchain file are fingerprinted by role and as extra tools. `finish`
can read the host Python identity from the stored `toolRoles`. Capture failure
and finish failure both abort before staging.

## Defects found and fixed inside the owned files

1. Stale test expectation. `test_included_ninja_rule_drift_is_rejected`
   expected the message `inventory changed`. An already-saved change added
   `CMakeFiles/rules.ninja` to `sourceDigests` (confirmed by
   `test_ninja_rules_are_fingerprinted`), so the direct per-source digest check
   now fires first with `input changed`. The test was red for that reason. It
   now expects `input changed` and explains why. Both outcomes reject the build;
   only the message and order changed.

2. Opaque error on a missing compile database. `snapshot()` opened
   `compile_commands.json` inside the `identity()` comprehension, so an absent
   file raised a bare `FileNotFoundError`. That is the live state of both real
   build directories (see below). `snapshot()` now checks for the file first and
   raises `ValueError("Configured build omits compilation commands: ...")`. A
   new synthetic test `test_missing_compilation_commands_is_rejected` covers it.

No other logic changed. The `identity`, `configured_variables`,
`resolve_roles`, `sdk_directories`, `sdk_identities`, `verify`, `finish` and
`save` behavior is unchanged.

## Synthetic tests executed

Every fixture file is inert metadata; the suite starts no compiler, SDK tool,
build or device. Command:

```
$env:PYTHONPATH='.'
python -m unittest discover -s test -t test -p "python_native_provenance_test.py" -v
```

Result: 29 tests, all pass. The suite was 28 tests with one failure before the
fix. Coverage includes: compiler roles taken from generated metadata rather than
the cache; extensionless libc++ and `.a`/`.so` fingerprinting; `rules.ninja`
fingerprinting and drift; generated `vm.c` drift; new compilation input;
compiler swap via metadata; host Python change; extensionless header, static
library and removed header drift; substituted SO; wrong ABI with a matching
digest; pending/failed build and wrong schema rejection; missing/ambiguous
compiler metadata; missing configured compiler; missing required role; missing
host Python; missing SDK directory; missing Ninja rules; missing compile
database; and manifest shapes that omit a role, Python, SDK inputs, the
extensionless libc++ header or the static libraries.

`python -m py_compile` on both owned Python files is clean.

The naive `python -m unittest test.python_native_provenance_test` fails with
`ModuleNotFoundError: No module named 'test.python_native_provenance_test'`.
The local `test/` directory has no `__init__.py`, so the stdlib `test` package
shadows it. The working command above uses `-s test -t test` plus
`PYTHONPATH=.`, matching the `from tool.X import ...` convention already used by
`test/python_audit_inputs_test.py`. The root `test-run.log` records the failing
naive form. That log is not mine to fix and was left in place.

## Not run (open gates)

- No `capture`, `finish` or `verify` was run against a real build directory.
  Both real build directories have `CMAKE_EXPORT_COMPILE_COMMANDS:BOOL=` empty
  and no `compile_commands.json`, so `snapshot()` would now stop with the new
  explicit error. A fresh `native/build.ps1` configure (which passes
  `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`) is required to produce the file. Only
  the unit functions (`configured_variables`, `resolve_roles`,
  `sdk_directories`, `sdk_identities`, `identity`) were exercised on real data.
- No native build was compiled. No `.so` was produced or checked for ABI. The
  regen/reconfigure/clean-first hook was read, not executed.
- No `native-build-evidence.json` exists anywhere in the tree.
  `tool/build_python_ohos_audit.ps1` defaults to
  `native/build/cmake-x86_64/native-build-evidence.json` and throws until a
  current x86_64 build writes one. That audit path was not run.
- No Flutter, Dart analyzer, OHOS audit, HAP packaging, WSL or device step ran.
  This review does not establish installed-app behavior.

## Risks and observations

- The SDK closure hashes about 150 MiB across roughly 3530 files. A single
  `snapshot()` therefore reads the whole SDK twice per build (capture and
  finish). Measured hashing time was about 2 to 3 seconds per ABI on this host
  with a warm cache. This is a deliberate trade for detecting header and
  library drift; it is not a cheap check.
- Capturing `embed/genhdr/*`, including the 9 MiB `qstr.i.last`, ties the
  manifest to generated header content. That is intended. If a future hook ever
  runs `qfli_py_regen` between capture and finish, `mpversion.h` and the other
  generated files change and `finish` will correctly refuse the output.
- The tool hashes `clang.exe` and `clang++.exe` to the same digest on this SDK.
  A check that only compared digests could not tell them apart, but the tool
  checks each configured path for existence and hashes it independently, so a
  path swap to a different binary is still detected.
- The `sdk_directories()` sysroot branch only runs when `CMAKE_SYSROOT` is in
  the cache. It is not on this configuration. The OHOS architecture mapping for
  that branch therefore remains source-only, unexercised by real data.

## Files changed by this review

- `test/python_native_provenance_test.py`: fixed the rules-drift expectation;
  added the missing-compilation-commands regression.
- `tool/python_native_provenance.py`: explicit error for an absent
  `compile_commands.json`.
- This note. `native/build.ps1` was read and left unchanged; its saved hook
  already matches the requirement.

No commit was created.
