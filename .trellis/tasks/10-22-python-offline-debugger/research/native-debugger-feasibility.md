# Native Python debugger feasibility

Date: 2026-10-22. Scope: read-only inspection of the checked-in MicroPython
1.24.1 (`ecfdd5d`) embedding package, port, bridges and Dart transports. No
build, generated-source edit, device operation or debugger implementation was
performed for this research. Line anchors below refer to the inspected local
files and may move with concurrent work.

## Conclusion

A real project source breakpoint / line step / continue / stop debugger is
feasible without replacing MicroPython or rewriting Python source. Enable the
existing upstream trace machinery, install a native MicroPython callable as the
trace callback before entry execution, and pause that callback on a separate
native session condition variable. Keep every VM read on its execution worker.
The existing NAPI async worker and Dart FFI isolate can remain blocked safely
while their UI thread polls copied events and sends control commands.

Actual stack and module globals are available. Complete named function locals
are **not** exposed by the stock frame API: they require a small, reproducible
compiler metadata extension. Do not label `f_globals`, `co_names`, a Python
`locals()` call, or anonymous stack slots as complete locals. A first native
prototype can prove breakpoint/stack/control with `localsAvailable: false`;
the final variables capability must follow a real metadata-backed test.

Two other upstream facts affect the product contract: enabling tracing adds
frame allocations even when no callback is active, and line callbacks occur
only when the emitted source line changes. Neither zero nondebug overhead nor
single-line iteration stepping follows automatically from `SETTRACE=1`.

## Existing executable hooks and source evidence

| Fact | Exact local anchors |
| --- | --- |
| Packaged upstream identity is v1.24.1 / ecfdd5d. | `native/micropython_embed/genhdr/mpversion.h:2`, `:3` |
| Trace defaults off; the port does not override it. | `native/micropython_embed/py/mpconfig.h:1517`; `native/port/mpconfigport.h:55` |
| Trace requires persistent-code-save metadata, already enabled in this port. | `native/micropython_embed/py/profile.c:34`; `native/port/mpconfigport.h:59` |
| Public C entry is `mp_prof_settrace(mp_obj_t callback)`; callable sets the thread trace root and noncallable clears it. | `native/micropython_embed/py/profile.h:62`; `native/micropython_embed/py/profile.c:313` |
| The callback receives `(frame, event, arg)` through `mp_call_function_n_kw`; callbacks are guarded against trace recursion. | `native/micropython_embed/py/profile.c:297` |
| `call` invokes the global callback; its returned callable becomes that frame's callback. Return the native callback object for every frame that must remain traced. | `native/micropython_embed/py/profile.c:322`, `:351`, `:356` |
| `line` is emitted only when previous and current decoded source lines differ. | `native/micropython_embed/py/profile.c:410` |
| `return` is emitted for both RETURN_VALUE and YIELD_VALUE. `exception` has `arg=None`, not a CPython exception tuple. | `native/micropython_embed/py/profile.c:403`, `:421` |
| Opcode tracing is disabled by an unconditional `if (false)`; `f_trace_opcodes` is only a TODO. | `native/micropython_embed/py/profile.c:431` |
| Instruction tick executes before the next opcode in both computed-goto and switch dispatch. A line pause can stop before that line's effect. | `native/micropython_embed/py/vm.c:224`, `:231`, `:309` |
| Traced frames retain actual code-state and previous-code-state links; raw code retains line prelude and line-of-definition metadata. | `native/micropython_embed/py/profile.h:45`; `native/micropython_embed/py/bc.h:233`; `native/micropython_embed/py/emitglue.h:86` |
| The source filename and function name come from the module qstr table, not a fabricated source parser. | `native/micropython_embed/py/profile.c:160`, `:166` |
| Public frame attributes are f_back, f_code, f_globals, f_lasti, f_lineno. There is no f_locals case. | `native/micropython_embed/py/profile.c:220` |
| `co_names` is not the fast-locals map: its `dict_locals` is captured by `mp_locals_get()` and has an upstream comment saying it is wrong. | `native/micropython_embed/py/profile.c:169`, `:197` |
| Current thread trace state is reset during each mp_init. | `native/micropython_embed/py/runtime.c:160`; `native/micropython_embed/py/mpstate.h:291` |

The native callable can be defined with `MP_DEFINE_CONST_FUN_OBJ_3` in an
app-owned debugger C file. Its frame argument is the exact upstream frame
object; after checking its type, read `mp_obj_frame_t` / `mp_code_state_t`
directly. There is no need to evaluate Python attributes to obtain stack or
location. Install it after `mp_init()` and before `mp_call_function_0()`;
the bridge currently compiles then calls entry at
`native/src/qfli_py_bridge.c:315` and `:322`.

### Trace limitations that need explicit behavior

- The line event's `arg` is None, return/yield values are not supplied, and the
  exception event does not supply a CPython exception tuple. Preserve the
  existing final traceback/exit as the authoritative program result. Do not
  invent return values or exception detail in trace events.
- One source line with several statements cannot be stepped by statement.
  `while True: pass` can remain on one emitted source line forever. Existing VM
  cancellation hooks can still stop it; a line-only step may wait indefinitely
  until Stop. A later explicit pause-at-any-instruction feature would need a
  narrow tick hook, not the stock disabled opcode callback.
- Match breakpoints only on actual `line` events in accepted source files.
  `call` reports a definition line before resetting frame lineno to zero
  (`profile.c:335`, `:358`); do not treat that call event as a line breakpoint.
  Obtain executable line membership from the emitted line table; blank/comment
  or removed lines remain unverified rather than silently moving elsewhere.
- A script can call `sys.settrace(None)` or replace the global trace callback
  (`native/micropython_embed/py/modsys.c:220`). A debugger that uses this stock
  callback slot is cooperative. Either report a trace-disabled condition, or
  make a separate, reviewed port trace hook if debugger operation must survive
  such user calls. This is not an isolation/security mechanism.
- Built-in/native C calls have no Python bytecode frame or instruction pause
  inside them. Existing finite input and sleep/cancellation behavior still
  applies; arbitrary blocking native I/O cannot gain interruption by tracing.
- A frame allocation can fail and be absent (`profile.c:258`, `:325`). Report
  a real unavailable/truncated-stack state; do not continue showing stale data.

## Named locals: what is missing and the smallest complete mechanism

The actual local values exist in the VM, but their names are discarded with the
compiler scope. The VM state layout is `state[n_state - 1 - local_num]`
(`native/micropython_embed/py/vm.c:198`; setup in `py/bc.c:186`). `n_state`
includes both locals and operand stack (`py/emitbc.c:296`), so iterating all
state slots is not a locals implementation.

The compiler already has the correct map: `id_info_t` contains kind, flags,
`local_num`, and qstr (`py/scope.h:49`), and scope has raw code and local count
(`py/scope.h:73`, `:88`). `scope_compute_things` finalizes fast/cell/free
numbering, including closure-related shifts (`py/compile.c:3393`, `:3421`,
`:3436`). Parameter names alone survive in the bytecode prelude
(`py/emitbc.c:324`), with explicit `*` placeholders for some closed-over slots.
Those surviving names can support a deliberately partial parameters display;
they do not recover ordinary local names or every closure parameter.

Recommended extension for complete source-compiled function locals:

1. Add a config-guarded `scope compiled` hook after a scope's successful final
   MP_PASS_EMIT, while its `id_info` remains live. The concrete insertion region
   is `py/compile.c:3589` after the repeat-until-stable emitter loop, before
   `scope_free` at `:3657`. The hook receives the actual scope/raw-code and source
   qstr. It records LOCAL/CELL/FREE entries, actual final slot index, parameter
   flags and scope kind; it never reconstructs this from source spelling.
2. Retain that mapping in GC-owned metadata attached to the raw code object,
   guarded by a product debugger macro. Both `mp_raw_code_t` and
   `mp_raw_code_truncated_t` must retain identical common layout
   (`py/emitglue.h:74`, `:104`). `mp_emit_glue_new_raw_code` zero-initializes
   new objects (`py/emitglue.c:54`), including loaded .mpy code
   (`py/persistentcode.c:334`), so absent metadata can be explicit null.
   Attaching a GC allocation to the live raw code avoids a malloc side table
   with unrooted/stale raw-code addresses and pointer-reuse bugs.
3. At pause, iterate only this known local map. Null slots are **unbound**, not
   Python None. CELL/FREE slots contain cells; unwrap with
   `mp_obj_cell_get()` (`py/obj.h:1056`) according to compiler metadata. Never
   call a Python `locals()` function from the trace callback.
4. Module scopes can expose their actual `fun_bc->context->module.globals`
   dictionary (`py/profile.c:238`). Class/comprehension/generator scopes must be
   tested independently. Do not claim a saved class locals dict exists in
   `mp_code_state_t`; it stores old_globals, not an old_locals field
   (`py/bc.h:243`). If reliable class locals capture is not implemented, mark
   those scope variables unavailable while still showing the genuine frame.
5. Keep this as runtime metadata, without changing upstream .mpy serialization.
   Existing .mpy imports can still trace their bytecode/lines, but they have no
   new named-local mapping. Report per-frame `localsAvailable: false` and its
   reason. Adding metadata-bearing .mpy is a separate format/compatibility task.

This hook is an upstream-source overlay, not an app-side reflection trick.
Persist it in the generator workflow with exact expected-context checks and a
test for reproducible generation. Do not edit only `micropython_embed/py/*`:
`native/tools/build_embed.py:579` overwrites every py source from the pinned
checkout. Do not dirty or mutate the vendor checkout as an implicit build step.
Apply a reviewed, version-checked overlay during package assembly, with any
preprocessor-visible new qstr/root declarations also present during generation.

### Value snapshots without running user getters

Capture bounded, immutable display snapshots on the execution worker before
publishing the pause. The smallest safe display uses direct exact-type reads:
None/bool/int/float/str/bytes, and bounded built-in tuple/list/dict children.
Known getters such as `mp_obj_str_get_data` and `mp_obj_float_get` are C
accessors; use them only after exact built-in type/tag checks
(`py/obj.h:940`, `:961`, `:1100`). Walk exact dictionaries by map slots
(`py/obj.h:452`, `:479`), and exact lists/tuples by their raw item arrays
(`py/objlist.h:31`, `py/objtuple.h:31`).

Never call `repr`, `str`, `getattr`, `dir`, generic iteration, subscription,
sorting, equality, hashing or an arbitrary object's print slot. A dict key of
an unknown type also receives only a type placeholder. Unknown objects display
`<TypeName>` using their actual type name, with no property expansion. Bound
total bytes, string length, depth, item count, frame count and cycles. Preserve
explicit truncated/unbound/unsupported states. Avoid holding VM pointers in
events or UI handles; eager bounded snapshots need no VM access from poll or
after resume. If later expansion is added, queue the request to the paused
worker and invalidate its object IDs at each resume.

## Pause, stepping and lifetime

The current worker holds a global runtime lock from before `gc_init/mp_init`
until after file cleanup and `mp_deinit`
(`native/src/qfli_py_bridge.c:454`, `:488`, `:513`). Retain this lock throughout
pause. Releasing it would allow another run/check to reset the paused VM. Add a
**different**, session-owned mutex/condition for copied events, breakpoint
configuration and commands. Poll/continue/step/stop must never acquire the VM
runtime lock. Windows currently uses SRWLOCK, POSIX uses pthread_mutex
(`native/src/qfli_py_platform.c:48`, `:379`); add matching Windows condition
variable / pthread condition primitives, without a new dynamic dependency.

Proposed worker algorithm:

1. Claim the debug session once and retain a worker reference before queuing.
   On start, publish started; activate its trace callback. Store canonical
   project root, accepted entry/import filenames and an immutable copy of
   initial breakpoint configuration in session memory.
2. In the native trace callback, take a project line event, compare verified
   breakpoints and step state, and decide whether to stop. Exclude bundled
   `.qfli/python/bundled/v1` code and system/pseudo files from ordinary stepping.
   A project containment test alone does not exclude the bundled subtree.
3. On stop, snapshot actual location/stack/variables on the worker. Publish a
   paused event with a new pause generation and monotonic sequence. Wait on the
   condition in a predicate loop. The condition releases only the session
   mutex, leaving the VM runtime lock held. The UI remains runnable.
4. Continue consumes that pause generation and switches back to breakpoint
   mode. Step-into pauses at the next accepted **line trace event**, including a
   callee. Step-over records paused frame/code-state identity and depth, skips
   deeper frames, and pauses at the next line at that frame or a returning
   ancestor. Step-out waits for an accepted ancestor line. Call/yield/return
   semantics must be tested; do not use raw event counts as a call stack.
5. Stop atomically requests the existing cancel token and signals the condition
   even while paused. Release every session lock before raising/unwinding.
   Existing VM init/loop/return hooks and sleep checks already call cancellation
   (`native/port/mpconfigport.h:60`; `native/src/qfli_py_hal.c:236`). For prompt
   stop from the callback, restore trace-recursion state safely or return with
   a scheduled exception; an unguarded raise skips
   `mp_prof_callback_invoke`'s `prof_callback_is_executing=false` at
   `py/profile.c:305`. Test this path rather than relying on next-run mp_init.
6. Runtime errors, compile errors, Stop, disposal and normal finish share one
   terminal path. Clear the active debugger/trace before VM teardown, free
   metadata via VM lifetime, publish terminal state once, and retain copied
   terminal events until acknowledged or disposed. No API frees a session while
   its queued/running worker owns it. Late commands become typed no-ops.

An explicit Pause command while running requires a check on every instruction
or existing loop hook in addition to line callbacks if it must stop a same-line
loop. Stop is already achievable without adding that capability. Publish only
implemented command flags in capability discovery.

### Ordinary-run cost

Simply enabling `MICROPY_PY_SYS_SETTRACE` is not free when debug is off.
`FRAME_ENTER` invokes `mp_prof_frame_enter` without checking global callback
(`py/vm.c:157`), and that function allocates frame/code objects before testing
`prof_trace_cb` (`py/profile.c:325`, `:343`). Bytecode functions also retain raw
code metadata under the trace configuration. A guarded overlay can skip
frame allocation/update when there is no trace callback and keep the existing
code-state chain correct; that overlay needs real no-trace and nested-call tests.
Even then extra fields/branches remain. Measure and describe the cost honestly;
do not claim binary size/allocation/performance identity without evidence.

## Additive ABI and transport design

Keep `qfli_py_run`, `qfli_py_execute[_into]` and their results unchanged
(`native/src/qfli_py_bridge.h:71`, `:81`). Add an opaque `QfliPyDebugSession`
family, for example:

```c
uint32_t qfli_py_debug_capabilities(void); /* versioned bit flags */
QfliPyDebugSession *qfli_py_debug_create(/* copied settings + breakpoints */);
void qfli_py_debug_execute_into(QfliPyRunResult *result,
    /* existing execution arguments */, QfliPyDebugSession *session);
int qfli_py_debug_command(QfliPyDebugSession *session,
    uint64_t pause_generation, int command);
char *qfli_py_debug_poll_json(QfliPyDebugSession *session, size_t max_bytes);
void qfli_py_debug_json_free(char *json);
void qfli_py_debug_release(QfliPyDebugSession *session);
```

These are proposed names, not existing exports. An optional atomic replacement
breakpoints command can be added with copied bounded config. Prefer bounded
nonblocking poll to native-to-Dart or NAPI cross-thread callbacks for the first
implementation. Poll drains serialized snapshots only; no VM access occurs.
Reject malformed command/config values. Use generation checks so a delayed
Continue cannot accidentally release a later pause. Native worker and wrapper
registry references must protect concurrent release/command/poll lifetimes.

Event payload should carry schema version, opaque public session ID, sequence,
kind, state/reason, pause generation, source file/line, frame snapshots,
variables availability/truncation, and the actual terminal status. Bound the
ring and event sizes. A paused or terminal state cannot be silently dropped
when a log/event ring is full; reserve state slots or retain latest authoritative
state separately and expose a dropped-event count. Do not block VM execution
waiting for UI to drain ordinary telemetry.

### OHOS

`native/src/qfli_py_napi.cpp:188` already executes on an async worker and
`:205` marshals its result on completion. Add create/debugRun/poll/command/
release exports; the debugRun Promise remains pending while paused. Poll and
commands perform bounded native copies/signaling on the ArkTS thread and must
not use another queued VM task. This avoids async-worker-pool starvation while
a worker is paused.

Both `native/ohos/QfliPyNative.ets` and
`ohos/entry/src/main/ets/plugins/QfliPyNative.ets` must remain byte-identical.
Reuse opaque string IDs and the existing claimed-session pattern
(`native/ohos/QfliPyNative.ets:247`, `:581`), with a distinct debug registry or
typed debug session entries. Detect every required native export before
advertising debugger support, as existing cancellation discovery does at
`:132`. Add MethodChannel prepareDebug/debugRun/debugPoll/debugCommand/
releaseDebug mappings. Preserve result/error completion for synchronous
throws, Promise rejects and malformed native outcomes.

Current `releaseRun` deletes and frees immediately on run completion
(`:284`, `:598`); copying this exactly would discard final debugger events.
Debug workers may settle first, but the copied event/session object must remain
until final drain + release. Disposal requests Stop immediately, continues
cleanup until native settlement, then releases the final wrapper reference.
Do not release a token merely because the Dart UI has stopped listening.

### Dart FFI

`lib/python_ffi.dart:138` creates a native token, sends its address to an
`Isolate.run` worker at `:246`, and releases it only when that worker settles
(`:180`). Extend this pattern with a native debug session pointer and optional
debug bindings. The worker invokes the new debug execution function; the owner
isolate polls/commands directly through bounded nonblocking FFI calls. It does
not need to receive a Dart callback from the blocked native thread.

Probe optional symbols separately from legacy bindings (`:249`) so an old
library remains a usable normal runner and advertises debugger=false. Return a
typed session with events, final result, continue/step/stop/dispose. Keep its
native worker reference until actual settlement. The active runtime lease must
remain held through a paused session and its real exit, using the app-owned
`lib/python_runtime_activity.dart` coordination already consumed by
`lib/python_runner.dart:256` and `:308`.

The shared core currently exposes `WebPreviewSession.debugStream` in
`../qfli_studio_core/lib/services/studio_profile.dart:287`, and ProgramRunner /
ProgramRunResult at `:305` / `:329`. Inspection found no general breakpoint
debugger provider/session contract. Agree that contract with the C owner before
UI integration; do not write core or repurpose web preview logs as Python
debugger state.

## Required configuration and generated changes

1. Set `MICROPY_PY_SYS_SETTRACE (1)` in `native/port/mpconfigport.h`; preserve
   existing persistent-code-load/save and source-line options. The source-line
   default is already enabled by the port's ROM level (`py/mpconfig.h:774`),
   but explicitly test that debugger compilation never uses optimize=3
   (`py/emitbc.c:427`).
2. Regenerate the embed package through `native/tools/build_embed.py`. It
   scans all py sources (`:287`) and regenerates qstr/module/root headers
   (`:404`, `:482`, `:503`), then copies the port and generated files
   (`:604`, `:621`). New trace qstrs must come from this scan, not hand-edited
   `qstrdefs.generated.h`. Core thread fields are conditional in mpstate and do
   not automatically require a new port root declaration.
3. If named locals / nondebug frame-allocation guards are included, persist
   exact reproducible source overlays and synchronization tests in the
   generator. The desktop builder reads the tracked embed package without
   regeneration (`native/desktop/CMakeLists.txt:7`), while OHOS regeneration is
   triggered by port/tool mtimes (`native/CMakeLists.txt:88`, `:131`). Verify both
   use the same resulting trace/metadata code and config.
4. Add debugger C source to OHOS, desktop, Android and native host build source
   lists. Preserve legacy ABI and ELF dependency policy. Rebuild each claimed
   ABI; a version string unchanged at 1.24.1 is insufficient proof that the
   rebuilt library includes the debugger exports.

### Concrete build and adapter entry points

| Boundary | Existing insertion point |
| --- | --- |
| OHOS shared library source list | `native/CMakeLists.txt:201` (bridge at `:208`, NAPI at `:209`) |
| Desktop FFI library source list | `native/desktop/CMakeLists.txt:19` (bridge at `:24`, into-result wrappers at `:27`) |
| Android shared library source list | `native/android/CMakeLists.txt:21` (bridge at `:28`, JNI at `:29`) |
| Native host executable list | `native/tests/run_host.sh:10` and `:11`; append debugger C file and an independent controller-thread test source |
| Apple source staging list | `native/apple/podspec.rb:5` through existing `qfli_py_ffi.c` entry at `:11`; add debugger source |
| Apple retained C symbols | `native/apple/podspec.rb:72`; add new dynamically looked-up debugger exports to retained linker symbols |
| Existing portable result-out wrappers | `native/src/qfli_py_ffi.c:4` and `:12`; use the same out-result convention for debug execution |
| Existing NAPI async invocation and exports | `native/src/qfli_py_napi.cpp:188` and `:459`; add optional debugger exports without changing Run argument order |
| Existing JNI worker call / token exports | `native/src/qfli_py_jni.cpp:92`, `:113`, `:122`, `:128`; add debug JNI methods if Android advertises debugger capability |
| Android transport and executor | `android/app/src/main/kotlin/com/azurekiln/qfli/pyflow/QfliPyNative.kt:37`, `:45`, `:154`; direct command/poll calls must not queue behind its paused single executor |
| OHOS MethodChannel methods | `native/ohos/QfliPyNative.ets:524`; both byte-identical copies need the same typed registry and handlers |
| FFI optional lookup and worker | `lib/python_ffi.dart:249`, `:246`; preserve legacy bindings when optional symbols are absent |
| App runtime result/lease integration | `lib/python_runner.dart:335`, `:400`; add a separate debugger adapter once C's provider contract is frozen |

Recommended native files are `native/src/qfli_py_debug.[ch]` for session/control/
serialization and worker-side trace/value snapshots, plus necessary bridge,
platform condition primitives, generator overlays and source-list changes. Keep
the debugger ABI declaration either in that header or included additively from
`qfli_py_bridge.h`; it must have the same public export visibility convention.
No UI callback may receive MicroPython object pointers.

For the scope hook, a concrete minimal metadata structure is
`{scope_kind, local_count, entry_count, entries[{qstr, slot, kind, flags}]}`.
Copy it once per successful source scope while debug is active, attach its
GC-owned pointer to raw code, and leave that pointer null for nondebug/source
compilation and loaded .mpy code. Pass the scope to an app-owned C hook rather
than moving the VM/compiler data structures into Dart. Match final slot numbers
after closure shifts, not the earlier scope pass. Include the raw-code common
layout extension and successful-final-emit hook in a deterministic overlay.

For the normal-run guard, preserve `prev_state` / current_code_state setup and
teardown but guard `mp_prof_frame_enter` when no global trace callback is active;
guard `mp_prof_frame_update` for null frames as appropriate. Verify nested calls,
trace installation before entry, any supported mid-run settrace behavior and
generator resumption. A blanket removal of FRAME_ENTER/FRAME_SETUP corrupts
the thread chain and is not a valid optimization. If the public sys.settrace
semantics cannot be preserved by this narrow guard, accept/document measured
nondebug overhead first instead of shipping an untested optimization.

### Recommended implementation ownership

- **One native debugger owner:** exclusive batch over `native/src/`, port
  config, metadata/frame guards, generator/overlays, generated embed package,
  all native build lists and real native tests. The modules batch is complete,
  but serialized generation/builds must still be coordinated with root. Freeze
  header/status/event schema before adapter work; no second worker edits the
  bridge/platform/generator concurrently.
- **Platform transport owner after ABI freeze:** NAPI/JNI + ArkTS/Kotlin
  registry/poll/commands and adapter tests. The native owner can retain NAPI if
  splitting `native/src` would otherwise overlap. Poll/control must be tested
  from the actual platform thread while execution is paused.
- **Dart debugger owner after public-contract freeze:** optional FFI binding,
  typed session parsing, runtime lease and provider adaptation. Coordinate with
  current analyzer/tools owners before touching runner/FFI/tool pages. It can
  work in a new app-owned adapter file while existing owners settle.
- **C coordinator:** general shared-core debugger/provider/panel contract and
  UI. This Python task must consume that contract and must not edit common core
  or add a second general debugger API under the Python product.

The first handoff milestone should be a real native test that pauses before a
file write, shows a real nested frame and metadata-backed local, steps, continues,
stops while paused, and then runs normally. That makes the ABI concretely
reviewable before asynchronous platform and shared UI wiring multiply it.

## Meaningful acceptance tests

These are proposed tests; none was run during this research.

1. **Real pause before effect:** a native worker executes a file with line 3
   writing a marker. A separate controller thread receives paused(line=3),
   verifies marker absence while paused, Continue, then verifies marker and
   exact output/exit. A UI-only event double cannot prove this.
2. **Actual stack and locals:** nested functions with parameters, ordinary
   locals, unbound/deleted locals, closure cells/free vars, Unicode names and
   global shadowing. Assert values from the real state at two pauses; verify
   values change after step. Explicitly exercise generator/comprehension/class
   behavior and per-scope unsupported states.
3. **No user code during inspection:** objects whose __repr__, __str__,
   property getter, __getattribute__, __iter__, comparison and hash mutate a
   counter or throw. Pause and snapshot variables; counter stays unchanged.
   Include such objects as container values and dictionary keys, with cyclic
   containers and oversized strings to prove all bounds.
4. **Line semantics:** step into a helper, step over its nested calls, step out
   to the actual caller, two breakpoint visits in a loop, same-line statements,
   return/yield and caught/uncaught exceptions. Confirm next-line pause occurs
   before that next line's effect. Same-line infinite loop remains stoppable.
5. **Source identity:** imported project module, nested/Unicode path,
   identically named files in different projects, missing/blank breakpoint
   lines, .mpy-loaded frame without locals metadata, excluded bundled module.
   No false project stop or invented relocated breakpoint is accepted.
6. **Lifetime and concurrency:** Stop while paused, Stop while running/inside
   sleep, Stop before queued execution, disposal during start, duplicate start,
   stale pause-generation command, late poll/command/release, runtime error and
   queue/allocation failure. Every run settles once; no use-after-free; a
   subsequent ordinary run succeeds. A paused VM cannot be reset by analyzer.
7. **Bounds/state retention:** poll slowly, overflow telemetry ring, pause
   without any poll, terminate and then drain, dispose with no listener. Paused
   and terminal state remain observable, sequence/drop counters are truthful,
   memory stays bounded and Stop never waits behind the VM lock.
8. **Normal-run regression:** existing real native suite plus allocation and
   elapsed-time comparisons with trace compiled on/callback off. Exercise
   no-callback nested calls after any guarded FRAME_ENTER optimization and a
   normal run after a debugger error/Stop.
9. **Adapter behavior:** real DLL FFI debug worker + owner-isolate control;
   actual ArkTS handler tests for optional capability discovery, opaque IDs,
   malformed events/commands, rejection cleanup and final-event draining; byte
   parity of ArkTS copies. Keep mocked mapping evidence separate from VM proof.
10. **Installed OHOS:** final matching HAP/library build, exported debugger
    capability, line/stack/locals evidence, step/continue/Stop while UI remains
    responsive, imported source, disposal/error/recovery and ordinary run.
    Record source/library/HAP hashes, event order, ABI/device identity and
    actual outcomes. Host success alone leaves the installed-OHOS gate open.
