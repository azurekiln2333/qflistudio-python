# Native debugger ordinary-run cost review

Initial review: 2026-10-23. Source application: 2026-10-24. Owner:
`/root/implement_python_debugger_native`. The initial active dispatch was
`10-22-python-offline-tools`; the D1 requirement, source follow-up dispatch and
immutable host evidence belong to sibling `10-22-python-offline-debugger`.

Root accepted and authorized A+B source changes on October 24. They are now
applied only to `debug_overlay.py` and the matching tracked `vm.c`/`emitglue.h`
blocks, with research/spec identity updated. Generated blocks were synchronized
by source editing, not a generator run. No library, build script, adapter, core
file or device was changed. No generators, builds, tests, WSL or Flutter were
run. The released Windows library remains frozen at SHA256
`52e7400fdcd50cb03d94026ad6331c3b27770e2795e3418259d54e4d3a79a54e`.
The root's explicit serialized host grant is still required before any future
implementation verification or either OHOS ABI build.

The source map, layouts and measurement discussion below capture the released
pre-A+B source unless marked proposed/applied. Existing 28/28 reports and the
1.0937 ratio were not rerun or edited; they do not validate the modified source.
Exact post-edit source hashes and the unrun record are in the debugger task's
`research/native-debugger-implementation.md` source-only follow-up section.

## Finding and recommendation

The measured **1.0937017601** median ratio is a real unresolved D1 finding;
the existing 2.6 ms workload is insufficient to assign that entire difference
to a particular VM instruction or predict representative/device performance.
Ordinary runs still pay for enabled tracing in both execution and object
layout, despite allocating no trace frames on the tested no-callback path.

Root accepted two small, independent source patches for later verification:

1. Reorder existing VM conditions so an absent frame/callback rejects the
   ordinary path before loading the trace-recursion flag. This changes no
   callback, line, frame-chain or cancellation semantics.
2. Move `line_of_definition` into the unused four-byte raw-code header padding,
   identically in full/truncated layouts. The source-calculated 64-bit raw-code
   allocation drops from 128 to 96 GC bytes without removing any trace field.

Both are applied at source level only; neither has been built or benchmarked.
Keep separate candidate artifacts when the granted verification starts. Neither
justifies declaring D1 closed. There
is no need for a second interpreter, copied opcode implementation, reconstructed
source semantics, sampled trace events or weakened lifetime control.

## Captured pre-A+B source map and costs with tracing off

| Boundary | Source | Actual ordinary-path effect |
| --- | --- | --- |
| Compile-time configuration | `native/port/mpconfigport.h:63-66` | `SETTRACE=1` and native metadata fields are present in every run. Persistent save/load were already enabled; do not attribute those pre-existing options to the debugger. |
| Each dispatched bytecode and exception tick | `native/micropython_embed/py/vm.c:179-189`, dispatch sites `:234`, `:315`, `:1403` | Live tick condition reads the recursion flag and frame pointer before deciding whether to call the profiler. With a null frame it never calls `mp_prof_instr_tick` or decodes line tables. |
| Function/generator VM entry | `vm.c:151-177`, `:256-261` | Link `prev_state`, update the VM's current-code-state root, and test recursion/global callback. No frame/code object is allocated when the global callback is null. |
| Call-like operations/attribute/import | `vm.c:396`, `:477`, `:771`, `:927`, `:962`, `:1008`, `:1047`, `:1231`, `:1240` | `FRAME_UPDATE` checks the recursion flag and frame. The current null-frame guard prevents the updater/line decoder from running. |
| VM return/yield/error | `vm.c:1147`, `:1188`, `:1306`, `:1484` | Restore the previous current-code-state root. These chain writes remain with no callback. |
| Invocation allocation/setup | `py/bc.h:234-252`, `py/bc.c:321-333`, `py/objfun.c:180-299` | Two extra code-state pointers and two null initializations. The larger header affects stack/heap size even with no frame object. |
| Function object | `py/objfun.h:32-44`, `py/emitglue.c:226-229` | An extra `rc` pointer is stored in every bytecode function. It also retains that raw-code object while the function remains live. |
| Raw code creation/assignment | `py/emitglue.h:74-125`, `py/emitglue.c:54-85` | Larger zero-initialized raw-code allocation; `line_of_definition` bookkeeping; unconditional `mp_prof_extract_prelude` for source/loaded bytecode, even when no callback is active. |
| Compiler line bookkeeping | `py/compile.c:1611`, `:3168`; `py/emitbc.c:220` | Additional source-line metadata for except/class/call attribution. This is compile work, not extra semantic Python instructions. |
| Native named-locals hook | `py/compile.c:3597-3601`, `native/src/qfli_py_debug.c:639-658` | One out-of-line hook per successful final scope emit. With `active_session == NULL` it returns before iterating identifiers or allocating metadata. |
| VM initialization | `py/mpstate.h:291-295`, `py/runtime.c:160-164` | Global callback, recursion flag and current-state root fields; reset once per fresh VM. |
| Legacy run wrapper | `native/src/qfli_py_bridge.c:502-519`, `qfli_py_debug.c:660-675` | Begin/end hooks perform a few null checks/stores with a null debug session. They allocate no session, condition variable, queue or snapshot. |

The first `TRACE_TICK` condition only surrounds `MP_PROF_INSTR_DEBUG_PRINT`.
`py/profile.h:72-78` hardcodes that diagnostic macro off, so its body is empty
and an optimizing production compiler can eliminate the whole first condition.
Do **not** count the two written `if` statements as two retained production
runtime branches without inspecting optimized output. Likewise NDEBUG removes
the written assertions. The current Windows CMake cache records Release GCC
`-O3 -DNDEBUG`; exact optimized load/branch counts were not measured here.

The port retains default switch dispatch (`MICROPY_OPT_COMPUTED_GOTO=0`),
`STACKLESS=0`, no Python threads and no pystack override. Cancellation hooks at
VM entry, branches and return predate tracing and must stay. Ordinary tracing
adds no new per-op session mutex/atomic/token poll. Session allocation, JSON,
condition waits, variable snapshots, line decoding, code objects and the
callback NLR guard are all outside the no-callback tick path.

## Heap and frame accounting

These are **source-derived C layouts**, not newly executed `sizeof` or heap
attribution measurements. They assume the current 64-bit pointer/size_t/qstr
configuration, four-byte `uint`, default alignment and no machine/inline-ASM
emitter. `qstr` is `size_t` (`py/qstr.h:60`); `mp_uint_t` is `uintptr_t` in the
port. GC rounds up to four object words, hence 32-byte blocks on these targets
(`py/mpconfig.h:170`, `py/gc.c:726-729`).

| Object | Foundation, tracing disabled | Current, tracing enabled | Reason |
| --- | --- | --- | --- |
| `mp_raw_code_t` and truncated bytecode layout | 32 C bytes / 32 GC bytes | 104 C bytes / 128 GC bytes | `line_of_definition`, cached prelude, native metadata pointer and padding. |
| Raw code with upstream SETTRACE but without native metadata pointer | — | 96 C bytes / 96 GC bytes, hypothetical comparison | The native pointer currently pushes the trace-enabled layout across one extra GC block. No such comparison binary was built. |
| Bytecode function without defaults | 32 C bytes / 32 GC bytes | 40 C bytes / 64 GC bytes | Retained raw-code pointer. Defaults can change rounding boundaries. |
| `mp_code_state_t` header | 40 C bytes | 56 C bytes | `prev_state` and `frame`. No separate GC frame object is implied. |
| `mp_bytecode_prelude_t` | Not retained in raw code | 56 C bytes inside each raw code | Six uints, one qstr and three pointers. |
| Thread-state trace fields | Absent | Two pointers plus bool/alignment, normally 24 C bytes | Static VM context, not per-call GC allocation. |

The allocation fixture contains three source scopes/functions: module, `leaf`
and `parent`. Three raw-code increases of 96 GC bytes plus three function
increases of 32 bytes predict **384 bytes**, exactly the observed 1760 → 2144
retained difference. This is a consistent layout explanation, not a separately
instrumented attribution; root reachability and source metadata can also change
retention in other programs. In particular, every function now roots its own
raw code through `fun_bc->rc`.

The fixture's extra 32 bytes across 4000 calls shows that this small no-callback
call path does not allocate a fresh trace frame each time. It does not prove
that every function/generator has identical allocation cost. `fun_bc_call`
compares **variable state size**, excluding the header, with its 11-word stack
threshold. The extra 16-byte header does not itself change that decision; it
increases the eventual alloca/heap request. Larger functions which already use
heap code states may cross a GC-block boundary. Generators embed the larger
code state in a heap object (`py/objgenerator.c:45-69`). More live/larger objects
also affect allocation pressure and GC scans.

There is no source-compiled locals-metadata allocation during these ordinary
runs. The always-present pointer and cached upstream prelude must not be
confused with that session-only metadata payload.

## Concrete patch A: put the absent object first

Extend the pinned `vm.c` overlay, with no opcode, callback or lifetime changes:

```c
/* FRAME_ENTER: callback absent on ordinary entry. Keep chain writes intact. */
if (MP_STATE_THREAD(prof_trace_callback) && !mp_prof_is_executing) {
    mp_prof_frame_enter(code_state);
}

/* FRAME_UPDATE: absence of a frame rejects the ordinary path first. */
if (code_state->frame && !mp_prof_is_executing) {
    code_state->frame = MP_OBJ_TO_PTR(mp_prof_frame_update(code_state));
}

/* TRACE_TICK live condition; leave diagnostic-print handling equivalent. */
if (code_state->frame && !mp_prof_is_executing && code_state->frame->callback) {
    mp_prof_instr_tick(code_state, is_exception);
}
```

All operands are valid worker-owned initialized state. The conjunctions have
the same truth conditions; the skipped reads have no side effects. No extra
cache/flag is introduced. For a null frame this exposes a single frame-pointer
test before reading the global recursion flag. For entry it exposes the null
global callback first. The optimizer may already produce equivalent code or
choose a different order; verify generated code and representative cost before
claiming a benefit. Trace-active behavior and callback recursion protection
remain unchanged.

Do not replace the live tick's per-frame callback test with the global callback.
They are different upstream states: `mp_prof_settrace` changes the global slot,
while an existing frame can retain a callback. Also do not cache the global
callback once per VM invocation: normal user `sys.settrace` changes it during
execution and affects later nested calls/generator entries. Do not gate these
paths solely on the native `active_session`, since ordinary user tracing is
supported and tested without a native debugger session.

## Concrete patch B: reclaim raw-code padding

In both raw-code common layouts, move the existing guarded uint32 definition
line directly after the four flag/header bytes, before pointer fields:

```c
uint8_t proto_fun_indicator[2];
uint8_t kind;
bool is_generator;
#if MICROPY_PY_SYS_SETTRACE
uint32_t line_of_definition;
#endif
const void *fun_data;
struct _mp_raw_code_t **children;
/* existing native metadata pointer and persistent fields follow */
```

Remove its old copy inside the persistent-save block; preserve its documented
meaning. SETTRACE already requires persistent save (`py/profile.c:36-40`).
Preserve the first two proto bytes at offset zero and every field, including
the actual prelude and GC-visible metadata pointer.

Current 64-bit offsets: pointer fields at 8/16/24, persistent size/count at
32/36, definition line at 40, prelude at 48, total 104. Proposed: definition
line at 4, pointers at 8/16/24, size/count at 32/36, prelude at 40, total 96.
That saves **one 32-byte GC block per raw code**, with no new runtime branch.
The three-scope fixture would predict 96 fewer retained bytes; measure rather
than promise that exact post-patch result. A 32-bit configuration is predicted
to keep the same total size, but must be checked independently if shipped.

This changes an internal C layout and requires recompiling all translation
units together. Exported run/debug ABI structures do not change. Full/truncated
layouts must retain identical common offsets. Bytecode `.mpy` save/load writes
explicit fields/bytecode, not a C-struct memory dump (`py/persistentcode.c:238`,
`:571`). The freeze emitter uses designated `.line_of_definition`/`.prelude`
initializers (`tools/mpy-tool.py:910-954`). Existing native/dynamic module
compatibility cannot be inferred solely from that bytecode format fact.

Apply this through `native/tools/debug_overlay.py`, regenerate the tracked
package in a granted serialized window and extend the overlay/layout checks.
Do not hand-edit only the generated header, use packing pragmas/unaligned
pointers, remove fields, or place compiler metadata in an unrooted side table.

## Changes not justified by this finding

- Removing `FRAME_SETUP/ENTER/LEAVE` chain bookkeeping when the native debugger
  is absent: breaks genuine stack state, nested ordinary `sys.settrace` and
  exception/generator restoration unless a larger reviewed design replaces it.
- Disabling ordinary `sys.settrace`, skipping line events, checking only every
  N opcodes, bypassing Stop, or dropping the callback NLR cleanup guard.
- Enabling computed-goto dispatch or selective exception-IP storage as a D1
  fix: these alter unrelated VM mechanisms and need their own accuracy review;
  selective IP in particular must not invalidate the profiler's exact tick IP.
- Lazy prelude allocations/alternate compact function layouts, global layout
  modes, hot-swapped dispatch tables, or a separately maintained nontrace VM.
  These are materially larger changes than the observed issue warrants now.
- Moving the compile-hook guard merely to another out-of-line helper: that
  retains the call overhead. Exposing more global state to save one call per
  scope is low priority compared with the live dispatch conditions.

## Validation after an explicit host grant

The current report measures real end-to-end legacy calls: ctypes argument
encoding, VM/GC initialization, project setup, parsing/compilation, about
45,001 Python function calls, output copying and cleanup. Each library has two
warmups and nine samples, with baseline then current in every pair. The result
is valid for that workload; fixed order, short duration and host memory/CPU
contention limit attribution. Do not subtract overhead after the fact to
relabel it a pass.

Later, preserve the frozen adapter DLL and use isolated build directories for
matched baseline/current/A/A+B artifacts with identical compiler flags and
source provenance. Verify exported ABI and layout offsets first. Keep the
existing report, then add balanced/randomized order and longer representative
samples (roughly 0.25–1 s VM work each), recording individual samples, medians,
paired differences and result equality:

- Arithmetic/branches with few Python calls, to expose dispatch cost.
- Small-function/call-heavy and closure/generator workloads, to expose frame
  bookkeeping; include normal user trace enable/disable and generator resume.
- Import-heavy and compile-only source, to distinguish raw-code/prelude/hook
  cost from execution; use the actual embedded VM throughout.
- Many retained functions/generators, large heap code states and post-GC memory,
  to cover the untested allocation boundaries and raw-code lifetimes.
- A small representative curriculum/module set through the actual public run
  ABI, retaining complete output/exit/error equality.

Then rerun the existing 28 real debugger cases on Windows/POSIX, ordinary 100
native cases and overlay checks, and relevant product adapter/module tests in
the root's agreed order. Add meaningful layout assertions, not duplicate
implementation-only unit tests. Inspect optimized dispatch to confirm whether
patch A actually reduced ordinary-path loads. Keep D1 open if cost remains
materially higher; benchmark improvements cannot erase retained-memory changes
or substitute for an explicit requirement/tradeoff decision.

Both OHOS ARM64 and x86_64 debugger library builds are this owner's future
responsibility **after** a root serialized host grant. Use `-SkipCopy`, inspect
artifacts, and stage controlled matching libraries only by coordination. This
research does not authorize those builds, signing, installation or a device
window. Installed OHOS and all separate target acceptance gates remain open.
