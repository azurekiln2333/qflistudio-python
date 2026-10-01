#include "qfli_py_file.h"
#include "qfli_py_platform.h"

#include "py/builtin.h"
#include "py/runtime.h"
#include "py/persistentcode.h"
#include "py/stream.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct qfli_py_file_node {
    int fd;
    struct qfli_py_file_node *next;
};

typedef struct {
    mp_obj_base_t base;
    qfli_py_file_node_t *node;
} qfli_file_t;

static char project_root[QFLI_PY_PATH_MAX];
static qfli_py_file_node_t *open_files;

void qfli_py_file_begin(const char *project_dir)
{
    project_root[0] = '\0';
    if (project_dir != NULL && project_dir[0] != '\0' &&
        qfli_py_realpath(project_dir, project_root, sizeof(project_root)) == NULL)
        project_root[0] = '\0';
}

void qfli_py_file_end(void)
{
    qfli_py_file_node_t *node = open_files;
    while (node != NULL)
    {
        qfli_py_file_node_t *next = node->next;
        qfli_py_file_close(node);
        free(node);
        node = next;
    }
    open_files = NULL;
    project_root[0] = '\0';
}

qfli_py_file_node_t *qfli_py_file_track(int fd)
{
    qfli_py_file_node_t *node = malloc(sizeof(*node));
    if (node == NULL)
    {
        qfli_py_close(fd);
        mp_raise_OSError(MP_ENOMEM);
    }
    node->fd = fd;
    node->next = open_files;
    open_files = node;
    return node;
}

void qfli_py_file_close(qfli_py_file_node_t *node)
{
    if (node != NULL && node->fd >= 0)
    {
        int fd = node->fd;
        node->fd = -1;
        qfli_py_close(fd);
    }
}

static void resolve_path(mp_obj_t file, bool create, char resolved[QFLI_PY_PATH_MAX])
{
    size_t length;
    const char *name = (const char *)mp_obj_str_get_data(file, &length);
    char candidate[QFLI_PY_PATH_MAX];
    int written;

    if (project_root[0] == '\0')
        mp_raise_OSError(MP_ENOENT);
    if (length == 0 || strlen(name) != length)
        mp_raise_OSError(MP_EINVAL);

    written = qfli_py_path_is_absolute(name)
        ? snprintf(candidate, sizeof(candidate), "%s", name)
        : snprintf(candidate, sizeof(candidate), "%s/%s", project_root, name);
    if (written < 0 || (size_t)written >= sizeof(candidate))
        mp_raise_OSError(ENAMETOOLONG);

    if (qfli_py_realpath(candidate, resolved, QFLI_PY_PATH_MAX) != NULL)
    {
        if (!qfli_py_path_contains(project_root, resolved))
            mp_raise_OSError(MP_EACCES);
        return;
    }
    if (!create || errno != ENOENT)
        mp_raise_OSError(errno);

    char *slash = (char *)qfli_py_path_last_separator(candidate);
    if (slash == NULL || slash[1] == '\0' || strcmp(slash + 1, ".") == 0 ||
        strcmp(slash + 1, "..") == 0)
        mp_raise_OSError(MP_EINVAL);
    /* Keep the separator so both / and C:/ remain valid parent roots. */
    char first_name_char = slash[1];
    slash[1] = '\0';
    char parent[QFLI_PY_PATH_MAX];
    if (qfli_py_realpath(candidate, parent, sizeof(parent)) == NULL)
        mp_raise_OSError(errno);
    slash[1] = first_name_char;
    if (!qfli_py_path_contains(project_root, parent))
        mp_raise_OSError(MP_EACCES);
    written = snprintf(resolved, QFLI_PY_PATH_MAX, "%s/%s", parent, slash + 1);
    if (written < 0 || written >= QFLI_PY_PATH_MAX)
        mp_raise_OSError(ENAMETOOLONG);
}

void qfli_py_file_resolve(const char *name, int create, char *resolved)
{
    resolve_path(mp_obj_new_str(name, strlen(name)), create != 0, resolved);
}

static void write_bytecode(void *data, const char *bytes, size_t length)
{
    qfli_py_file_node_t *node = data;
    while (length > 0)
    {
        intptr_t written = qfli_py_write(node->fd, bytes, length);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) mp_raise_OSError(written < 0 ? errno : MP_EIO);
        bytes += written;
        length -= (size_t)written;
    }
}

void qfli_py_file_save_bytecode(mp_compiled_module_t *module, const char *name)
{
    char resolved[QFLI_PY_PATH_MAX];
    qfli_py_file_resolve(name, 1, resolved);
    int fd = qfli_py_open(resolved, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) mp_raise_OSError(errno);
    qfli_py_file_node_t *node = qfli_py_file_track(fd);
    mp_print_t print = {node, write_bytecode};
    mp_raw_code_save(module, &print);
    qfli_py_file_close(node);
}

static mp_uint_t file_read(mp_obj_t self, void *buf, mp_uint_t size, int *errcode)
{
    qfli_file_t *file = MP_OBJ_TO_PTR(self);
    if (file->node->fd < 0)
    {
        *errcode = EBADF;
        return MP_STREAM_ERROR;
    }
    intptr_t count;
    do { count = qfli_py_read(file->node->fd, buf, size); } while (count < 0 && errno == EINTR);
    if (count < 0)
    {
        *errcode = errno;
        return MP_STREAM_ERROR;
    }
    return (mp_uint_t)count;
}

static mp_uint_t file_write(mp_obj_t self, const void *buf, mp_uint_t size, int *errcode)
{
    qfli_file_t *file = MP_OBJ_TO_PTR(self);
    if (file->node->fd < 0)
    {
        *errcode = EBADF;
        return MP_STREAM_ERROR;
    }
    intptr_t count;
    do { count = qfli_py_write(file->node->fd, buf, size); } while (count < 0 && errno == EINTR);
    if (count < 0)
    {
        *errcode = errno;
        return MP_STREAM_ERROR;
    }
    return (mp_uint_t)count;
}

static mp_uint_t file_ioctl(mp_obj_t self, mp_uint_t request, uintptr_t arg, int *errcode)
{
    qfli_file_t *file = MP_OBJ_TO_PTR(self);
    int fd = file->node->fd;
    if (request == MP_STREAM_CLOSE)
    {
        qfli_py_file_close(file->node);
        return 0;
    }
    if (fd < 0)
    {
        *errcode = EBADF;
        return MP_STREAM_ERROR;
    }
    if (request == MP_STREAM_FLUSH)
        return 0;
    if (request == MP_STREAM_SEEK)
    {
        struct mp_stream_seek_t *seek = (struct mp_stream_seek_t *)arg;
        int64_t offset = qfli_py_seek(fd, seek->offset, seek->whence);
        if (offset >= 0)
        {
            seek->offset = offset;
            return 0;
        }
    }
    *errcode = request == MP_STREAM_SEEK ? errno : EINVAL;
    return MP_STREAM_ERROR;
}

static const mp_rom_map_elem_t file_methods[] = {
    { MP_ROM_QSTR(MP_QSTR_read), MP_ROM_PTR(&mp_stream_read_obj) },
    { MP_ROM_QSTR(MP_QSTR_readinto), MP_ROM_PTR(&mp_stream_readinto_obj) },
    { MP_ROM_QSTR(MP_QSTR_readline), MP_ROM_PTR(&mp_stream_unbuffered_readline_obj) },
    { MP_ROM_QSTR(MP_QSTR_readlines), MP_ROM_PTR(&mp_stream_unbuffered_readlines_obj) },
    { MP_ROM_QSTR(MP_QSTR_write), MP_ROM_PTR(&mp_stream_write_obj) },
    { MP_ROM_QSTR(MP_QSTR_seek), MP_ROM_PTR(&mp_stream_seek_obj) },
    { MP_ROM_QSTR(MP_QSTR_tell), MP_ROM_PTR(&mp_stream_tell_obj) },
    { MP_ROM_QSTR(MP_QSTR_flush), MP_ROM_PTR(&mp_stream_flush_obj) },
    { MP_ROM_QSTR(MP_QSTR_close), MP_ROM_PTR(&mp_stream_close_obj) },
    { MP_ROM_QSTR(MP_QSTR___enter__), MP_ROM_PTR(&mp_identity_obj) },
    { MP_ROM_QSTR(MP_QSTR___exit__), MP_ROM_PTR(&mp_stream___exit___obj) },
};
static MP_DEFINE_CONST_DICT(file_methods_dict, file_methods);

static const mp_stream_p_t binary_stream = {
    .read = file_read, .write = file_write, .ioctl = file_ioctl,
};
static const mp_stream_p_t text_stream = {
    .read = file_read, .write = file_write, .ioctl = file_ioctl, .is_text = true,
};

MP_DEFINE_CONST_OBJ_TYPE(qfli_binary_file_type, MP_QSTR_FileIO,
    MP_TYPE_FLAG_ITER_IS_STREAM, protocol, &binary_stream, locals_dict, &file_methods_dict);
MP_DEFINE_CONST_OBJ_TYPE(qfli_text_file_type, MP_QSTR_TextIOWrapper,
    MP_TYPE_FLAG_ITER_IS_STREAM, protocol, &text_stream, locals_dict, &file_methods_dict);

static int parse_mode(const char *mode, bool *binary, bool *create)
{
    int flags = -1;
    bool plus = false;
    bool text = false;
    *binary = false;
    *create = false;
    for (const char *part = mode; *part != '\0'; ++part)
    {
        switch (*part)
        {
            case 'r': if (flags >= 0) return -1; flags = O_RDONLY; break;
            case 'w': if (flags >= 0) return -1; flags = O_WRONLY | O_CREAT | O_TRUNC; *create = true; break;
            case 'a': if (flags >= 0) return -1; flags = O_WRONLY | O_CREAT | O_APPEND; *create = true; break;
            case 'x': if (flags >= 0) return -1; flags = O_WRONLY | O_CREAT | O_EXCL; *create = true; break;
            case '+': if (plus) return -1; plus = true; break;
            case 'b': if (*binary || text) return -1; *binary = true; break;
            case 't': if (text || *binary) return -1; text = true; break;
            default: return -1;
        }
    }
    if (flags < 0) return -1;
    if (plus) flags = (flags & ~O_ACCMODE) | O_RDWR;
    return flags;
}

static mp_obj_t file_open(size_t n_args, const mp_obj_t *pos_args, mp_map_t *kw_args)
{
    enum { ARG_file, ARG_mode };
    static const mp_arg_t allowed[] = {
        { MP_QSTR_file, MP_ARG_REQUIRED | MP_ARG_OBJ, {.u_obj = MP_OBJ_NULL} },
        { MP_QSTR_mode, MP_ARG_OBJ, {.u_rom_obj = MP_ROM_QSTR(MP_QSTR_r)} },
    };
    mp_arg_val_t args[MP_ARRAY_SIZE(allowed)];
    mp_arg_parse_all(n_args, pos_args, kw_args, MP_ARRAY_SIZE(allowed), allowed, args);

    bool binary, create;
    const char *mode = mp_obj_str_get_str(args[ARG_mode].u_obj);
    int flags = parse_mode(mode, &binary, &create);
    if (flags < 0)
        mp_raise_ValueError(MP_ERROR_TEXT("invalid mode"));
    char path[QFLI_PY_PATH_MAX];
    resolve_path(args[ARG_file].u_obj, create, path);
    int fd = qfli_py_open(path, flags, 0644);
    if (fd < 0)
        mp_raise_OSError(errno);
    int regular = qfli_py_fd_is_regular(fd);
    if (regular < 0)
    {
        int error = errno;
        qfli_py_close(fd);
        mp_raise_OSError(error);
    }
    if (!regular)
    {
        qfli_py_close(fd);
        mp_raise_OSError(EISDIR);
    }

    qfli_py_file_node_t *node = qfli_py_file_track(fd);
    qfli_file_t *file = mp_obj_malloc(qfli_file_t,
        binary ? &qfli_binary_file_type : &qfli_text_file_type);
    file->node = node;
    return MP_OBJ_FROM_PTR(file);
}
MP_DEFINE_CONST_FUN_OBJ_KW(mp_builtin_open_obj, 1, file_open);
