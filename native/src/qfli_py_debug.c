#include "qfli_py_debug.h"
#include "qfli_py_platform.h"

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "py/runtime.h"
#include "py/profile.h"
#include "py/bc0.h"
#include "py/objfun.h"
#include "py/objint.h"
#include "py/objlist.h"
#include "py/objtuple.h"
#include "py/objstr.h"
#include "qfli_debug_metadata.h"

#define DEBUG_BREAKPOINT_LIMIT 128
#define DEBUG_EVENT_LIMIT 16
#define DEBUG_EVENT_BYTES (192u * 1024u)
#define DEBUG_POLL_BYTES (256u * 1024u)
#define DEBUG_FRAME_LIMIT 16
#define DEBUG_VARIABLE_LIMIT 64
#define DEBUG_STRING_BYTES 256

typedef enum { DEBUG_CREATED, DEBUG_RUNNING, DEBUG_PAUSED, DEBUG_TERMINATED } DebugState;
typedef struct { char *file; uint32_t line; } DebugBreakpoint;
typedef struct { char *json; size_t length; int important; uint64_t generation; } DebugEvent;

struct qfli_py_debug_session {
    QfliPyCondition *condition;
    QfliPyCancel *cancel;
    size_t references;
    int worker_active;
    int claimed;
    uint64_t id;
    uint64_t sequence;
    uint64_t generation;
    uint64_t observed_generation;
    uint64_t dropped;
    DebugState state;
    int stop_on_entry;
    int step;
    size_t step_depth;
    const mp_code_state_t *step_frame; /* worker-only, cleared before teardown */
    int step_target_returned;
    char *project;
    char *entry;
    char *bundled;
    DebugBreakpoint breakpoints[DEBUG_BREAKPOINT_LIMIT];
    size_t breakpoint_count;
    DebugEvent events[DEBUG_EVENT_LIMIT];
    size_t event_count;
    int trace_disabled;
    char *terminal_buffer;
};

/* Accessed only by the worker while it owns the existing global VM lock. */
static QfliPyDebugSession *active_session;

typedef struct { char *data; size_t used; size_t capacity; int failed; } Json;

static void json_raw_n(Json *json, const char *text, size_t length)
{
    if (json->failed || length >= json->capacity - json->used) {
        json->failed = 1;
        return;
    }
    memcpy(json->data + json->used, text, length);
    json->used += length;
    json->data[json->used] = '\0';
}
static void json_raw(Json *json, const char *text) { json_raw_n(json, text, strlen(text)); }
static void json_uint(Json *json, uint64_t value)
{
    char text[32];
    snprintf(text, sizeof(text), "%" PRIu64, value);
    json_raw(json, text);
}
static void json_string_n(Json *json, const char *text, size_t length)
{
    json_raw(json, "\"");
    for (size_t i = 0; i < length && !json->failed; ++i) {
        unsigned char ch = (unsigned char)text[i];
        if (ch == '"') json_raw(json, "\\\"");
        else if (ch == '\\') json_raw(json, "\\\\");
        else if (ch < 32) {
            char escape[7];
            snprintf(escape, sizeof(escape), "\\u%04x", ch);
            json_raw(json, escape);
        } else json_raw_n(json, text + i, 1);
    }
    json_raw(json, "\"");
}
static void json_string(Json *json, const char *text)
{
    json_string_n(json, text == NULL ? "" : text, text == NULL ? 0 : strlen(text));
}
static size_t utf8_prefix(const char *text, size_t length, size_t bound)
{
    if (length <= bound) return length;
    size_t end = bound;
    while (end > 0 && ((unsigned char)text[end] & 0xc0) == 0x80) --end;
    return end;
}
static char *copy_string(const char *text)
{
    size_t length = strlen(text) + 1;
    char *copy = malloc(length);
    if (copy != NULL) memcpy(copy, text, length);
    return copy;
}
static const char *state_name(DebugState state)
{
    switch (state) {
        case DEBUG_CREATED: return "created";
        case DEBUG_RUNNING: return "running";
        case DEBUG_PAUSED: return "paused";
        default: return "terminated";
    }
}
static int accepted_file(QfliPyDebugSession *session, const char *file, char *resolved)
{
    return file != NULL && qfli_py_path_is_absolute(file)
        && qfli_py_realpath(file, resolved, QFLI_PY_PATH_MAX) != NULL
        && qfli_py_path_type(resolved) == QFLI_PY_PATH_FILE
        && qfli_py_path_contains(session->project, resolved)
        && !qfli_py_path_contains(session->bundled, resolved);
}

uint32_t qfli_py_debug_capabilities(void)
{
    return QFLI_PY_DEBUG_BREAKPOINTS | QFLI_PY_DEBUG_STEP | QFLI_PY_DEBUG_STACK
        | QFLI_PY_DEBUG_LOCALS | QFLI_PY_DEBUG_STOP;
}

/* All queue operations require the session mutex. Important paused/terminal
 * states cannot be evicted. A pause can only be resumed with a generation
 * obtained from its event, so at most one undrained pause can exist. */
static void enqueue_event(QfliPyDebugSession *session, char *data, int important)
{
    if (session->event_count == DEBUG_EVENT_LIMIT) {
        size_t discard = 0;
        while (discard < session->event_count && session->events[discard].important) ++discard;
        /* Commands require a polled generation, so this cannot occur for a
         * paused/terminal publication. Preserve retained states defensively. */
        if (discard == session->event_count) { free(data); ++session->dropped; return; }
        free(session->events[discard].json);
        memmove(&session->events[discard], &session->events[discard + 1],
            (session->event_count - discard - 1) * sizeof(DebugEvent));
        --session->event_count;
        ++session->dropped;
    }
    DebugEvent *event = &session->events[session->event_count++];
    event->json = data;
    event->length = strlen(data);
    event->important = important;
    event->generation = session->state == DEBUG_PAUSED ? session->generation : 0;
}

static void event_prefix(Json *json, QfliPyDebugSession *session, const char *reason)
{
    json_raw(json, "{\"sequence\":");
    json_uint(json, ++session->sequence);
    json_raw(json, ",\"kind\":\"state\",\"state\":");
    json_string(json, state_name(session->state));
    json_raw(json, ",\"reason\":");
    json_string(json, reason);
    json_raw(json, ",\"pauseGeneration\":");
    json_uint(json, session->generation);
}

static void state_event(QfliPyDebugSession *session, const char *reason, int exit_code)
{
    /* This small allocation is made before taking any VM state snapshots. */
    char *data = session->state == DEBUG_TERMINATED ? session->terminal_buffer : malloc(1024);
    if (data == NULL) return;
    if (session->state == DEBUG_TERMINATED) session->terminal_buffer = NULL;
    Json json = {data, 0, 1024, 0};
    event_prefix(&json, session, reason);
    if (session->state == DEBUG_TERMINATED) {
        char number[32];
        snprintf(number, sizeof(number), "%d", exit_code);
        json_raw(&json, ",\"exitCode\":");
        json_raw(&json, number);
        json_raw(&json, ",\"traceDisabled\":");
        json_raw(&json, session->trace_disabled ? "true" : "false");
    }
    json_raw(&json, "}");
    enqueue_event(session, data, session->state == DEBUG_TERMINATED);
}

QfliPyDebugSession *qfli_py_debug_create(const char *project_dir,
    const char *entry_file, int stop_on_entry)
{
    char project[QFLI_PY_PATH_MAX], entry[QFLI_PY_PATH_MAX];
    if (project_dir == NULL || entry_file == NULL
        || !qfli_py_path_is_absolute(project_dir) || !qfli_py_path_is_absolute(entry_file)
        || qfli_py_realpath(project_dir, project, sizeof(project)) == NULL
        || qfli_py_realpath(entry_file, entry, sizeof(entry)) == NULL
        || qfli_py_path_type(project) != QFLI_PY_PATH_DIRECTORY
        || qfli_py_path_type(entry) != QFLI_PY_PATH_FILE
        || !qfli_py_path_contains(project, entry)) return NULL;
    QfliPyDebugSession *session = calloc(1, sizeof(*session));
    if (session == NULL) return NULL;
    session->condition = qfli_py_condition_create();
    session->cancel = qfli_py_cancel_create();
    session->terminal_buffer = malloc(1024);
    session->references = 1;
    session->project = copy_string(project);
    session->entry = copy_string(entry);
    size_t bundled_length = strlen(project) + sizeof("/.qfli/python/bundled");
    session->bundled = malloc(bundled_length);
    if (session->bundled != NULL)
        snprintf(session->bundled, bundled_length, "%s/.qfli/python/bundled", project);
    if (session->condition == NULL || session->cancel == NULL || session->terminal_buffer == NULL || session->project == NULL
        || session->entry == NULL || session->bundled == NULL) {
        qfli_py_condition_free(session->condition);
        qfli_py_cancel_free(session->cancel);
        free(session->terminal_buffer); free(session->project); free(session->entry); free(session->bundled); free(session);
        return NULL;
    }
    if (qfli_py_path_contains(session->bundled, entry)) {
        qfli_py_debug_release(session);
        return NULL;
    }
    session->id = qfli_py_next_session_id();
    session->stop_on_entry = stop_on_entry != 0;
    session->state = DEBUG_CREATED;
    state_event(session, "created", 0);
    return session;
}

void qfli_py_debug_retain(QfliPyDebugSession *session)
{
    if (session == NULL) return;
    qfli_py_condition_lock(session->condition);
    ++session->references;
    qfli_py_condition_unlock(session->condition);
}

void qfli_py_debug_release(QfliPyDebugSession *session)
{
    if (session == NULL) return;
    qfli_py_condition_lock(session->condition);
    size_t remaining = --session->references;
    if (remaining == 1 && session->worker_active) {
        qfli_py_cancel_request(session->cancel);
        qfli_py_condition_signal(session->condition);
    }
    qfli_py_condition_unlock(session->condition);
    if (remaining != 0) return;
    for (size_t i = 0; i < session->breakpoint_count; ++i) free(session->breakpoints[i].file);
    for (size_t i = 0; i < session->event_count; ++i) free(session->events[i].json);
    qfli_py_cancel_free(session->cancel);
    qfli_py_condition_free(session->condition);
    free(session->terminal_buffer); free(session->project); free(session->entry); free(session->bundled); free(session);
}

int qfli_py_debug_set_breakpoints(QfliPyDebugSession *session,
    const char *const *files, const uint32_t *lines, size_t count)
{
    if (session == NULL || (count != 0 && (files == NULL || lines == NULL))) return QFLI_PY_DEBUG_INVALID;
    if (count > DEBUG_BREAKPOINT_LIMIT) return QFLI_PY_DEBUG_BOUNDS;
    DebugBreakpoint next[DEBUG_BREAKPOINT_LIMIT] = {{0}};
    int status = QFLI_PY_DEBUG_OK;
    for (size_t i = 0; i < count; ++i) {
        char resolved[QFLI_PY_PATH_MAX];
        if (lines[i] == 0 || lines[i] > INT32_MAX || !accepted_file(session, files[i], resolved)) {
            status = QFLI_PY_DEBUG_INVALID;
            break;
        }
        next[i].file = copy_string(resolved);
        next[i].line = lines[i];
        if (next[i].file == NULL) { status = QFLI_PY_DEBUG_OOM; break; }
    }
    if (status == QFLI_PY_DEBUG_OK) {
        qfli_py_condition_lock(session->condition);
        if (session->state == DEBUG_TERMINATED) status = QFLI_PY_DEBUG_WRONG_STATE;
        else {
            for (size_t i = 0; i < session->breakpoint_count; ++i) free(session->breakpoints[i].file);
            memcpy(session->breakpoints, next, count * sizeof(DebugBreakpoint));
            session->breakpoint_count = count;
        }
        qfli_py_condition_unlock(session->condition);
    }
    if (status != QFLI_PY_DEBUG_OK)
        for (size_t i = 0; i < count; ++i) free(next[i].file);
    return status;
}

int qfli_py_debug_command(QfliPyDebugSession *session, uint64_t generation, int command)
{
    if (session == NULL || command < QFLI_PY_DEBUG_CONTINUE || command > QFLI_PY_DEBUG_STOP_REQUEST)
        return QFLI_PY_DEBUG_INVALID;
    qfli_py_condition_lock(session->condition);
    int status = QFLI_PY_DEBUG_OK;
    if (session->state == DEBUG_TERMINATED) status = QFLI_PY_DEBUG_WRONG_STATE;
    else if (command == QFLI_PY_DEBUG_STOP_REQUEST) {
        qfli_py_cancel_request(session->cancel);
        qfli_py_condition_signal(session->condition);
    } else if (session->state != DEBUG_PAUSED) status = QFLI_PY_DEBUG_WRONG_STATE;
    else if (generation == 0 || generation != session->generation
        || generation != session->observed_generation) status = QFLI_PY_DEBUG_STALE;
    else {
        session->step = command == QFLI_PY_DEBUG_CONTINUE ? 0 : command;
        session->state = DEBUG_RUNNING;
        state_event(session, "resumed", 0);
        qfli_py_condition_signal(session->condition);
    }
    qfli_py_condition_unlock(session->condition);
    return status;
}

char *qfli_py_debug_poll_json(QfliPyDebugSession *session, size_t max_bytes)
{
    if (session == NULL) return NULL;
    if (max_bytes == 0) max_bytes = DEBUG_POLL_BYTES;
    if (max_bytes < 1024 || max_bytes > DEBUG_POLL_BYTES) return NULL;
    char *data = malloc(max_bytes);
    if (data == NULL) return NULL;
    Json json = {data, 0, max_bytes, 0};
    qfli_py_condition_lock(session->condition);
    json_raw(&json, "{\"schema\":1,\"sessionId\":\""); json_uint(&json, session->id);
    json_raw(&json, "\",\"state\":"); json_string(&json, state_name(session->state));
    json_raw(&json, ",\"sequence\":"); json_uint(&json, session->sequence);
    json_raw(&json, ",\"pauseGeneration\":"); json_uint(&json, session->generation);
    json_raw(&json, ",\"droppedEvents\":"); json_uint(&json, session->dropped);
    json_raw(&json, ",\"events\":[");
    size_t consumed = 0;
    while (consumed < session->event_count) {
        DebugEvent *event = &session->events[consumed];
        if (event->length + 128 >= max_bytes - json.used) break;
        if (consumed != 0) json_raw(&json, ",");
        json_raw_n(&json, event->json, event->length);
        if (event->generation != 0) session->observed_generation = event->generation;
        free(event->json);
        ++consumed;
    }
    memmove(session->events, session->events + consumed,
        (session->event_count - consumed) * sizeof(DebugEvent));
    session->event_count -= consumed;
    json_raw(&json, "]");
    if (consumed == 0 && session->event_count != 0) {
        json_raw(&json, ",\"requiredBytes\":");
        json_uint(&json, session->events[0].length + 512);
    }
    json_raw(&json, "}");
    qfli_py_condition_unlock(session->condition);
    if (json.failed) { free(data); return NULL; }
    return data;
}
void qfli_py_debug_json_free(char *json) { free(json); }

/* Exact built-in access only. No repr/str/getattr/iterator/equality/hash slots
 * are called. Unknown objects expose their actual type name, without members. */
static void value_snapshot(Json *json, mp_obj_t value, unsigned depth,
    const mp_obj_t *ancestors, size_t ancestor_count)
{
    if (value == MP_OBJ_NULL) {
        json_raw(json, "{\"type\":\"unbound\",\"value\":\"<unbound>\",\"unbound\":true}");
        return;
    }
    const mp_obj_type_t *type = mp_obj_get_type(value);
    json_raw(json, "{\"type\":");
    const char *type_name = qstr_str(type->name);
    json_string_n(json, type_name, utf8_prefix(type_name, strlen(type_name), DEBUG_STRING_BYTES));
    json_raw(json, ",\"value\":");
    char text[512];
    if (value == mp_const_none) json_string(json, "None");
    else if (value == mp_const_true || value == mp_const_false)
        json_string(json, value == mp_const_true ? "True" : "False");
    else if (mp_obj_is_small_int(value)) {
        snprintf(text, sizeof(text), "%" PRIdPTR, (intptr_t)MP_OBJ_SMALL_INT_VALUE(value));
        json_string(json, text);
    } else if (type == &mp_type_int) {
        #if MICROPY_LONGINT_IMPL == MICROPY_LONGINT_IMPL_MPZ
        mp_obj_int_t *integer = MP_OBJ_TO_PTR(value);
        if (mpz_max_num_bits(&integer->mpz) <= 512) {
            mpz_as_str_inpl(&integer->mpz, 10, "", 'a', 0, text);
            json_string(json, text);
        } else { json_string(json, "<large integer>"); json_raw(json, ",\"truncated\":true"); }
        #elif MICROPY_LONGINT_IMPL == MICROPY_LONGINT_IMPL_LONGLONG
        snprintf(text, sizeof(text), "%lld", (long long)((mp_obj_int_t *)MP_OBJ_TO_PTR(value))->val);
        json_string(json, text);
        #else
        json_string(json, "<integer>");
        #endif
    } else if (mp_obj_is_float(value)) {
        snprintf(text, sizeof(text), "%.17g", (double)mp_obj_float_get(value));
        json_string(json, text);
    } else if (type == &mp_type_str) {
        size_t length;
        const char *string = mp_obj_str_get_data(value, &length);
        size_t take = utf8_prefix(string, length, DEBUG_STRING_BYTES);
        json_string_n(json, string, take);
        if (take < length) json_raw(json, ",\"truncated\":true");
    } else if (type == &mp_type_bytes) {
        size_t length;
        const unsigned char *bytes = (const unsigned char *)mp_obj_str_get_data(value, &length);
        size_t take = length > 64 ? 64 : length;
        for (size_t i = 0; i < take; ++i) snprintf(text + i * 2, 3, "%02x", bytes[i]);
        text[take * 2] = '\0';
        json_string(json, text);
        json_raw(json, ",\"encoding\":\"hex\"");
        if (take < length) json_raw(json, ",\"truncated\":true");
    } else {
        int container = type == &mp_type_list || type == &mp_type_tuple || type == &mp_type_dict;
        size_t type_length = strlen(type_name);
        size_t type_take = utf8_prefix(type_name, type_length, DEBUG_STRING_BYTES);
        snprintf(text, sizeof(text), "<%.*s>", (int)type_take, type_name);
        json_string(json, text);
        if (type_take < type_length) json_raw(json, ",\"truncated\":true");
        if (container) {
            int cycle = 0;
            for (size_t i = 0; i < ancestor_count; ++i) if (ancestors[i] == value) cycle = 1;
            if (cycle || depth >= 2) {
                json_raw(json, cycle ? ",\"cycle\":true" : ",\"truncated\":true");
            } else {
                mp_obj_t next_ancestors[3];
                memcpy(next_ancestors, ancestors, ancestor_count * sizeof(mp_obj_t));
                next_ancestors[ancestor_count] = value;
                json_raw(json, ",\"children\":[");
                size_t total = 0, shown = 0;
                if (type == &mp_type_dict) {
                    mp_map_t *map = &((mp_obj_dict_t *)MP_OBJ_TO_PTR(value))->map;
                    total = map->used;
                    for (size_t i = 0; i < map->alloc && shown < 4; ++i) {
                        if (!mp_map_slot_is_filled(map, i)) continue;
                        if (shown++) json_raw(json, ",");
                        json_raw(json, "{\"key\":");
                        value_snapshot(json, map->table[i].key, depth + 1, next_ancestors, ancestor_count + 1);
                        json_raw(json, ",\"item\":");
                        value_snapshot(json, map->table[i].value, depth + 1, next_ancestors, ancestor_count + 1);
                        json_raw(json, "}");
                    }
                } else {
                    mp_obj_t *items;
                    if (type == &mp_type_list) {
                        mp_obj_list_t *list = MP_OBJ_TO_PTR(value); total = list->len; items = list->items;
                    } else {
                        mp_obj_tuple_t *tuple = MP_OBJ_TO_PTR(value); total = tuple->len; items = tuple->items;
                    }
                    for (; shown < total && shown < 4; ++shown) {
                        if (shown) json_raw(json, ",");
                        value_snapshot(json, items[shown], depth + 1, next_ancestors, ancestor_count + 1);
                    }
                }
                json_raw(json, "]");
                if (shown < total) json_raw(json, ",\"truncated\":true");
            }
        }
    }
    json_raw(json, "}");
}

static int append_variable(Json *frame, const char *variable_name, size_t name_length,
    mp_obj_t value, int separator)
{
    char data[4096], value_data[3072];
    Json json = {data, 0, sizeof(data), 0};
    Json snapshot = {value_data, 0, sizeof(value_data), 0};
    mp_obj_t ancestors[3] = {0};
    value_snapshot(&snapshot, value, 0, ancestors, 0);
    json_raw(&json, "{\"name\":");
    json_string_n(&json, variable_name, utf8_prefix(variable_name, name_length, DEBUG_STRING_BYTES));
    if (!snapshot.failed) {
        json_raw(&json, ",");
        json_raw_n(&json, value_data + 1, snapshot.used - 1);
    }
    if (snapshot.failed || json.failed) {
        json.used = 0; json.failed = 0;
        json_raw(&json, "{\"name\":");
        json_string_n(&json, variable_name, utf8_prefix(variable_name, name_length, DEBUG_STRING_BYTES));
        json_raw(&json, ",\"type\":\"bounded\",\"value\":\"<snapshot limit>\",\"truncated\":true}");
    }
    if (json.used + 512 >= frame->capacity - frame->used) return 0;
    if (separator) json_raw(frame, ",");
    json_raw_n(frame, data, json.used);
    return name_length > DEBUG_STRING_BYTES ? 2 : 1;
}

static void frame_snapshot(Json *json, const mp_code_state_t *state,
    uint64_t generation, size_t index, size_t current_line)
{
    const mp_raw_code_t *rc = state->fun_bc->rc;
    const mp_module_context_t *context = state->fun_bc->context;
    const mp_bytecode_prelude_t *prelude = &rc->prelude;
    const qfli_py_debug_metadata_t *metadata = rc->qfli_debug_metadata;
    qstr filename = context->constants.qstr_table[0];
    qstr name = context->constants.qstr_table[prelude->qstr_block_name_idx];
    json_raw(json, "{\"id\":\""); json_uint(json, generation); json_raw(json, ":"); json_uint(json, index);
    json_raw(json, "\",\"file\":"); json_string(json, qstr_str(filename));
    json_raw(json, ",\"name\":"); json_string(json, qstr_str(name));
    json_raw(json, ",\"line\":");
    size_t line = current_line;
    if (line == 0) line = mp_bytecode_get_source_line(prelude->line_info, prelude->line_info_top,
        state->ip - prelude->opcodes);
    json_uint(json, line);
    int available = metadata != NULL && metadata->scope_kind != SCOPE_CLASS;
    json_raw(json, ",\"localsAvailable\":"); json_raw(json, available ? "true" : "false");
    if (!available) {
        json_raw(json, ",\"localsReason\":");
        json_string(json, metadata == NULL ? "no-source-metadata" : "class-namespace-unavailable");
    }
    json_raw(json, ",\"variables\":[");
    size_t shown = 0;
    int truncated = 0;
    if (available && metadata->scope_kind == SCOPE_MODULE) {
        mp_map_t *map = &context->module.globals->map;
        for (size_t i = 0; i < map->alloc; ++i) {
            if (!mp_map_slot_is_filled(map, i)) continue;
            mp_obj_t key = map->table[i].key;
            if (mp_obj_get_type(key) != &mp_type_str) { truncated = 1; continue; }
            size_t name_length;
            const char *name_data = mp_obj_str_get_data(key, &name_length);
            if (shown == DEBUG_VARIABLE_LIMIT) { truncated = 1; break; }
            int appended = append_variable(json, name_data, name_length,
                map->table[i].value, shown != 0);
            if (!appended) {
                truncated = 1; break;
            }
            if (appended == 2) truncated = 1;
            ++shown;
        }
    } else if (available) {
        for (size_t i = 0; i < metadata->count; ++i) {
            const qfli_py_debug_local_t *local = &metadata->entries[i];
            mp_obj_t value = MP_OBJ_NULL;
            if (local->slot < metadata->num_locals && local->slot < state->n_state) {
                value = state->state[state->n_state - 1 - local->slot];
                if (value != MP_OBJ_NULL && (local->kind == ID_INFO_KIND_CELL || local->kind == ID_INFO_KIND_FREE))
                    value = mp_obj_cell_get(value);
            }
            if (shown == DEBUG_VARIABLE_LIMIT) { truncated = 1; break; }
            int appended = append_variable(json, qstr_str(local->name),
                qstr_len(local->name), value, shown != 0);
            if (!appended) {
                truncated = 1; break;
            }
            if (appended == 2) truncated = 1;
            ++shown;
        }
    }
    json_raw(json, "]");
    if (truncated) json_raw(json, ",\"truncated\":true");
    json_raw(json, "}");
}

static size_t stack_depth(const mp_code_state_t *state)
{
    size_t depth = 0;
    for (; state != NULL && depth < 1024; state = state->prev_state) ++depth;
    return depth;
}

static void pause_event(QfliPyDebugSession *session, mp_obj_frame_t *frame,
    const char *file, const char *reason)
{
    char *data = malloc(DEBUG_EVENT_BYTES);
    if (data == NULL) {
        /* A pause without observable state cannot be resumed safely. */
        qfli_py_cancel_request(session->cancel);
        return;
    }
    Json json = {data, 0, DEBUG_EVENT_BYTES, 0};
    event_prefix(&json, session, reason);
    json_raw(&json, ",\"file\":"); json_string(&json, file);
    json_raw(&json, ",\"line\":"); json_uint(&json, frame->lineno);
    json_raw(&json, ",\"frames\":[");
    const mp_code_state_t *state = frame->code_state;
    size_t shown = 0;
    int truncated = 0;
    while (state != NULL && shown < DEBUG_FRAME_LIMIT) {
        char frame_data[16384];
        Json snapshot = {frame_data, 0, sizeof(frame_data), 0};
        frame_snapshot(&snapshot, state, session->generation, shown, shown == 0 ? frame->lineno : 0);
        if (snapshot.failed || snapshot.used + 512 >= json.capacity - json.used) { truncated = 1; break; }
        if (shown) json_raw(&json, ",");
        json_raw_n(&json, frame_data, snapshot.used);
        ++shown;
        state = state->prev_state;
    }
    if (state != NULL) truncated = 1;
    json_raw(&json, "],\"truncated\":"); json_raw(&json, truncated ? "true" : "false");
    json_raw(&json, "}");
    enqueue_event(session, data, 1);
}

static mp_obj_t debug_trace(mp_obj_t frame_object, mp_obj_t event, mp_obj_t argument);
static MP_DEFINE_CONST_FUN_OBJ_3(debug_trace_object, debug_trace);

static mp_obj_t debug_trace(mp_obj_t frame_object, mp_obj_t event, mp_obj_t argument)
{
    (void)argument;
    QfliPyDebugSession *session = active_session;
    if (session == NULL) return mp_const_none;
    mp_obj_frame_t *frame = MP_OBJ_TO_PTR(frame_object);
    if (event == MP_OBJ_NEW_QSTR(MP_QSTR_return) && frame->code_state == session->step_frame
        && *frame->code_state->ip == MP_BC_RETURN_VALUE) session->step_target_returned = 1;
    if (event != MP_OBJ_NEW_QSTR(MP_QSTR_line)) return MP_OBJ_FROM_PTR(&debug_trace_object);
    const char *file = qstr_str(frame->code->context->constants.qstr_table[0]);
    char resolved[QFLI_PY_PATH_MAX];
    if (!accepted_file(session, file, resolved)) return MP_OBJ_FROM_PTR(&debug_trace_object);
    size_t depth = stack_depth(frame->code_state);
    qfli_py_condition_lock(session->condition);
    const char *reason = NULL;
    if (session->stop_on_entry) {
        reason = "entry";
        session->stop_on_entry = 0;
    }
    for (size_t i = 0; reason == NULL && i < session->breakpoint_count; ++i)
        if (session->breakpoints[i].line == frame->lineno && strcmp(session->breakpoints[i].file, resolved) == 0)
            reason = "breakpoint";
    if (reason == NULL && (session->step == QFLI_PY_DEBUG_STEP_INTO
        || (session->step == QFLI_PY_DEBUG_STEP_OVER && (depth < session->step_depth
            || (depth == session->step_depth && frame->code_state == session->step_frame
                && !session->step_target_returned)))
        || (session->step == QFLI_PY_DEBUG_STEP_OUT && depth < session->step_depth))) reason = "step";
    if (reason != NULL && !qfli_py_cancel_requested(session->cancel)) {
        session->state = DEBUG_PAUSED;
        session->step = 0;
        session->step_depth = depth;
        session->step_frame = frame->code_state;
        session->step_target_returned = 0;
        ++session->generation;
        pause_event(session, frame, resolved, reason);
        while (session->state == DEBUG_PAUSED && !qfli_py_cancel_requested(session->cancel))
            qfli_py_condition_wait(session->condition);
    }
    qfli_py_condition_unlock(session->condition);
    /* The overlay resets trace recursion state even if cancellation unwinds
     * this callback. Controls never hold the VM mutex or touch VM objects. */
    qfli_py_check_cancel();
    return MP_OBJ_FROM_PTR(&debug_trace_object);
}

void qfli_py_debug_record_scope(scope_t *scope)
{
    if (active_session == NULL || scope->raw_code == NULL || scope->raw_code->kind != MP_CODE_BYTECODE) return;
    size_t count = 0;
    for (size_t i = 0; i < scope->id_info_len; ++i)
        if (scope->id_info[i].kind == ID_INFO_KIND_LOCAL || scope->id_info[i].kind == ID_INFO_KIND_CELL
            || scope->id_info[i].kind == ID_INFO_KIND_FREE) ++count;
    size_t bytes = sizeof(qfli_py_debug_metadata_t) + count * sizeof(qfli_py_debug_local_t);
    qfli_py_debug_metadata_t *metadata = (qfli_py_debug_metadata_t *)m_new(byte, bytes);
    metadata->scope_kind = scope->kind;
    metadata->num_locals = scope->num_locals;
    metadata->count = count;
    size_t index = 0;
    for (size_t i = 0; i < scope->id_info_len; ++i) {
        id_info_t *id = &scope->id_info[i];
        if (id->kind != ID_INFO_KIND_LOCAL && id->kind != ID_INFO_KIND_CELL && id->kind != ID_INFO_KIND_FREE) continue;
        metadata->entries[index++] = (qfli_py_debug_local_t){id->qst, id->local_num, id->kind, id->flags};
    }
    scope->raw_code->qfli_debug_metadata = metadata;
}

void qfli_py_debug_vm_begin(QfliPyDebugSession *session)
{
    active_session = session;
    if (session != NULL) mp_prof_settrace(MP_OBJ_FROM_PTR(&debug_trace_object));
}
void qfli_py_debug_vm_end(QfliPyDebugSession *session)
{
    if (active_session != session) return;
    if (session != NULL) {
        session->trace_disabled = MP_STATE_THREAD(prof_trace_callback) != MP_OBJ_FROM_PTR(&debug_trace_object);
        mp_prof_settrace(mp_const_none);
    }
    active_session = NULL;
}

void qfli_py_debug_execute_into(QfliPyRunResult *result, const char *source,
    const char *stdin_text, int heap_kb, QfliPyDebugSession *session)
{
    if (result == NULL) return;
    if (session == NULL) {
        result->exit_code = 1; result->output = copy_string("");
        result->error = copy_string("Invalid debugger session."); result->truncated = 0;
        return;
    }
    qfli_py_condition_lock(session->condition);
    if (session->claimed) {
        qfli_py_condition_unlock(session->condition);
        result->exit_code = 1; result->output = copy_string("");
        result->error = copy_string("Debugger session already executed."); result->truncated = 0;
        return;
    }
    session->claimed = 1;
    session->worker_active = 1;
    ++session->references;
    session->state = DEBUG_RUNNING;
    state_event(session, "started", 0);
    qfli_py_condition_unlock(session->condition);
    *result = qfli_py_execute_debug_internal(source, stdin_text, heap_kb,
        session->project, session->entry, session->cancel, session);
    qfli_py_condition_lock(session->condition);
    session->state = DEBUG_TERMINATED;
    session->step_frame = NULL;
    state_event(session, result->exit_code == 130 ? "stopped" : result->exit_code == 0 ? "completed" : "error", result->exit_code);
    session->worker_active = 0;
    qfli_py_condition_unlock(session->condition);
    qfli_py_debug_release(session);
}
