# Native debugger implementation and handoff

Recorded on 2026-10-23, Asia/Shanghai. Native owner:
`/root/implement_python_debugger_native`. Task remains `in_progress`.
This note supersedes feasibility proposals where the implementation below is
more specific. It records host native evidence, not installed OHOS acceptance.

## Source-only A+B follow-up — 2026-10-24

The host evidence below describes the captured source used to build the frozen
`52e7400f…` DLL. Root subsequently accepted two narrow cost-review changes and
authorized source edits only. The current source therefore differs from the
released artifact; no existing 28/28 report is a test of this follow-up.

- A: `FRAME_ENTER` checks the global callback before recursion state;
  `FRAME_UPDATE` and both tick guards check frame presence before recursion
  state. All conditions, per-frame callback semantics, frame-chain writes,
  opcode ticks and cancellation/lifetime logic are preserved.
- B: move the existing uint32 `line_of_definition` into header padding after
  the four flag/proto bytes, identically in full/truncated raw-code layouts.
  This moves definition-line metadata, not the GC-owned compiler-locals pointer.
  All fields, first two proto bytes and explicit bytecode serialization remain.

Both changes are maintained in `native/tools/debug_overlay.py` and manually
synchronized to the tracked `micropython_embed/py/vm.c` and `emitglue.h` blocks.
`build_embed.py` already invokes that overlay and needs no change. The pinned
vendor sources, released DLLs, prior reports and evidence manifest are intact.
The source-only review used reads/hash checks; it did not execute the overlay.

| Applied source | SHA256 of recorded bytes |
| --- | --- |
| `native/tools/debug_overlay.py` | `b435f0dfc68a761da97044687c67a6c08246c7e14177d3726c9705c2c53fefcb` |
| `native/micropython_embed/py/vm.c` | `9e94eefad242c113acefd0fdd13ea7f5023d1138cb34212e6d4b5c215dcfb403` |
| `native/micropython_embed/py/emitglue.h` | `5bba2c8746b258e6f788a83dca870faa08196b2bceb33ad2420f6a87b350be49` |

Source calculation predicts raw-code size 104 → 96 C bytes and 128 → 96 GC
bytes on the current 64-bit layout. No `sizeof`, allocation or timing result
has been collected for these edits. D1 remains open; neither a cost benefit nor
a performance pass is claimed.

**Explicitly unrun:** generators, compiler/builds, overlay checks, Windows or
POSIX/native/Flutter tests, WSL, OHOS builds and installed-device operations.
No DLL was rebuilt or replaced. Both Windows DLL copies were rehashed and
still equal `52e7400fdcd50cb03d94026ad6331c3b27770e2795e3418259d54e4d3a79a54e`.
Verification awaits the root's explicit serialized host grant. Both future
OHOS ABI builds remain assigned to this owner after that grant, using
`-SkipCopy` and controlled staging.

Detailed source accounting and future validation plan:
`../../10-22-python-offline-tools/research/native-debugger-cost-review.md`.

## Implementation boundary

`native/src/qfli_py_debug.c` implements a real MicroPython 1.24.1 (`ecfdd5d`)
trace debugger. Entry pauses, source file/line breakpoints, step into/over/out,
Continue and Stop use actual upstream frame/line events. Source is neither
rewritten nor executed by a host Python interpreter. A pause precedes the
instruction attributed to the emitted line; upstream line attribution has the
limitations below.

The native batch owns `qfli_py_debug.[ch]`, additive bridge hooks, platform
condition primitives, maintained/generated port headers, compiler/profile/VM
overlays, the generator, all native source lists and native debugger tests.
Product Dart/FFI adapters, runtime leases, editor/UI integration and installed
device verification belong to the parent/adapter owners. Shared-core debugger
types and UI belong to C. No shared-core files, device state or commits were
changed by this batch.

The debugger source is included by OHOS `native/CMakeLists.txt`, desktop and
Android CMake lists, Apple pod source staging and both host test build scripts.
The Apple linker retention list contains all nine public debugger exports.
Source-list inclusion is not a successful target build. NAPI/JNI/ArkTS/Kotlin
debug handlers were not added: the product adapter uses direct FFI controls
with execution on a separate Dart isolate. The installed OHOS FFI route must
still be proved on its actual target.

## ABI and event contract

The authoritative declarations are `native/src/qfli_py_debug.h`, included
additively from `qfli_py_bridge.h`. Existing execution/result structures and
legacy run/compile entry points retain their ABI.

| Export | Contract |
| --- | --- |
| `qfli_py_debug_capabilities()` | Returns 31: breakpoints, steps, stack, bounded variables and Stop. |
| `qfli_py_debug_create(project, entry, stop_on_entry)` | Copies canonical existing absolute paths; entry must be a project-owned file outside the bundled directory. Returns one external reference. |
| `qfli_py_debug_retain/release(session)` | Each concurrent owner holds a reference. Release is nonblocking and requests Stop when only the active worker reference remains. |
| `qfli_py_debug_set_breakpoints(session, files, lines, count)` | Atomically replaces copied breakpoints. Count is at most 128, lines are positive Int32, paths must be existing accepted source files. |
| `qfli_py_debug_execute_into(result, source, stdin, heap, session)` | Blocking execution on the VM worker, once per session; writes the existing result structure. |
| `qfli_py_debug_command(session, generation, command)` | Control-thread operation independent of the VM lock. Non-Stop commands require a consumed current pause event. |
| `qfli_py_debug_poll_json(session, max_bytes)` | Nonblocking copied UTF-8 JSON; drains only events which fit the requested buffer. |
| `qfli_py_debug_json_free(json)` | Frees each successful poll result with its native allocator. |

Commands are Continue=1, Step Into=2, Step Over=3, Step Out=4, Stop=5.
Statuses are success=0, invalid argument=1, wrong state=2, stale generation=3,
bounds=4 and allocation failure=5. Null create/poll results indicate invalid
arguments or allocation failure. Results are freed through the existing
`qfli_py_result_free` convention.

Envelope example, with illustrative identity/numbers:

```json
{"schema":1,"sessionId":"1","state":"paused","sequence":3,"pauseGeneration":1,"droppedEvents":0,"events":[]}
```

Each state event has sequence, kind, state, reason and pause generation. Paused
events additionally carry actual file/line, frames and a stack truncation flag.
Terminal events include actual exit code and `traceDisabled`. The authoritative
program output/error buffers are returned only when execution completes;
native polling does not provide live stdout/stderr.

Variable fields are flat, for example
`{"name":"x","type":"int","value":"3"}`. Container snapshots can have
bounded children; dictionary children contain `key` and `item` snapshots.
`unbound`, `cycle`, `truncated` and bytes `encoding:"hex"` have explicit meaning.
Adapters must map this actual schema rather than assume an extra nested value
object or append cumulative buffers.

## Lifetime, locking and pause ownership

The existing VM lock covers the entire execution, including pauses. This keeps
ordinary runs, analysis and debug workers from simultaneously touching the
single embedded VM. The worker alone reads MicroPython objects and constructs
copied snapshots. Controls/polls use a separate session condition/mutex and
never acquire the VM lock. Windows uses SRW locks/condition variables; POSIX
uses pthread mutexes/condition variables.

Execution claims the session once and retains a worker reference before
entering the existing VM path. A transport which queues work must retain its
own reference **before scheduling**; the worker cannot protect a pointer until
`execute_into` is actually entered. Every concurrent poll/control/release
caller must itself own a reference. A pointer used after its final release is
invalid, even if a caller remembers its former session ID.

Stop requests the existing cancellation token and signals a paused condition.
It is valid before start and while queued, running or paused; terminal commands
are rejected. Last external release requests Stop without waiting on the VM.
The worker completes native cleanup, publishes its terminal state and drops its
reference. Terminal events can be drained while an external owner still holds
the session. No arbitrary cross-thread VM access or isolate termination is
used as cancellation.

A non-Stop command requires the current nonzero generation **and** an event
consumed by `poll_json`. An envelope's current generation does not acknowledge
its pause; a too-small poll cannot resume it by guessing that number. Thus a
retained pause cannot be skipped by a later pause. Adapters must publish final
completion and release the runtime lease only after the actual execution
worker returns, even when a native terminal event is already observable.

Tracing is disabled before formatting an escaped exception: a user's exception
`__str__` cannot reenter the debugger during diagnostic cleanup. The trace
callback exception overlay also resets upstream recursion state when Stop
unwinds through a trace callback.

## Real variables and deterministic source overlays

The compiler's finalized LOCAL/CELL/FREE names and slot numbers are copied into
GC-owned metadata attached to raw code, only while a debug session is active.
The final successful emit hook captures closure slot shifts. Raw-code full and
truncated common layouts both include the same guarded pointer. Values come
from actual code state slots, with explicit cell/free unwrapping and unbound
slots; names are not reconstructed from source spelling.

Module variables use the real globals dictionary, including dynamically
allocated string keys. Source-compiled functions, closures, generators and
comprehensions have tested metadata-backed locals. Class locals are explicitly
unavailable. Loaded `.mpy` code has no serialized compiler metadata and reports
named locals unavailable. Missing source is not invented for a `.mpy` pause.

Snapshots access primitives and exact built-in list/tuple/dict storage only.
They do not evaluate user repr/str, attributes/properties, iterators, hashing or
equality. Unknown objects expose a bounded actual type placeholder. UTF-8
truncation preserves whole characters, and shortened names/types set truncation
flags. No eval, watch expression or asynchronous Pause capability is exposed.

`native/tools/debug_overlay.py` applies pinned, hash-checked transformations to
`compile.c`, `emitglue.h`, `vm.c` and `profile.c` while `build_embed.py` assembles
the tracked embedding package. The vendor checkout is unchanged. Wrong input
hashes, changed contexts and double patching are rejected; CRLF source is
normalized. Generated readable headers use LF. Maintained and generated port
metadata/config headers must stay synchronized.

The no-callback VM guard avoids allocating trace frames on each ordinary
function invocation while preserving the upstream code-state chain and normal
`sys.settrace` behavior. Fields and branches remain; see the measured cost.

## Bounds and source semantics

| Resource | Limit/behavior |
| --- | --- |
| Breakpoints | 128, atomic replace; no relocation of blank/missing lines. |
| State queue | 16 events; retained paused/terminal states are not evicted. |
| Event size | 192 KiB maximum allocation. |
| Poll | 1–256 KiB; 0 means 256 KiB; `requiredBytes` identifies an event which does not fit. |
| Stack | 16 frames, with an explicit truncation flag. |
| Variables | At most 64/frame and a 16 KiB serialized frame budget. |
| Values | Depth 2; at most 4 container children; 256 UTF-8 bytes/string/name/type; 64 displayed bytes as hex. |
| Allocation failure | An unobservable pause requests cancellation; terminal storage is reserved at session creation. |

Accepted files are canonical existing absolute project-owned files. Imported
project sources and Unicode paths are covered. Files under
`.qfli/python/bundled` do not create ordinary project stops. Breakpoints become
actual hits only on genuine line events; blank/removed lines are never silently
moved to a nearby statement.

Upstream constraints remain visible:

- Monotonic line tables sometimes attribute loop entry/final guards to the
  final body line. An optimized `for n in range(2)` may first report that line
  before `n` is bound. The snapshot reports the real state rather than an
  invented next value.
- Generator resume can emit a genuine repeated event on the prior yield line.
  Tests remove some breakpoints after their asserted visits so later genuine
  guard/resume events do not leave the worker paused.
- A same-line loop may never emit another distinct line event. Line stepping
  can wait until Stop; existing cancellation still stops that loop.
- `sys.settrace(None)` or replacement can cooperatively disable tracing. The
  terminal event truthfully reports `traceDisabled:true`.
- Native calls provide no Python bytecode location inside C. Arbitrary blocking
  native I/O does not become interruptible through tracing.
- Class namespaces and loaded `.mpy` named locals are unavailable. The runtime
  lacks arbitrary precision integers; this batch does not claim to add them.

## Verification and immutable artifacts

| Check | Recorded result | Evidence |
| --- | --- | --- |
| Real Windows controller-thread debugger suite | 28/28; no failures/errors | `python-native-debugger.json` |
| Real POSIX controller-thread debugger suite | 28/28; no failures/errors | `python-native-debugger-posix.json` |
| Existing native host ordinary regression | 100/100 | Native owner's successful `run_host.sh` completion; no separate JSON reporter. |
| Pinned overlay/unchanged vendor/regeneration checks | 4/4 | Native owner's successful `debug_overlay_test.py` completion. |
| Real modules on current immutable debugger DLL | 306 assertions, 128 encoding vectors and 256 CSV differential scenarios; automatic imports/precedence/isolation/refresh passed | `python-stdlib-with-debugger.json` |
| Native whitespace check | Clean after LF normalization | `git diff --check -- native`. |

The clean whitespace result above was recorded before the final handoff. A
subsequent repeat during documentation on 2026-10-23 could not complete:
Git's submodule-status child reported `Out of memory` allocating 1 MiB. In the
same read-only batch, `rg` failed to allocate 64 KiB and another invocation
overflowed its stack. This failed repeat is not a new PASS or a source failure;
no process cleanup, rebuild or device operation was attempted. The frozen
artifact/report hashes were checked before that host-resource failure.

Commands already completed (do not rebuild the released DLL during adapter use):

```powershell
python native/tests/debugger.py native/build/windows/qfli_py_ffi.dll --report build/reports/python-native-debugger.json
wsl.exe -d qfli-java-build --cd /mnt/d/MyNewProjects/qfli_python -- sh native/tests/run_debugger_host.sh
wsl.exe -d qfli-java-build --cd /mnt/d/MyNewProjects/qfli_python -- sh native/tests/run_host.sh
python native/tests/debug_overlay_test.py
python tool/verify_python_modules.py --library build/qfli_py_ffi-debugger-stable.dll --report build/reports/python-stdlib-with-debugger.json
```

The WSL distribution with the working compiler is `qfli-java-build`. The
`Ubuntu` VHDX is missing; `qfli-terminal-test` lacks GCC. Neither is substituted
for the successful POSIX evidence.

| Artifact | SHA256 |
| --- | --- |
| Released `native/build/windows/qfli_py_ffi.dll`, identical immutable `build/qfli_py_ffi-debugger-stable.dll` | `52e7400fdcd50cb03d94026ad6331c3b27770e2795e3418259d54e4d3a79a54e` |
| POSIX `native/build/host/libqfli_py_debug_test.so` | `e77addddd488c8a49dc8f47edfb63b221c4c74e7a5682a7883341d34eb27da4f` |
| Module-foundation comparison `build/qfli_py_ffi-module-foundation-2329ef7d.dll` | `2329ef7d374e35dd5159db0f3f056b094effc9a0372ad29fe704af472a6c309f` |

The Windows artifact was explicitly released to the parent and
`/root/python_debugger_adapter`; it must remain unchanged during their real FFI
test window. Any correction requiring a rebuild must be coordinated first.
The four named JSON reports are copied byte-for-byte into this research
directory; `native-debugger-evidence-manifest.json` records their hashes and
current artifact identity.

An independent read-only native evidence review found no factual/schema
corrections: all copied report bytes and all four artifact identities match the
manifest, and every build source list/Apple retained export was checked. This
handoff was published in global `qfli-core-release-sync`, sequence 180.

## Ordinary-run cost and unresolved D1 acceptance

`native/tests/debugger_cost.py` runs the unchanged legacy ABI without a debug
session/callback. It alternates two libraries, warms each twice, records nine
samples/library, checks identical output/result and probes allocation with GC
disabled across 4,000 nested ordinary function calls.

| Metric | Module foundation | Current debugger library |
| --- | --- | --- |
| DLL bytes | 714,418 | 745,758 |
| Host median | 0.0025912 s | 0.0028340 s |
| Initial retained VM allocation | 1,760 bytes | 2,144 bytes |
| Incremental allocation across nested calls | 32 bytes | 32 bytes |
| Program output | `14901345\n` | `14901345\n` |

The measured median ratio is **1.0937017601**, approximately 9.4% slower on
this small Windows workload. There is no per-call trace frame allocation in
the tested ordinary path, but raw-code/frame fields, compiler hooks and VM
branches remain. These measurements establish neither zero overhead nor target
device performance. PRD D1's strict ordinary-cost preservation is therefore
**not closed**; the parent must resolve the measured tradeoff or require a
further scoped optimization. See `python-debugger-cost.json` for all samples
and workload hashes.

## Remaining integration/target gates

- Parent/adapter: actual FFI tests using the released DLL; complete product
  analysis/tests; exact shared contract mapping, snapshot validation, lease and
  queued-worker lifetime checks.
- Native target packaging: current debugger sources have **not** yet been
  built into both OHOS ARM64 and x86_64 libraries. The owner is waiting for the
  parent's serialized build handoff; no OHOS build or root signing changes are
  performed in this continuation. Existing pre-debugger module-audit HAPs do
  not prove debugger exports.
- Parent: inspect actual target ELF exports/dependencies and exact library to
  HAP binding, preserve signing and restore normal entry point after audits.
  Android and Apple target builds/runs remain independent gates.
- Installed OHOS: genuine pause before side effect, exact stack/locals,
  step/continue/second breakpoint, UI responsiveness, running/paused Stop,
  imports/Unicode, error/disposal/queued start cleanup and successful following
  ordinary run. Record target ABI/device, source/library/HAP hashes and events.
- Shared-core UI acceptance and complete umbrella task remain open. No host
  result in this note is an installed-device result or authorization to claim
  another coordinator's exclusive device window.
