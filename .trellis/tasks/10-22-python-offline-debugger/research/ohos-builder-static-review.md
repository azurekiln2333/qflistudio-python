# OHOS audit builder: independent static review

Date: 2026-10-24. Owner: `/root/implement_python_debugger_native`.

Scope: source inspection of the builder, its synthetic PowerShell test, and the
three preparation schemas. Only this review note was written. None of the
reviewed scripts/tests was executed; no compiler, SDK command, Flutter build,
WSL process, signing command, device, or emulator was used. Root signing
configuration contents were neither read nor printed. The SDK implementation
behind the builder's Hvigor comment was not independently inspected.

## Conclusion

The existing staged-SO-to-archive and asset checks are useful exact-byte checks.
They do not establish that the staged SO was compiled from the current native
sources, or that the signed package contains this invocation's generated Dart
audit. Process execution also lacks a finite deadline. These are open acceptance
gates; this source review is not a successful build, signature verification,
runtime result, or validation of the source-only A+B debugger changes.

## Findings and minimal fixes

### 1. P1: external commands can indefinitely prevent restoration

`tool/build_python_ohos_audit.ps1:156`, `:179`, `:257`, `:325`, `:328`, `:331`
and `:348` invoke strip, strip-version, signature verification, preparation,
and Flutter directly with `&`. There is no deadline, bounded wait, cancellation
handler, or owned child-process-tree cleanup. Exit-code checks apply only after
the command returns. In particular, a hung Flutter/strip/signature process
keeps the temporary x86_64 entry profile, process environment, and local lock
active; the restoration `finally` at `:366` cannot run until control returns.
The Java heap limit bounds heap size, not elapsed time.

Minimal fix: use a shared process runner with explicit per-step deadlines,
redirected output drained during execution, and termination/wait of the exact
owned process tree before restoration. Include preparation and `--version`,
not only Flutter. Record timeout and termination outcomes in the report. A
small fake child that stalls, plus a child-spawning case, can verify this
without invoking the SDK or claiming a build/device result.

### 2. P1 acceptance gap: current native sources are not bound to the staged SO

The builder consumes the existing fixed x86_64 SO (`:31`, `:280`, `:325`–`:331`).
`Resolve-PythonNativeBinding` (`:126`) proves that the packaged Python SO equals
that staged input, or its exact locally reproduced strip output. It does not
rebuild the library or require a native build manifest.

The debugger preparer independently hashes current sources and the existing
binary (`tool/prepare_python_debugger_audit.py:117`, `:122`–`:137`). An older
debugger-capable SO can therefore be paired with newer source hashes and pass
the packaging check. Its byte-substring export guard (`:94`–`:104`) correctly
states its limited purpose; it neither resolves dynamic exports nor proves
current behavior. `buildMetadata` is optional, and the builder does not supply
or validate it.

The debugger source allowlist (`:16`–`:43`) also omits the actual generated
`native/micropython_embed/py/vm.c` and `emitglue.h` files carrying the A+B edits.
Hashing the overlay/generator alone cannot detect independent generated-source
drift. The module/content source lists contain no native compilation closure.

Minimal fix: require a native-build evidence manifest that records the actual
compiled source closure (including generated inputs), ABI, relevant build
options, toolchain identity, and output SO hash/size. Compare that output hash
to the staged SO and its source hashes to the reviewed source snapshot before
packaging. Keep the existing exact staged/strip/archive relation as the next
link in the chain. Until then, describe this report as packaging of declared
inputs; do not use it to close current-source native behavior or A+B cost gates.

### 3. P1 acceptance gap: recent signed HAP selection does not bind Dart audit identity

The candidate rule (`tool/build_python_ohos_audit.ps1:352`–`:356`) accepts any
`*-signed.hap` in one output directory with a modification time as early as two
seconds before the invocation, then chooses the newest. It does not require a
unique expected output or compare a pre-build artifact inventory. A recently
retained package can qualify if a nominally successful build leaves it in
place. The timestamp alone is not evidence of production by this invocation.

`Inspect-Hap` (`:202`–`:210`, `:239`–`:242`) requires runtime-library names and
the presence of `libapp.so` or one debug kernel, but does not bind that Dart
payload to `targetSha256`, `generatedPayloadSha256`, audit kind, suite/inventory,
or embedded build evidence. Local generated-file pre/post checks (`:336`–`:338`,
`:357`–`:359`) do not inspect compiled Dart bytes. For example, module and
debugger HAPs can share the same bundled assets and Python SO; the archive
checks cannot distinguish their entry points. Signature verification proves a
signature on the chosen file, not that it contains the requested audit entry.

Minimal fix: select the exact expected output using per-invocation artifact
identity rather than a filename glob/time tolerance; reject ambiguous outputs.
Bind the packaged debug kernel/app library to the actual build output and a
manifest of the generated inputs. Carry a fresh audit identifier in the
generated evidence and require the matching identifier in installed-runtime
acceptance. A copied JSON sidecar alone cannot prove which Dart program runs.

### 4. P2: inspection and signature verification reopen a mutable artifact path

`Inspect-Hap` records the HAP hash at `:233` and disposes its archive at `:246`.
The caller then invokes the signer on that path at `:363`. The report has no
post-verification artifact hash comparison and no read-only handle protecting
the same bytes across both operations. A path replacement after inspection
can therefore pair inspected content/hash from one package with verification
of another. The local script lock serializes this script, not every writer to
the normal build output directory. This is a mutation window, not evidence
that a mutation actually occurred in this review.

Minimal fix: make a uniquely named evidence copy under the audit build
directory and protect it against writes/replacement for inspection and signing
verification; recheck its hash afterward and report that retained copy. Recheck
the captured source/input snapshot after verification as well if the report
claims it remained current through the entire operation.

### 5. P2: source drift coverage differs substantially between audit kinds

`Assert-AuditSources` (`:72`–`:98`) correctly rehashes every declared product/core
source, plus the suite or content inventory/importer. Its coverage is exactly
the input allowlists. Module preparation (`tool/prepare_python_module_audit.py:57`
–`:71`) omits its own preparer, the OHOS module declaration, and shared-core
sources imported by the module harness. Content preparation
(`tool/prepare_python_content_audit.py:136`–`:155`) fingerprints only
`code_import_service.dart` from core, while the content harness also directly
imports project/tutorial models, app paths, and studio profile. Both omit
dependency/build-resolution inputs such as pubspec/lock/package configuration.
The debugger schema has broader core coverage but the native gaps in finding 2
remain. A change outside these lists is invisible to the source-drift check.

Minimal fix: define a shared, explicit audit source/build-input manifest and
extend it per audit kind, or collect the real build dependency closure. Include
the direct core imports used by each harness, preparers, module declaration,
and dependency-resolution identity. Treat this separately from proving the
native output's provenance: adding more current hashes alone does not solve
finding 2.

## Checks that are supported by the source

- Native binding (`builder:126`–`:181`) requires exact SHA256 and byte count.
  Identity is accepted directly; otherwise only the exact output of
  `llvm-strip --keep-section=.permission` qualifies. Transformation writes a
  separate build file and rechecks staged SO/tool hashes afterward. There is
  no version-string or fuzzy binary fallback.
- Content assets map to
  `packages/qfli_studio_core/<asset path>` and the sibling core source tree;
  bundled module assets retain product paths (`builder:52`–`:68`). Modules and
  debugger use product assets. Each declared asset requires one exact suffix
  match and agreement among archive, declared input, and current source hashes
  (`:220`–`:227`). Duplicate matching entries are rejected.
- Archive checks require one root `module.json`, reject the INTERNET permission,
  require exactly one Python/Flutter runtime entry, reject recognized foreign
  ABI native entries, and check each recognized SO's ELF64 little-endian x86_64
  header (`:189`–`:215`). These are structural/packaging checks. The 20-byte ELF
  check does not establish loadability, exports, dependencies, or behavior.
- Ordinary caught failures enter restoration. Original entry-profile bytes are
  retained in a unique recovery file; the script restores and hashes the entry
  profile, compares root-profile hashes, restores process Java options/location,
  and releases its lock (`:317`–`:322`, `:366`–`:391`). Root signing configuration
  is hashed, not rewritten. Abrupt termination/hangs remain outside that normal
  restoration guarantee; the recovery copy is useful in that case.
- Content preparation rejects absent required core assets, mismatched asset
  hashes, empty inventories, duplicate unit IDs, nonembedded units, absent code
  or behavioral expectations, and invalid fixture maps (`content prep:74`–`:112`).
  Debugger preparation checks containment and matching ArkTS source copies.

## What the synthetic test covers

`test/python_ohos_audit_build_test.ps1:8`–`:12` imports only function ASTs; it
does not run builder orchestration. Cases at `:100`–`:134` cover identity-bound
module/content/debugger asset mapping; INTERNET, changed/duplicate assets and
foreign ABI rejection; product/core source drift; and content inventory/importer
drift. No case exercises strip transformation success/mismatch/failure, actual
signature verification, artifact freshness/selection, restoration on a pipeline
failure, timeouts, or child cleanup.

The synthetic SO is a 20-byte header (`:74`–`:76`), and the debug kernel is one
byte (`:52`). The content fixture says `unitCount = 1158` while its inventory has
an empty units array (`:82`, `:97`). This is intentional helper-level test data,
not a schema-valid acceptance inventory or evidence of 1,158 executed units.
Do not interpret the synthetic suite as a native, signed-HAP, or installed-OHOS
test. No result from executing that suite is claimed by this review.

## Reviewed file identities

SHA256 values below describe the files read for this review, not executed tools
or successful build inputs.

| File | SHA256 |
| --- | --- |
| `tool/build_python_ohos_audit.ps1` | `e70970fd2a9544aec6191d5c93de006005e320dc58c9cb4c27c9c8fd0b6125d2` |
| `test/python_ohos_audit_build_test.ps1` | `1468c5a59f62a6cbc2a01e9a3aeffceeaa6ea3494583515c4f987ef34b07e0ec` |
| `tool/prepare_python_module_audit.py` | `0584ef88edf76dfec2cf9e3b497b9ccec4c205be444badb13a678eeef12729f3` |
| `tool/prepare_python_content_audit.py` | `871555d6a1deaaddbc969d5f6b637a27efeca0ced6f1cccb113c2eb1d6b9cb6f` |
| `tool/prepare_python_debugger_audit.py` | `f287fbdadfbe4171c2d114c124aaf8c0dacd749e4329a8e90f84a1e4319b8308` |

No builder, preparer, shared-core, runtime, native artifact, or test was changed
to address these findings. Implementation remains with the owning coordinator.

## Addendum: review of the coordinator's first repair batch

Date: 2026-10-24. This is another source-only review. The coordinator reports
7/7 metadata-only Python checks and 15/15 synthetic PowerShell checks passing;
this reviewer did not rerun them. Neither those counts nor this addendum is an
owned-process control, compiler/SDK/native build, Dart, signature, or installed
device result. The frozen Windows DLL remains the earlier captured artifact;
no A+B native execution or cost validation is inferred from this repair batch.

Only this addendum was written during the review. Builder, native builder,
preparers, new provenance/input tools and tests remained read-only for this
reviewer. Findings below refer to the file identities at the end of this section;
later coordinator changes require a further check.

### Original findings: closure assessment

| Original finding | Assessment of this source snapshot |
| --- | --- |
| 1: Unbounded audit commands | Addressed in the audit builder's source. `Invoke-AuditTool` routes preparation, build, native-provenance/input verification, strip, strip-version and signature verification through `python_owned_process.py`, and requires FINISHED/RELEASE plus confirmed cleanup and closed handles. Real Windows controls remain unexecuted. Native `build.ps1` still uses its existing synchronous `Invoke-Tool`; its actual build must run inside an independently owned serialized process window. |
| 2: No current-source native provenance | Partially addressed, still OPEN. There is now a pending/completed build manifest and pre/post source/output verification. The generated VM/layout files and ABI-specific generation directory are included. The incremental-build and actual compiler/toolchain omissions below still prevent a complete current-source build claim. |
| 3: Signed HAP does not bind generated Dart audit | Addressed at source level by one exact expected output, a fresh per-invocation nonce, suite/inventory identity in the debug kernel, and exact packaged/intermediate kernel hash equality. Synthetic kernel rejection cases exercise these helper decisions, not real Dart compilation. |
| 4: HAP changes between inspection and signature | Addressed at source level. A unique evidence copy is held with read-only sharing through archive inspection, SDK signature verification and final hash comparison (`builder:422`–`:431`). The actual SDK verification path remains unexecuted. |
| 5: Narrow product/core source lists | The previously identified direct-core/preparer/module/dependency omissions are addressed by `collect_inputs`, used by all three preparers, plus before/after inventory checks. Captured-file deletion fails the existing rehash loop; additions are compared against the fresh inventory. This is broader declared-input coverage, not proof of native compilation. |

### Confirmed remaining R1: incremental objects can acquire fresh source provenance

`native/build.ps1:308`–`:314` captures current input contents, then invokes
`cmake --build <dir> --target qfli_py` on the existing object tree. There is no
forced clean/fresh compilation, nor a content-based provenance check for reused
objects. `finish` (`tool/python_native_provenance.py:117`–`:125`) subsequently
compares the current input snapshot and records whichever SO is present after
the successful incremental build and dependency check.

Concrete failure condition: an object/SO was produced from source A; source B
is restored with an older or preserved modification time; Ninja considers the
old object current. Capture reads B, the build reuses the A object, the dependency
checker succeeds, and finish associates B's hashes with the A-derived output.
The before/after content comparison cannot detect this because B is stable
throughout the invocation. This is a supported failure scenario, not a claim
that the reviewed frozen artifacts were actually produced that way.

Minimal repair: ensure a complete compile/link from a clean object/output state
after capture, preserving the captured configure/generated inputs, or require
validated content provenance for every reused object. Add a regression covering
unchanged/older source mtimes and an existing output, rather than treating an
incremental exit 0 alone as compiler evidence.

### Confirmed remaining R2: real configured C/C++ compiler binaries are omitted

`tool/python_native_provenance.py:33`–`:36` looks for C/C++ compiler paths only in
`CMakeCache.txt` and silently skips missing keys/files. The existing real x86_64
configuration has no bare `CMAKE_C_COMPILER` or `CMAKE_CXX_COMPILER` cache entries.
Their paths are instead in:

- `native/build/cmake-x86_64/CMakeFiles/3.28.2/CMakeCCompiler.cmake:1`;
- `native/build/cmake-x86_64/CMakeFiles/3.28.2/CMakeCXXCompiler.cmake:1`.

The corresponding `CMakeFiles/rules.ninja` invokes Clang for C/C++ compilation
and the C++ driver for linking, including a response file. None of those generated
compiler metadata files is in `snapshot`. The supplied capture tools
(`native/build.ps1:310`) are CMake, Ninja and one toolchain CMake file, not Clang
or the host Python interpreter. AR/linker/RANLIB cache keys make the toolchain
dictionary nonempty, so the nonempty check at provenance `:70`–`:71` does not
catch absent compiler identities. Replacing a compiler alone is therefore
invisible in this configuration even when the source snapshot stays stable.

Minimal repair: discover the actual configured compiler executables from CMake
compiler metadata/authoritative configuration, require the expected tool roles,
and fingerprint C/C++ drivers plus Python explicitly. Do not silently substitute
"some tool identities exist" for "the tools that ran are identified". A metadata
fixture with compiler paths only in `CMake*Compiler.cmake` should reject driver
drift and missing required roles without executing any compiler.

### Confirmed remaining R3: command/dependency closure is incomplete

Provenance `:30` captures only `compile_commands.json`, `CMakeCache.txt` and the
top-level `build.ninja` as configured build metadata. The existing real
`build.ninja:35` includes `CMakeFiles/rules.ninja`; the included file supplies the
actual compiler/linker command bodies and response-file contents. Changing that
file alone is not detected. `compile_commands.json` is a compilation database;
it does not replace the rules Ninja will execute or the link command/input list.

SDK sysroot headers, compiler resource headers, toolchain-included CMake files,
and linked static/library inputs also fall outside the current snapshot. The
real rules explicitly use the external OHOS sysroot and toolchain, while
`native/CMakeLists.txt` selects static C++ support and the NAPI/hilog/math link
inputs. Current snapshot traversal cannot observe changes to those files.
This is a gap in a complete source/toolchain/dependency closure claim; it is not
evidence that this SDK changed during any prior build.

Minimal repair: include the recursive Ninja/CMake rule/configuration closure and
resolved compile/link dependencies, including relevant SDK/resource/library
identities. If some external SDK resources intentionally remain outside the
manifest, state that boundary explicitly and avoid claiming a full toolchain
closure. Add metadata-only drift cases for an included rule and external
header/static-library input.

### Generated and per-ABI evidence that is now present

`snapshot` (`provenance:25`–`:31`) walks maintained source/port/tools, the actual
`micropython_embed` compilation package, upstream generator inputs, and the
selected build directory's complete `embed` generation tree. It therefore
includes `vm.c`, `emitglue.h`, packaged generated headers and selected-ABI
generation intermediates. Compile-database source rows must resolve to captured
project inputs. Finish compares the complete collected maps; verify recollects
them, checks required generated files, rehashes the output, and rejects a
header ABI inconsistent with the manifest.

The source package's generated headers are shared across ABI configurations
(`native/CMakeLists.txt:23`; `native/tools/build_embed.py:615`–`:623`). If another
ABI's configure regenerates that shared package with different bytes, an earlier
ABI manifest becomes noncurrent and verify fails. This is conservative drift
rejection, not silent adoption. It also means the coordinator cannot assume two
ABI manifests remain simultaneously current after sequential regeneration;
retain each exact source/generated snapshot and artifact identity when planning
both ABI evidence windows. No per-ABI build was run by this reviewer.

The existing helper-level source/asset/ABI checks remain useful; they still
do not prove dynamic exports, loader dependencies, ordinary-run cost, debugger
behavior, signature verification or installed target behavior. The seven new
native-provenance tests use a synthetic 20-byte ELF and manually prepared
metadata; they do not exercise CMake configure/capture/compiler/dependency/finish
or the real compiler-discovery layout above.

### Addendum reviewed file identities

| File | SHA256 |
| --- | --- |
| `tool/build_python_ohos_audit.ps1` | `a2f7c648bbc4b73a9da2dae59d53e0eac1918c6dbfc6b30f57ebfbc6278e3d9a` |
| `native/build.ps1` | `7ad8a1c1b690c02a3db267a2cb2824131ab6a213cbb76b8c5f6d7c301576b8d2` |
| `tool/python_native_provenance.py` | `9556b7b6e1faf8fb9e0b5ebd39f71681645ba094381ac480a4cafe1b6d3766ee` |
| `tool/python_audit_inputs.py` | `6447f0492f91f074ab542eb9b6ed6883f5cd090a0c38751ec2e806049f027d3d` |
| `tool/prepare_python_module_audit.py` | `1c4bd56bac3a4b63e1160e03f60f0f296f5f99908bfc2ae0560f1dc87d8ab58d` |
| `tool/prepare_python_content_audit.py` | `83795ba638036e0310efe9b09b1e288b3d32e9b089300c0366636acc6e683225` |
| `tool/prepare_python_debugger_audit.py` | `b69506a1027b3242d66b027eaf496d6e792fd4c22108641199a0ae9626e765c4` |
| `test/python_native_provenance_test.py` | `444dedd9ec4807c33b87a6cd37bf3969ebe82b3477d35acc1b4673fd677596e2` |
| `test/python_ohos_audit_build_test.ps1` | `89d3050bb0c2b8f5c30d9fbb1384fee46a4da2d752f918be7cac440cb6366e5a` |

### Follow-up during the coordinator's next edit

The reviewer observed additional edits while completing the addendum. At
`native/build.ps1` SHA256
`d85fe3aad785f857419d31cc2490d326b62f825eeeca4e432b7dff2bc66c3a41`,
the script explicitly regenerates, reconfigures the generated source inventory,
captures inputs including the Python executable, and builds with `--clean-first`.
That addresses R1 at source level. No clean build was executed to validate it.

At provenance SHA256
`83a3d92adce417d574b33a15af6f652e4bb3de1c2c2de062ea9605c7bb166610`,
the source also captures generated CMake metadata and `rules.ninja`, addressing
the omitted rule-file subcase of R3. Compiler and sysroot discovery still depend
on optional cache keys in that observed intermediate edit. In the existing real
configuration, `CMAKE_SYSROOT` is also absent from the cache. The generated
compiler metadata instead lists implicit include/link directories; the C++
directories additionally include extensionless libcxx headers and LLVM
architecture libraries outside `sysroot/usr/lib/<triple>`. The coordinator was
notified so the final repair can use those actual configured inputs and require
their presence. This paragraph records an intermediate read, not a review of
subsequent unpublished changes.

Both frozen DLL copies were independently rehashed during this read-only review
and still equal
`52e7400fdcd50cb03d94026ad6331c3b27770e2795e3418259d54e4d3a79a54e`.

### Resumed review: current closure at handoff

Date: 2026-10-24. A fresh filesystem read confirms the native builder and
provenance helper still have the intermediate identities recorded above. No
later compiler-discovery or SDK-closure repair was present in this read. The
remaining seven builder/input/preparer/test identities in the addendum table
remain current.

R1 is source-addressed: `native/build.ps1:307` explicitly runs regeneration,
`:309`-`:312` reconfigures, `:316` captures, and `:321` compiles with
`--clean-first`. The capture explicitly includes the selected Python executable.
The native source-to-object concern now requires a real serialized clean-build
window to validate behavior; this review supplies no such execution evidence.

R2 remains OPEN at `tool/python_native_provenance.py:42`-`:49`. Compiler
discovery still reads optional bare cache entries and silently skips absent
keys/files. The real generated C/C++ compiler metadata was re-read and still
contains the Clang paths in its first line, while the bare cache entries are
absent. Capturing those metadata files as source inputs does not hash the
compiler executables they name. Require those actual compiler roles and reject
missing role paths; the current generic nonempty tool dictionary is insufficient.

R3's generated-rule subcase is source-addressed by generated `*.cmake` and
`CMakeFiles/rules.ninja` collection. The SDK/resource/link-input subcase remains
OPEN at provenance `:50`-`:60`: `CMAKE_SYSROOT` is optional and absent from this
real cache, so SDK collection is skipped. Even when that cache key is present,
the two collected directory trees do not cover the generated C++ implicit
include/link directories, notably extensionless libcxx headers and LLVM
architecture libraries outside the sysroot triple tree. The actual configured
directories in `CMakeCCompiler.cmake:71`/`:73` and
`CMakeCXXCompiler.cmake:82`/`:84` remain concrete inputs for the owning
coordinator's repair.

The seven provenance fixtures remain unchanged at SHA256
`444dedd9ec4807c33b87a6cd37bf3969ebe82b3477d35acc1b4673fd677596e2`.
Their cache is only `# synthetic cache` (`test:26`), so a successful stable
fixture (`:41`) does not establish required compiler-role or SDK discovery.
Future metadata cases should model generated-only compiler paths, absent
required roles, included-rule drift, extensionless header drift and external
static-library drift. No test was imported or executed here.

Final disposition of the original five findings: 1, 3 and 4 are source-addressed;
the identified product/core scope gaps in 5 are source-addressed; 2 remains
partially addressed pending R2 and R3. Real owned-process controls, compiler/SDK
build, signing verification, native runtime/cost checks and installed OHOS
acceptance remain separate open evidence gates. Only this review note was
written by this reviewer; implementation remains with the owning coordinator.
