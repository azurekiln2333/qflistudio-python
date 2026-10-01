#ifndef QFLI_PY_PLATFORM_H
#define QFLI_PY_PLATFORM_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <fcntl.h>

#define QFLI_PY_PATH_MAX 4096

#ifndef O_ACCMODE
#define O_ACCMODE (O_RDONLY | O_WRONLY | O_RDWR)
#endif

typedef enum {
    QFLI_PY_PATH_MISSING,
    QFLI_PY_PATH_FILE,
    QFLI_PY_PATH_DIRECTORY,
    QFLI_PY_PATH_OTHER,
} qfli_py_path_type_t;

void qfli_py_runtime_lock(void);
void qfli_py_runtime_unlock(void);
uint64_t qfli_py_monotonic_ns(void);
uint64_t qfli_py_realtime_ns(void);
void qfli_py_sleep_us(uint64_t us);

char *qfli_py_realpath(const char *path, char *resolved, size_t capacity);
bool qfli_py_path_contains(const char *root, const char *path);
bool qfli_py_path_is_absolute(const char *path);
const char *qfli_py_path_last_separator(const char *path);
qfli_py_path_type_t qfli_py_path_type(const char *path);

int qfli_py_open(const char *path, int flags, int mode);
int qfli_py_close(int fd);
intptr_t qfli_py_read(int fd, void *buffer, size_t size);
intptr_t qfli_py_write(int fd, const void *buffer, size_t size);
int64_t qfli_py_seek(int fd, int64_t offset, int whence);
int qfli_py_fd_is_regular(int fd);

#endif
