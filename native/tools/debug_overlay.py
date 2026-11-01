"""Version-checked MicroPython debugger metadata and non-traced frame guards.

The vendor checkout is never changed. These transformations are applied only
while assembling the tracked embedding package; qstr collection still scans
the original source with the maintained port configuration.
"""

from __future__ import annotations

import hashlib

EXPECTED = {
    "compile.c": "88fd2e50f154b7bca297276d0f4deb9d5aa748e36b6e1be3dc5b78522eb237b4",
    "vm.c": "28e6344248b74f5bc9d74342781d760f3b0bd36141f878335a89dad746d69932",
    "emitglue.h": "04bc4314892d13491780cee9ad598a8c7637a66fe97428777910e41d499a2731",
    "profile.c": "d3bda4f846012bb550425e7cc6af14d8155d15930aad408cf0aaffcafec5af37",
}


def _replace(source: str, before: str, after: str, count: int = 1) -> str:
    if source.count(before) != count:
        raise ValueError("MicroPython debugger overlay context changed")
    return source.replace(before, after)


def apply_debug_overlay(name: str, data: bytes) -> bytes:
    if name not in EXPECTED:
        return data
    source = data.decode("utf-8").replace("\r\n", "\n")
    if hashlib.sha256(source.encode()).hexdigest() != EXPECTED[name]:
        raise ValueError("Debugger overlay requires pinned MicroPython 1.24.1: " + name)
    if name == "emitglue.h":
        source = _replace(
            source,
            "    // line_of_definition is a Python source line where the raw_code was\n"
            "    // created e.g. MP_BC_MAKE_FUNCTION. This is different from lineno info\n"
            "    // stored in prelude, which provides line number for first statement of\n"
            "    // a function. Required to properly implement \"call\" trace event.\n",
            "",
        )
        source = _replace(
            source,
            "    #if MICROPY_PY_SYS_SETTRACE\n"
            "    uint32_t line_of_definition;\n"
            "    mp_bytecode_prelude_t prelude;\n"
            "    #endif\n",
            "    #if MICROPY_PY_SYS_SETTRACE\n"
            "    mp_bytecode_prelude_t prelude;\n"
            "    #endif\n",
            2,
        )
        source = _replace(
            source,
            "    bool is_generator;\n",
            "    bool is_generator;\n"
            "    #if MICROPY_PY_SYS_SETTRACE\n"
            "    // Definition source line for call events, not the first body line.\n"
            "    // This fills the 64-bit common-header padding.\n"
            "    uint32_t line_of_definition;\n"
            "    #endif\n",
            2,
        )
        source = _replace(
            source,
            "    struct _mp_raw_code_t **children;\n",
            "    struct _mp_raw_code_t **children;\n"
            "    #if QFLI_PY_DEBUG_METADATA\n"
            "    void *qfli_debug_metadata; // GC-owned, never serialized\n"
            "    #endif\n",
            2,
        )
    elif name == "compile.c":
        source = _replace(source, '#include "py/smallint.h"\n',
            '#include "py/smallint.h"\n#if QFLI_PY_DEBUG_METADATA\n'
            '#include "qfli_debug_metadata.h"\n#endif\n')
        source = _replace(source,
            "                while (!compile_scope(comp, s, MP_PASS_EMIT)) {\n"
            "                }\n",
            "                while (!compile_scope(comp, s, MP_PASS_EMIT)) {\n"
            "                }\n"
            "                #if QFLI_PY_DEBUG_METADATA\n"
            "                if (comp->compile_error == MP_OBJ_NULL) {\n"
            "                    qfli_py_debug_record_scope(s);\n"
            "                }\n"
            "                #endif\n")
    elif name == "vm.c":
        source = _replace(source,
            "    if (!mp_prof_is_executing) { \\\n        mp_prof_frame_enter(code_state); \\\n",
            "    if ((MP_STATE_THREAD(prof_trace_callback) || code_state->frame) && !mp_prof_is_executing) { \\\n        mp_prof_frame_enter(code_state); \\\n")
        source = _replace(source,
            "    if (!mp_prof_is_executing) { \\\n        code_state->frame = MP_OBJ_TO_PTR(mp_prof_frame_update(code_state)); \\\n",
            "    if (code_state->frame && !mp_prof_is_executing) { \\\n        code_state->frame = MP_OBJ_TO_PTR(mp_prof_frame_update(code_state)); \\\n")
        source = _replace(source,
            "    if (!mp_prof_is_executing && code_state->frame && ",
            "    if (code_state->frame && !mp_prof_is_executing && ",
            2)
    elif name == "profile.c":
        source = _replace(source, '#include "py/objfun.h"\n',
            '#include "py/objfun.h"\n#include "py/nlr.h"\n')
        source = _replace(source,
            "    mp_obj_t a[3] = {MP_OBJ_FROM_PTR(args->frame), args->event, args->arg};\n"
            "    mp_obj_t top = mp_call_function_n_kw(callback, 3, 0, a);\n\n"
            "    mp_prof_is_executing = false;\n",
            "    mp_obj_t a[3] = {MP_OBJ_FROM_PTR(args->frame), args->event, args->arg};\n"
            "    mp_obj_t top;\n"
            "    nlr_buf_t trace_nlr;\n"
            "    if (nlr_push(&trace_nlr) == 0) {\n"
            "        top = mp_call_function_n_kw(callback, 3, 0, a);\n"
            "        nlr_pop();\n"
            "    } else {\n"
            "        mp_prof_is_executing = false;\n"
            "        nlr_jump(trace_nlr.ret_val);\n"
            "    }\n"
            "    mp_prof_is_executing = false;\n")
    return source.encode("utf-8")
