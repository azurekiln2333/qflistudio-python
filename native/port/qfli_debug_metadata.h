#ifndef QFLI_PY_DEBUG_METADATA_H
#define QFLI_PY_DEBUG_METADATA_H

#include "py/scope.h"

/* GC-owned metadata: only source compilation during a debug VM creates it.
 * It is attached to raw code and is deliberately absent from .mpy files. */
typedef struct {
    qstr name;
    uint16_t slot;
    uint8_t kind;
    uint8_t flags;
} qfli_py_debug_local_t;
typedef struct {
    uint16_t scope_kind;
    uint16_t num_locals;
    uint16_t count;
    qfli_py_debug_local_t entries[];
} qfli_py_debug_metadata_t;

void qfli_py_debug_record_scope(scope_t *scope);

#endif
