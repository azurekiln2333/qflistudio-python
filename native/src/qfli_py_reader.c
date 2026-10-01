#include "py/mpconfig.h"

#if defined(_WIN32)

#include "qfli_py_file.h"
#include "qfli_py_platform.h"
#include "py/lexer.h"
#include "py/reader.h"
#include "py/runtime.h"

#include <errno.h>

typedef struct {
    qfli_py_file_node_t *node;
    int fd;
    size_t length;
    size_t position;
    byte buffer[128];
} qfli_py_reader_t;

static mp_uint_t reader_readbyte(void *data)
{
    qfli_py_reader_t *reader = data;
    if (reader->position == reader->length)
    {
        intptr_t count;
        do { count = qfli_py_read(reader->fd, reader->buffer, sizeof(reader->buffer)); }
        while (count < 0 && errno == EINTR);
        if (count < 0)
        {
            int error = errno;
            qfli_py_file_close(reader->node);
            mp_raise_OSError(error);
        }
        if (count == 0) return MP_READER_EOF;
        reader->length = (size_t)count;
        reader->position = 0;
    }
    return reader->buffer[reader->position++];
}

static void reader_close(void *data)
{
    qfli_py_reader_t *reader = data;
    qfli_py_file_close(reader->node);
    m_del_obj(qfli_py_reader_t, reader);
}

void mp_reader_new_file_from_fd(mp_reader_t *reader, int fd, bool close_fd)
{
    /* Track before GC allocation: even an allocation exception must close the descriptor. */
    qfli_py_file_node_t *node = close_fd ? qfli_py_file_track(fd) : NULL;
    qfli_py_reader_t *state = m_new_obj(qfli_py_reader_t);
    state->node = node;
    state->fd = fd;
    state->length = 0;
    state->position = 0;
    reader->data = state;
    reader->readbyte = reader_readbyte;
    reader->close = reader_close;
}

void mp_reader_new_file(mp_reader_t *reader, qstr filename)
{
    int fd = qfli_py_open(qstr_str(filename), O_RDONLY, 0644);
    if (fd < 0) mp_raise_OSError_with_filename(errno, qstr_str(filename));
    mp_reader_new_file_from_fd(reader, fd, true);
}

mp_lexer_t *mp_lexer_new_from_file(qstr filename)
{
    mp_reader_t reader;
    mp_reader_new_file(&reader, filename);
    return mp_lexer_new(filename, reader);
}

#endif
