# Current native debugger source review (unbuilt A + B, ABI layout/lifetime)

Date: 2026-10-26
Scope: ordinary-path optimizations A (VM trace guards) and B (raw-code layout), plus
ABI layout and object-lifetime contracts.
Method: static source reading only. No compiler, build, SDK, WSL, Dart, Flutter, control,
device or channel execution. Only this note was written. READY704 stays frozen.

## Verdict

**F1 is fixed at source and unrun.** F1 was a real trace enable/disable defect that
reached product code. It is repaired in the overlay and in the tracked source, and two
regressions were added. Patch B, ABI, persistence, GC lifetime and port/generated sync
pass. Nothing here is built or executed, so the new regressions stay unknown until a
native build grant.

## Pinned hashes

| File | Bytes | SHA256 |
| --- | --- | --- |
| `micropython_embed/py/vm.c` (A) | 64543 | `bef4d4b5f2d334e21a8e76a834e4f3f0bb1a1f2382d6f08c8bc4ced43d05a589` |
| `micropython_embed/py/emitglue.h` (B) | 6008 | `5bba2c8746b258e6f788a83dca870faa08196b2bceb33ad2420f6a87b350be49` |
| `micropython_embed/py/profile.c` | 32037 | `8f722ffa057dbccfaf520cdd5f831ceea59430ab1c0bf3860cf9cfef3125905e` |
| `micropython_embed/py/bc.h` | 15264 | `bcadf7af4a74bb0e20b3933aa7ebf739c82d189eb9d04c65f4f8bec42e487fe2` |
| `micropython_embed/py/objfun.h` | 4942 | `2851fe4c0d564bef90790edd334334c32e9188805262317a91ded6fa7ea702cc` |
| `micropython_embed/port/mpconfigport.h` | 9882 | `8bbad61b8cf20c5eeabdd2981b82e4745decfe1bb895ec454957ea9719867b5c` |
| `port/mpconfigport.h` | 9882 | `8bbad61b8cf20c5eeabdd2981b82e4745decfe1bb895ec454957ea9719867b5c` |
| `micropython_embed/port/qfli_debug_metadata.h` | 566 | `74e96633a0fbbe688a7b6123e622022b0af78cfa5203020684b2803350151fba` |
| `port/qfli_debug_metadata.h` | 566 | `74e96633a0fbbe688a7b6123e622022b0af78cfa5203020684b2803350151fba` |
| `native/src/qfli_py_debug.c` | 31054 | `9b1ac56bfb4bafd9f453d4ed10065b5381908f9818b8961426d01417e009ab54` |
| `native/src/qfli_py_debug.h` | 3146 | `8564ae80c153fb6e422615a052d9f8c525eec21b93d0256468529b96a3a2cf87` |
| `native/tools/debug_overlay.py` | 5424 | `7bb9b1ab724958dc7ed1e1e0dd732bb9f60e4b7b00e49d669b66e3c7d90beb39` |
| `native/tests/debug_overlay_test.py` | 2230 | `b70e0eeb3aa25493218f7f9ffa579530784bda44e2b90ac742ee6e6df3ea52d0` |
| `native/tests/debugger.py` | 32891 | `86a6e8d82b957eb75d53d6e9c5026cef80dd33771bfe9d3b47c92d70b5f833c7` |

Overlay pins match `third_party` byte for byte, so `micropython_embed` is reproducible
overlay output, not a hand-edited tree:

- `third_party/micropython/py/vm.c` = `28e6344248b74f5bc9d74342781d760f3b0bd36141f878335a89dad746d69932`
- `third_party/micropython/py/emitglue.h` = `04bc4314892d13491780cee9ad598a8c7637a66fe97428777910e41d499a2731`

## F1 (fixed at source, unrun) — trace disable was not honoured by a resumed generator

Patch A is not a pure reorder. Its `FRAME_ENTER` change removes a side effect, so the
frame lifecycle changes. Overlay transform (`native/tools/debug_overlay.py:86-95`):

```c
// before: if (!mp_prof_is_executing) { mp_prof_frame_enter(code_state); }
// after:  if (MP_STATE_THREAD(prof_trace_callback) && !mp_prof_is_executing) { mp_prof_frame_enter(code_state); }
```

The call event is not the difference; `mp_prof_frame_enter` already returns early on a
null global. The difference is `code_state->frame`:

- `profile.c:339-349` allocates the frame and assigns `code_state->frame = frame` **before**
  the `if (!prof_trace_cb) return` at line 351.
- `profile.c:283` gives a new frame `callback = MP_OBJ_NULL`.
- `profile.c:321-325` `mp_prof_settrace` changes only the global; it never clears a frame
  callback.
- `profile.c:431-435` clears `frame->callback` only for `MP_BC_RETURN_VALUE`, not
  `MP_BC_YIELD_VALUE`.

A generator suspended at a yield keeps the frame built while tracing was active, with a
non-null callback. Upstream re-enters `mp_prof_frame_enter` on resume, replaces the frame
and drops the callback. Patch A skips that when the global is null, so the stale frame and
callback survive. `TRACE_TICK` (`vm.c:185`) still passes
`code_state->frame && !mp_prof_is_executing && code_state->frame->callback`, so the stale
callback keeps firing.

Product-visible: the debugger installs its own callback as the global
(`native/src/qfli_py_debug.c:663`) and its handler guards only on the session
(`:598-601`, `if (session == NULL) return;`), never re-checking the global against
`debug_trace_object`. A stale frame keeps calling `debug_trace`, so line events and pauses
can still fire after user code disabled tracing, contradicting the `traceDisabled`
contract (`:187-188`, set at `:669`).

### Minimal reproduction (source-derived, not executed)

```python
import sys
def gen():
    yield 1
    yield 2
g = gen()
next(g)            # frame created with the active trace callback
sys.settrace(None)
next(g)            # patched: FRAME_ENTER skipped, stale callback still fires
```

Contract and upstream: no trace events after `sys.settrace(None)`. Patched: `LINE`/`RETURN`
continue on the second resume. Mirror case: disable, then re-enable a different callback,
then resume; the old generator keeps the old callback instead of rebinding.

### Exact test gap

- `native/tests/debugger.py:559-570` covers enable → run → disable at top level, never
  suspending a generator across the disable.
- `native/tests/debugger.py:406-420` resumes a generator, but with tracing active, so patch
  A matches upstream there.

No test covers "generator suspended, tracing disabled, generator resumed".

### Applied fix (overlay plus engine)

Both operands are kept in the guard, so ordinary calls still skip allocation:

```c
if ((MP_STATE_THREAD(prof_trace_callback) || code_state->frame) && !mp_prof_is_executing) {
    mp_prof_frame_enter(code_state);
}
```

Applied to `native/tools/debug_overlay.py` and to the tracked
`native/micropython_embed/py/vm.c`; the vendor tree is untouched. A fresh ordinary entry
has no frame and no global callback, so the allocation win is unchanged. A resumed
generator that still holds a frame re-enters, the frame is replaced, and the callback is
dropped, which is the upstream path.

The live tick still reads the frame callback, as upstream does, so the frame that is
currently executing keeps ticking until it returns. Only resume-time re-entry resets a
callback, which is why the guard needs the frame operand rather than a global check alone.

### Added regressions (source only, unrun)

- `native/tests/debugger.py`
  `test_ordinary_trace_disable_does_not_retrace_resumed_generator` runs a real VM without
a debug session. The generator body sits on lines 7-8, away from every module line, so a
line number in that range can only come from the generator frame. It records
`(event, frame.f_lineno)` pairs, disables tracing, resumes, and asserts stdout is exactly
`True 0`: tracing worked before the disable, and it raised nothing in the generator after
it. `f_lineno` is a supported attribute (`profile.c:245`), not a CPython assumption. The
assertion is scoped by line number because the live tick keeps tracing the module frame,
so a bare event count would be contaminated.
- `native/tests/debugger.py`
  `test_debugger_trace_disable_suppresses_resumed_generator_pause` runs two debug
sessions. The control puts a breakpoint on the first suspension point and asserts a real
pause with `reason == "breakpoint"`, `line == 3` and frame name `gen`, so the subject
cannot pass for a generator that never pauses. The subject puts the breakpoint on the
second yield, behind `sys.settrace(None)`, and asserts a clean `done` finish with no
`paused` event. Both assert `terminated["traceDisabled"] is True`.

These regressions are unrun. They need a distinct native build grant; there is no red or
green result on the frozen DLL.

## Notes (low)

- N1 config coupling: `compile.c:3597-3599` guards the `qfli_py_debug_record_scope` call
  with `#if QFLI_PY_DEBUG_METADATA`, but the definition is unguarded and reads
  `rc->qfli_debug_metadata`, a field that exists only while the macro is 1
  (`mpconfigport.h:61`). Pinned at 1, so no current defect; a flip breaks the build rather
  than misbehaving silently.
- N2 cost-note wording: `native-debugger-cost-review.md` says no frame or code object is
  allocated when the global callback is null. True for the patched tree, not for pre-A+B
  source. Read its "tracing off" figures as post-patch numbers.

## Pass items (compact)

- A ordinary path: every `code_state->frame` use in `vm.c` is guarded (`:174-175`, `:182`,
  `:185`, `:789-790`). `FRAME_ENTER` runs once at `vm.c:256`, `FRAME_SETUP` at `:261`. A
  non-traced run carries `frame == NULL` with no NULL dereference. `mp_prof_frame_update`
  was already NULL-safe, so the `FRAME_UPDATE` guard and `TRACE_TICK` reorder are
  truth-equivalent. Regression: `test_non_debug_nested_calls_do_not_allocate_trace_frames`
  asserts < 1024 bytes across 2000 calls, which fails on pre-patch behaviour.
- B layout: `line_of_definition` moves to offset 4, after `is_generator`, filling the
  64-bit pointer padding. Offsets 0/4/8/16/24/32/40, total 104 → 96, matching the cost
  note. The first two proto bytes stay at offset 0, so `mp_proto_fun_is_bytecode` is
  unaffected. The overlay applies the transform twice (`count=2`), keeping full and
  truncated structs in step.
- B persistence and ABI: `persistentcode.c:573-598` writes `fun_data_len`, `n_children`,
  `prelude_offset`, `kind` by field and never serialises `line_of_definition`;
  `emitglue.c:54-58` uses `m_new0` plus an explicit zero; `mpy-tool.py` uses designated
  initialisers. Existing `.mpy` and frozen code are unaffected. `mp_raw_code_t` and
  `mp_code_state_t` are internal, so the exported headers and schema version 1 are
  unchanged.
- Lifetime, GC, closures, cells: metadata is GC-owned via `raw_code->qfli_debug_metadata`,
  rooted by `fun_bc->rc` (`objfun.h:38`) and each code state's `fun_bc` (`bc.h`); the flex
  array is sized exactly from LOCAL/CELL/FREE; `scope->raw_code == NULL` is rejected;
  `m_new` raises instead of returning NULL. `frame` and `prev_state` live in `bc.h` only
  under `MICROPY_PY_SYS_SETTRACE`, which the port enables.
- Port/generated sync: `port/mpconfigport.h` equals `micropython_embed/port/mpconfigport.h`
  and both `qfli_debug_metadata.h` copies match, byte for byte.
  `native/tests/debug_overlay_test.py` asserts `apply_debug_overlay(third_party)` equals
  the tracked `micropython_embed` file byte for byte, rejects double application, is
  CRLF-insensitive, and passes unrelated files through. That is the sync guard for A and B.

## Gates

Run here: `native/tests/debug_overlay_test.py`, the source-only overlay unittest, plus
AST parse checks on the edited Python. That proves the overlay and the tracked
`micropython_embed` source agree byte for byte; it proves nothing about runtime behaviour.
A separate root-run check reproduced the same result independently: 4/4 overlay tests and
valid AST for `debugger.py`, `debug_overlay.py` and `debug_overlay_test.py`, with 30
authored debugger cases. The vendor tree stayed unmodified.

Unrun: compiler and native build for the embed package and the OHOS target;
`native/tests/debugger.py`, now 30 cases after the two additions, including the allocation
regression and the two new trace-disable regressions; the cost benchmark; and a
built-artifact ABI check. F1 is fixed at source, and the two new regressions are the
runtime confirmation that stays red/green-unknown until a distinct native build grant.