/*
 * Adapted from MicroPython shared/runtime/sys_stdio_mphal.c.
 *
 * The MIT License (MIT)
 *
 * Copyright (c) 2013-2019 Damien P. George
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */
#include "qfli_py_hal.h"

#include "py/mperrno.h"
#include "py/mphal.h"
#include "py/obj.h"
#include "py/stream.h"

enum { STDIO_IN, STDIO_OUT, STDIO_ERR };

typedef struct {
    mp_obj_base_t base;
    int fd;
} qfli_stdio_t;

#if MICROPY_PY_SYS_STDIO_BUFFER
static const qfli_stdio_t stdin_buffer_obj;
static const qfli_stdio_t stdout_buffer_obj;
static const qfli_stdio_t stderr_buffer_obj;
#endif

static void stdio_print(const mp_print_t *print, mp_obj_t self, mp_print_kind_t kind)
{
    qfli_stdio_t *stream = MP_OBJ_TO_PTR(self);
    mp_printf(print, "<io.%s %d>", mp_obj_get_type_str(self), stream->fd);
}

static mp_uint_t stdio_read(mp_obj_t self, void *buf, mp_uint_t size, int *errcode)
{
    qfli_stdio_t *stream = MP_OBJ_TO_PTR(self);
    if (stream->fd != STDIO_IN)
    {
        *errcode = MP_EPERM;
        return MP_STREAM_ERROR;
    }
    mp_uint_t count = 0;
    while (count < size)
    {
        int ch = mp_hal_stdin_rx_chr();
        if (ch < 0)
            break;
        ((byte *)buf)[count++] = (byte)ch;
    }
    return count;
}

static mp_uint_t stdio_write(mp_obj_t self, const void *buf, mp_uint_t size, int *errcode)
{
    qfli_stdio_t *stream = MP_OBJ_TO_PTR(self);
    if (stream->fd == STDIO_IN)
    {
        *errcode = MP_EPERM;
        return MP_STREAM_ERROR;
    }
    qfli_py_hal_write(stream->fd == STDIO_ERR ? QFLI_PY_SINK_STDERR : QFLI_PY_SINK_STDOUT,
        buf, size);
    return size;
}

static mp_uint_t stdio_ioctl(mp_obj_t self, mp_uint_t request, uintptr_t arg, int *errcode)
{
    qfli_stdio_t *stream = MP_OBJ_TO_PTR(self);
    if (request == MP_STREAM_POLL)
    {
        /* Reading the finite buffer never blocks, including at EOF. */
        return arg & (stream->fd == STDIO_IN ? MP_STREAM_POLL_RD : MP_STREAM_POLL_WR);
    }
    if (request == MP_STREAM_CLOSE || request == MP_STREAM_FLUSH)
        return 0;
    *errcode = MP_EINVAL;
    return MP_STREAM_ERROR;
}

static void stdio_attr(mp_obj_t self, qstr attr, mp_obj_t *dest)
{
    if (dest[0] != MP_OBJ_NULL)
        return;
#if MICROPY_PY_SYS_STDIO_BUFFER
    if (attr == MP_QSTR_buffer)
    {
        qfli_stdio_t *stream = MP_OBJ_TO_PTR(self);
        const qfli_stdio_t *buffer = stream->fd == STDIO_IN ? &stdin_buffer_obj :
            stream->fd == STDIO_OUT ? &stdout_buffer_obj : &stderr_buffer_obj;
        dest[0] = MP_OBJ_FROM_PTR(buffer);
        return;
    }
#endif
    dest[1] = MP_OBJ_SENTINEL;
}

static const mp_rom_map_elem_t stdio_methods[] = {
    { MP_ROM_QSTR(MP_QSTR_read), MP_ROM_PTR(&mp_stream_read_obj) },
    { MP_ROM_QSTR(MP_QSTR_readinto), MP_ROM_PTR(&mp_stream_readinto_obj) },
    { MP_ROM_QSTR(MP_QSTR_readline), MP_ROM_PTR(&mp_stream_unbuffered_readline_obj) },
    { MP_ROM_QSTR(MP_QSTR_readlines), MP_ROM_PTR(&mp_stream_unbuffered_readlines_obj) },
    { MP_ROM_QSTR(MP_QSTR_write), MP_ROM_PTR(&mp_stream_write_obj) },
    { MP_ROM_QSTR(MP_QSTR_flush), MP_ROM_PTR(&mp_stream_flush_obj) },
    { MP_ROM_QSTR(MP_QSTR_close), MP_ROM_PTR(&mp_identity_obj) },
    { MP_ROM_QSTR(MP_QSTR___enter__), MP_ROM_PTR(&mp_identity_obj) },
    { MP_ROM_QSTR(MP_QSTR___exit__), MP_ROM_PTR(&mp_stream___exit___obj) },
};
static MP_DEFINE_CONST_DICT(stdio_methods_dict, stdio_methods);

static const mp_stream_p_t text_stream = {
    .read = stdio_read, .write = stdio_write, .ioctl = stdio_ioctl, .is_text = true,
};
MP_DEFINE_CONST_OBJ_TYPE(qfli_stdio_type, MP_QSTR_TextIOWrapper,
    MP_TYPE_FLAG_ITER_IS_STREAM, print, stdio_print, attr, stdio_attr,
    protocol, &text_stream, locals_dict, &stdio_methods_dict);

const qfli_stdio_t mp_sys_stdin_obj = {{&qfli_stdio_type}, STDIO_IN};
const qfli_stdio_t mp_sys_stdout_obj = {{&qfli_stdio_type}, STDIO_OUT};
const qfli_stdio_t mp_sys_stderr_obj = {{&qfli_stdio_type}, STDIO_ERR};

#if MICROPY_PY_SYS_STDIO_BUFFER
static const mp_stream_p_t binary_stream = {
    .read = stdio_read, .write = stdio_write, .ioctl = stdio_ioctl,
};
MP_DEFINE_CONST_OBJ_TYPE(qfli_stdio_buffer_type, MP_QSTR_FileIO,
    MP_TYPE_FLAG_ITER_IS_STREAM, print, stdio_print,
    protocol, &binary_stream, locals_dict, &stdio_methods_dict);
static const qfli_stdio_t stdin_buffer_obj = {{&qfli_stdio_buffer_type}, STDIO_IN};
static const qfli_stdio_t stdout_buffer_obj = {{&qfli_stdio_buffer_type}, STDIO_OUT};
static const qfli_stdio_t stderr_buffer_obj = {{&qfli_stdio_buffer_type}, STDIO_ERR};
#endif
