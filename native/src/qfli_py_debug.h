#ifndef QFLI_PY_DEBUG_H
#define QFLI_PY_DEBUG_H

#include <stddef.h>
#include <stdint.h>
#include "qfli_py_bridge.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct qfli_py_debug_session QfliPyDebugSession;

enum {
    QFLI_PY_DEBUG_BREAKPOINTS = 1,
    QFLI_PY_DEBUG_STEP = 2,
    QFLI_PY_DEBUG_STACK = 4,
    QFLI_PY_DEBUG_LOCALS = 8,
    QFLI_PY_DEBUG_STOP = 16,
};
enum {
    QFLI_PY_DEBUG_CONTINUE = 1,
    QFLI_PY_DEBUG_STEP_INTO = 2,
    QFLI_PY_DEBUG_STEP_OVER = 3,
    QFLI_PY_DEBUG_STEP_OUT = 4,
    QFLI_PY_DEBUG_STOP_REQUEST = 5,
};
enum {
    QFLI_PY_DEBUG_OK = 0,
    QFLI_PY_DEBUG_INVALID = 1,
    QFLI_PY_DEBUG_WRONG_STATE = 2,
    QFLI_PY_DEBUG_STALE = 3,
    QFLI_PY_DEBUG_BOUNDS = 4,
    QFLI_PY_DEBUG_OOM = 5,
};

/* ABI/schema version 1. No eval/watch or asynchronous Pause capability. */
QFLI_PY_API uint32_t qfli_py_debug_capabilities(void);
/* Existing absolute project/entry paths are canonicalized and copied. */
QFLI_PY_API QfliPyDebugSession *qfli_py_debug_create(
    const char *project_dir, const char *entry_file, int stop_on_entry);
/* Each concurrent owner retains a reference. Release never blocks for the VM.
 * It requests Stop when the last external reference leaves an active worker.
 * Passing a pointer after releasing its last reference is invalid. */
QFLI_PY_API void qfli_py_debug_retain(QfliPyDebugSession *session);
QFLI_PY_API void qfli_py_debug_release(QfliPyDebugSession *session);
/* Atomically replaces <=128 copied breakpoints. A missing/outside/bundled file
 * is rejected. Lines are never relocated; an actual line event verifies a hit. */
QFLI_PY_API int qfli_py_debug_set_breakpoints(QfliPyDebugSession *session,
    const char *const *files, const uint32_t *lines, size_t count);
/* A session can be executed once. The worker owns a reference until real exit. */
QFLI_PY_API void qfli_py_debug_execute_into(QfliPyRunResult *result,
    const char *source, const char *stdin_text, int heap_kb,
    QfliPyDebugSession *session);
/* A non-Stop command requires the current nonzero pause generation from a
 * consumed paused event. Merely reading an envelope cannot acknowledge it. */
QFLI_PY_API int qfli_py_debug_command(QfliPyDebugSession *session,
    uint64_t pause_generation, int command);
/* Nonblocking copied JSON. max_bytes is [1024,262144], or 0 for 262144.
 * A small poll may return no events with requiredBytes for the next event.
 * Repeated polling drains the bounded state queue; terminal events survive
 * worker completion. NULL means allocation failure/invalid arguments. */
QFLI_PY_API char *qfli_py_debug_poll_json(QfliPyDebugSession *session,
    size_t max_bytes);
QFLI_PY_API void qfli_py_debug_json_free(char *json);

#ifdef __cplusplus
}
#endif

/* Worker-only bridge hooks. They run while the existing VM lock is held. */
void qfli_py_debug_vm_begin(QfliPyDebugSession *session);
void qfli_py_debug_vm_end(QfliPyDebugSession *session);
QfliPyRunResult qfli_py_execute_debug_internal(const char *source,
    const char *stdin_text, int heap_kb, const char *project_dir,
    const char *entry_file, QfliPyCancel *token, QfliPyDebugSession *session);

#endif
