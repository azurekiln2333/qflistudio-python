# Independent review: F1 generator-across-trace-disable repair

Date: 2026-10-26. Reviewer: independent of the repair owner (p3).
Task: `10-22-python-offline-tools`, debugger research.
Method: static source reading, file lookup and hashing only.

Verdict: **source-level PASS. No blocker.** The F1 repair, its two native
regressions and the overlay reproducibility contract all hold on reading. Every
runtime assertion remains **UNRUN**: no DLL was built or loaded, `debugger.py`
was not executed against any native library, and no compiler, analyzer, SDK, WSL,
Flutter, device, control or channel command ran. Root separately confirms the
isolated overlay suite at 4/4 with AST validity; I did not repeat that run, and
this note adds no broad hash sweep beyond the reviewed files.

Earlier in this session I recorded F1 as unrepaired. That was true when read and
is now stale; p3 landed the change at 2026-10-26 07:07. Everything below reviews
the delivered tree.

## 1. Delivered hashes (p3 handoff, re-measured here)

| File | Bytes | SHA256 |
| --- | --- | --- |
| `native/tools/debug_overlay.py` | 5424 | `7bb9b1ab724958dc7ed1e1e0dd732bb9f60e4b7b00e49d669b66e3c7d90beb39` |
| `native/micropython_embed/py/vm.c` | 64543 | `bef4d4b5f2d334e21a8e76a834e4f3f0bb1a1f2382d6f08c8bc4ced43d05a589` |
| `native/tests/debugger.py` | 32891 | `86a6e8d82b957eb75d53d6e9c5026cef80dd33771bfe9d3b47c92d70b5f833c7` |
| `native/tests/debug_overlay_test.py` | 2230 | `b70e0eeb3aa25493218f7f9ffa579530784bda44e2b90ac742ee6e6df3ea52d0` |
| `native/micropython_embed/py/emitglue.h` (unchanged) | 6008 | `5bba2c8746b258e6f788a83dca870faa08196b2bceb33ad2420f6a87b350be49` |
| `native/micropython_embed/py/profile.c` (unchanged) | 32037 | `8f722ffa057dbccfaf520cdd5f831ceea59430ab1c0bf3860cf9cfef3125905e` |

`EXPECTED` still pins the four vendor files and each pin still equals the current
`third_party/micropython/py` bytes: `vm.c 28e63442…`, `emitglue.h 04bc4314…`,
`compile.c 88fd2e50…`, `profile.c d3bda4f8…`. The overlay pin was **not** relaxed
to fit a changed vendor tree.

`debugger.py` now defines **30** `test_` methods. The historical
`python-native-debugger.json` and `python-native-debugger-posix.json` record 28
and predate these cases; neither may be cited as evidence for this repair.

## 2. The change, and why it is mechanically sound

One hunk, in the overlay only (`debug_overlay.py:87-89`), reproduced verbatim in
the tracked tree (`vm.c:161-163`):

```c
if ((MP_STATE_THREAD(prof_trace_callback) || code_state->frame) && !mp_prof_is_executing) {
    mp_prof_frame_enter(code_state);
}
```

Three facts decide whether this actually repairs F1 rather than only looking
plausible. Each was checked in the delivered tree.

**(a) The guard reads the same global the setter writes.** `profile.c:41` is
`#define prof_trace_cb MP_STATE_THREAD(prof_trace_callback)`, and
`mp_prof_settrace` writes `prof_trace_cb` (`profile.c:323/325`). So the vm.c
term and the profile.c global are one variable. There is no second, unsynced
flag.

**(b) `FRAME_ENTER` runs on a generator resume, and the frame survives the
yield.** `vm.c:256` sits in the unconditional prologue after the
`run_code_state:` label, outside any conditional, before `FRAME_SETUP()` at
`:261`. Generator resume is `objgenerator.c:210`
`mp_execute_bytecode(&self->code_state, throw_value)` — the same entry point, so
the macro runs. `code_state->frame = NULL` exists at `bc.c:330`, but only inside
`mp_setup_code_state`, which initialises a **fresh** call; resume passes the
already-populated `self->code_state` and never re-runs it. The frame therefore
persists across `yield`, which is what the `|| code_state->frame` term keys on.

**(c) Re-entry replaces the stale callback.** `mp_prof_frame_enter` allocates at
`profile.c:333`, installs `code_state->frame = frame` at `:349`, and only then
returns early on the null global at `:351`. The fresh frame carries
`callback = MP_OBJ_NULL` from `mp_obj_new_frame` (`:283`), so the early return
leaves the **replaced** frame in place with no callback. `TRACE_TICK`
(`vm.c:185`) requires `code_state->frame->callback`, so the stale callback stops
being consulted. Ordinary re-entry with global null and `frame == NULL` still
short-circuits, so patch A's allocation win is preserved.

Consequence in the product path: `qfli_py_debug_vm_begin` sets
`debug_trace_object` as the global (`native/src/qfli_py_debug.c:663`). After user
`sys.settrace(None)`, a resumed generator now re-enters, drops the debugger
callback, and never reaches `debug_trace`. `traceDisabled` is then reported from
the global at `:669` and published at `:187-188`, consistent with events having
actually stopped.

## 3. Criteria check (pre-committed in the earlier note)

| # | Criterion | Result |
| --- | --- | --- |
| C1 | Change lives in the overlay, tracked `vm.c` is overlay output | **PASS** — the `after` string in `:89` matches `vm.c:161-162` exactly |
| C2 | `_replace` exactness and per-hunk `count` preserved | **PASS** — `FRAME_ENTER` hunk keeps default `count=1`; `FRAME_UPDATE` and `TRACE_TICK` keep `count=2` |
| C3 | Fresh entry with `frame == NULL` and null global still skips | **PASS** — `(global \|\| frame)` is false there; A's win holds |
| C4 | A frame that already exists is re-entered and rebuilt | **PASS** — per §2(c) |
| C5 | B layout, `qfli_debug_metadata`, `profile.c` nlr hunk untouched | **PASS** — `emitglue.h 5bba2c87…` and `profile.c 8f722ffa…` byte-identical to the pre-repair values |
| C6 | `EXPECTED` unchanged and matching `third_party` | **PASS** — all four pins recomputed and equal |
| C7 | Reproducibility contract intact | **PASS** — `debug_overlay_test.py` unmodified (`b70e0eeb…`); root's isolated 4/4 covers reproduction, double-apply rejection, CRLF and pass-through |
| C8 | Final hashes delivered | **PASS** — §1 |

## 4. Regression review, case by case

`test_ordinary_trace_disable_does_not_retrace_resumed_generator` (`debugger.py:569`)

- Uses only supported surface: `sys.settrace`, and `frame.f_lineno` — one of the
  five readable names in `frame_attr` (`profile.c:229-248`).
- Line arithmetic checked: `yield 1` / `yield 2` are lines 7-8, and no module
  statement occupies 7-8, so the `7 <= line <= 8` filter can only match generator
  body events. `def gen():` is line 6, and the CALL event's lineno is the
  definition line, so it is excluded correctly.
- Non-vacuous both ways: `pivot>0` is a positive control (events **must** exist
  from the traced first resume), and `late==0` is the negative assertion. A
  callback that never fires fails via `pivot>0`; a stale callback fails via
  `late`. Expectation is the literal `"True 0\n"`.
- Discriminating: on unfixed source the second resume keeps the frame callback,
  `TRACE_TICK` fires at line 8, and `late` is non-zero.

`test_debugger_trace_disable_suppresses_resumed_generator_pause` (`debugger.py:585`)

- Control, breakpoint at line 3 (first suspension): asserts
  `(reason, line) == ("breakpoint", 3)`, frame name `gen`, then a clean resume to
  `(0, "done\n")` and `traceDisabled: true`. That rules out "this generator never
  pauses", which is the failure mode that would make the subject vacuous.
- Subject, breakpoint at line 4 (after the disable): asserts zero `paused` events,
  completion of `(0, "done\n")`, and `traceDisabled: true`. Reaching `done`
  proves the generator really resumed, so the absence of a pause is meaningful
  rather than an early exit.
- Breakpoint rejection is guarded: `DebugRun.__init__` raises if
  `debug_set_breakpoints` returns non-zero, so "the breakpoint was never
  installed" cannot pass silently.
- Failure mode is bounded and visible. On unfixed source the subject pauses, the
  worker blocks in the pause loop, `finish()` joins with a 4 s timeout, issues
  cancel command 5, then raises `Debug worker did not settle`. The test fails
  rather than hanging the suite.
- No CPython-only attribute appears anywhere in `debugger.py`: zero matches for
  `f_trace`, `f_locals`, `f_trace_lines`, `gi_frame`, `gi_code`, `gi_yieldfrom`.
  This matters because `mp_type_frame` exposes only `f_back`, `f_code`,
  `f_globals`, `f_lasti`, `f_lineno`, is **not** writable
  (`profile.c:222-225` returns for non-load), and generator instances expose only
  `close/send/throw/pend_throw`. The CPython idiom `frame.f_trace = None` could
  not be used here, and it is not.

## 5. Residual findings (not blockers, root's call)

**R1 — the still-running frame keeps its callback after a disable.** The repair
restores correctness for frames that are **re-entered**, which is exactly the F1
case. A frame that is already executing does not re-enter, so when the debugger
has installed its callback at `vm_begin`, a `sys.settrace(None)` in the currently
running module or function frame leaves that frame's `callback` set until
`MP_BC_RETURN_VALUE` clears it (`profile.c:434-435`). `TRACE_TICK` keys on the
frame callback, not the global, so line events continue in that frame — and a
breakpoint on a still-executing line after the disable would still pause.
This is **not** an F1 regression and **not** introduced by patch A: upstream
behaves the same, because the global was only ever consulted at entry. It does
mean `traceDisabled: true` should be read as "the global was replaced", not as
"no further events are possible". Closing it would require a per-tick global
check and would change upstream trace semantics, so I recommend keeping it out of
this repair and recording it as a known scoping limit.

**R2 — allocation per resume after a traced session.** Once a frame exists, every
later resume re-enters and allocates a fresh frame even with tracing off, until
the generator finishes. That is upstream parity and is required for
correctness, but it is worth stating plainly: A's "no per-call frame allocation"
guarantee holds for runs that **never** enable tracing, and does not hold for a
generator that was traced at least once. `test_non_debug_nested_calls_…`
(`:605`) never enables tracing, so it remains valid and does not cover this path.

**R3 — spec now documents the requirement (corrected).** Earlier I wrote that the
spec said only "do not cache it across user `sys.settrace` calls" and lagged the
code. That was accurate at the 2026-10-24 12:07 revision and is now stale.
`native-python-runtime.md` was updated at **2026-10-26 07:16** (15061 bytes,
SHA256 `c4b0fc2aae05cf5eb97a7ddc3577c5da42bf2573ebf679a3e560b2d2c350ec2f`) and
now carries the guard verbatim with both operands, the instruction to keep both
so a fresh ordinary call still skips allocation, and the reason a global-only
test fails: a resumed generator still holds its previous frame, the upstream
re-entry that resets its per-frame callback is skipped, and the stale callback
keeps delivering events after `sys.settrace(None)`. It also names the two
required regressions. The spec additionally states the boundary that R1
describes — "the live tick uses the frame callback, as upstream does, so the
frame that is currently executing keeps ticking until it returns; only
resume-time frame re-entry resets the callback" — so R1 is a documented upstream
scope limit, not an undocumented gap, and needs no spec change. No spec edit by
me; I record the corrected state only.

## 6. Unrun, and what would confirm it

UNRUN: any build of `micropython_embed` or the desktop/OHOS libraries; `python
native/tests/debugger.py <dll>` against the 30 cases; the cost benchmark; any
ABI, device or control check. Root ran only the isolated overlay suite (4/4).

One built `debugger.py` run against a DLL containing this source is the single
gate that would confirm F1 behaviourally and turn this PASS from source-level
into observed. Until then this note asserts source correctness only, and the
historical 28-case reports describe the earlier captured source, not this tree.

## 7. Files

Only this note was written. No p3 file, overlay, tracked source, test, spec or
product file was edited, and no other worker's file was touched.

## 8. Release note

Released for the F1 scope: the generator-across-trace-disable repair, its two
native regressions, and the trace-entry spec. Release basis is **source reading
plus root's isolated overlay run (4/4, AST valid)**. Nothing runtime was
observed, so this releases source, not a verified binary.

| Artifact | Bytes | SHA256 |
| --- | --- | --- |
| `native/tools/debug_overlay.py` | 5424 | `7bb9b1ab724958dc7ed1e1e0dd732bb9f60e4b7b00e49d669b66e3c7d90beb39` |
| `native/micropython_embed/py/vm.c` | 64543 | `bef4d4b5f2d334e21a8e76a834e4f3f0bb1a1f2382d6f08c8bc4ced43d05a589` |
| `native/tests/debugger.py` (30 cases) | 32891 | `86a6e8d82b957eb75d53d6e9c5026cef80dd33771bfe9d3b47c92d70b5f833c7` |
| `native/tests/debug_overlay_test.py` | 2230 | `b70e0eeb3aa25493218f7f9ffa579530784bda44e2b90ac742ee6e6df3ea52d0` |
| `.trellis/spec/backend/native-python-runtime.md` | 15061 | `c4b0fc2aae05cf5eb97a7ddc3577c5da42bf2573ebf679a3e560b2d2c350ec2f` |

`emitglue.h` (`5bba2c87…`) and `profile.c` (`8f722ffa…`) are unchanged by this
repair, so patch B and the trace-callback nlr change are released as prior state,
not re-certified here.

What this release does **not** assert: no DLL or `.so` was built from this source;
`debugger.py` was not run against any native library, so the 30 cases including
both F1 regressions are unexecuted; the cost benchmark did not run; and no ABI,
device, OHOS or control result exists for this tree. The frozen Windows DLL
`52e7400f…` and its 28-case reports describe the earlier captured source and must
not be used as evidence for this delivery.

Carried forward, by design, and not defects: R1, a frame that is already
executing keeps ticking until it returns because the live tick keys on the frame
callback as upstream does; and R2, a generator traced at least once allocates a
frame per later resume. Both are upstream semantics, both are now written down in
the spec, and both are out of scope for F1.

Next gate, needing a distinct grant: one build of the embed package and a single
`python native/tests/debugger.py <library> --report …` run, which converts this
source-level PASS into an observed one and produces the 30-case report.
