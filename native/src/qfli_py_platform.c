#if defined(_WIN32) && (!defined(_WIN32_WINNT) || _WIN32_WINNT < 0x0600)
#undef _WIN32_WINNT
#define _WIN32_WINNT 0x0600
#endif
#if defined(_WIN32) && (!defined(WINVER) || WINVER < 0x0600)
#undef WINVER
#define WINVER 0x0600
#endif

#include "qfli_py_platform.h"

#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

#if defined(_WIN32)

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <io.h>
#include <wchar.h>

static SRWLOCK runtime_lock = SRWLOCK_INIT;

void qfli_py_runtime_lock(void) { AcquireSRWLockExclusive(&runtime_lock); }
void qfli_py_runtime_unlock(void) { ReleaseSRWLockExclusive(&runtime_lock); }

static void set_windows_errno(DWORD error)
{
    switch (error)
    {
        case ERROR_FILE_NOT_FOUND:
        case ERROR_PATH_NOT_FOUND:
        case ERROR_INVALID_DRIVE: errno = ENOENT; break;
        case ERROR_ACCESS_DENIED:
        case ERROR_SHARING_VIOLATION:
        case ERROR_LOCK_VIOLATION: errno = EACCES; break;
        case ERROR_FILE_EXISTS:
        case ERROR_ALREADY_EXISTS: errno = EEXIST; break;
        case ERROR_INVALID_HANDLE: errno = EBADF; break;
        case ERROR_DIRECTORY: errno = ENOTDIR; break;
        case ERROR_FILENAME_EXCED_RANGE:
        case ERROR_BUFFER_OVERFLOW: errno = ENAMETOOLONG; break;
        case ERROR_NOT_ENOUGH_MEMORY:
        case ERROR_OUTOFMEMORY: errno = ENOMEM; break;
        case ERROR_WRITE_PROTECT: errno = EROFS; break;
        case ERROR_DISK_FULL:
        case ERROR_HANDLE_DISK_FULL: errno = ENOSPC; break;
        case ERROR_TOO_MANY_OPEN_FILES: errno = EMFILE; break;
        case ERROR_INVALID_NAME:
        case ERROR_INVALID_PARAMETER:
        case ERROR_NO_UNICODE_TRANSLATION: errno = EINVAL; break;
        default: errno = EIO; break;
    }
}

static wchar_t *utf8_to_wide(const char *path)
{
    int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, NULL, 0);
    if (length == 0)
    {
        set_windows_errno(GetLastError());
        return NULL;
    }
    wchar_t *wide = malloc((size_t)length * sizeof(*wide));
    if (wide == NULL)
    {
        errno = ENOMEM;
        return NULL;
    }
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wide, length) == 0)
    {
        DWORD error = GetLastError();
        free(wide);
        set_windows_errno(error);
        return NULL;
    }
    for (wchar_t *part = wide; *part != L'\0'; ++part)
        if (*part == L'/') *part = L'\\';
    return wide;
}

/* Extended absolute paths keep UTF-8 names and long paths independent of the CRT locale. */
static wchar_t *windows_path(const char *path)
{
    wchar_t *wide = utf8_to_wide(path);
    if (wide == NULL) return NULL;
    if (wcsncmp(wide, L"\\\\?\\", 4) == 0) return wide;
    if (wcsncmp(wide, L"\\\\.\\", 4) == 0)
    {
        free(wide);
        errno = EINVAL;
        return NULL;
    }

    DWORD length = GetFullPathNameW(wide, 0, NULL, NULL);
    if (length == 0)
    {
        DWORD error = GetLastError();
        free(wide);
        set_windows_errno(error);
        return NULL;
    }
    wchar_t *full = malloc(((size_t)length + 1) * sizeof(*full));
    if (full == NULL)
    {
        free(wide);
        errno = ENOMEM;
        return NULL;
    }
    DWORD written = GetFullPathNameW(wide, length + 1, full, NULL);
    free(wide);
    if (written == 0 || written > length)
    {
        DWORD error = written == 0 ? GetLastError() : ERROR_FILENAME_EXCED_RANGE;
        free(full);
        set_windows_errno(error);
        return NULL;
    }

    bool unc = full[0] == L'\\' && full[1] == L'\\';
    const wchar_t *prefix = unc ? L"\\\\?\\UNC\\" : L"\\\\?\\";
    const wchar_t *tail = full + (unc ? 2 : 0);
    size_t prefix_length = wcslen(prefix), tail_length = wcslen(tail);
    wchar_t *extended = malloc((prefix_length + tail_length + 1) * sizeof(*extended));
    if (extended == NULL)
    {
        free(full);
        errno = ENOMEM;
        return NULL;
    }
    memcpy(extended, prefix, prefix_length * sizeof(*extended));
    memcpy(extended + prefix_length, tail, (tail_length + 1) * sizeof(*extended));
    free(full);
    return extended;
}

char *qfli_py_realpath(const char *path, char *resolved, size_t capacity)
{
    wchar_t *wide = windows_path(path);
    if (wide == NULL) return NULL;
    HANDLE handle = CreateFileW(wide, FILE_READ_ATTRIBUTES,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
        OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
    free(wide);
    if (handle == INVALID_HANDLE_VALUE)
    {
        set_windows_errno(GetLastError());
        return NULL;
    }

    DWORD length = GetFinalPathNameByHandleW(handle, NULL, 0, FILE_NAME_NORMALIZED);
    if (length == 0)
    {
        DWORD error = GetLastError();
        CloseHandle(handle);
        set_windows_errno(error);
        return NULL;
    }
    wide = malloc(((size_t)length + 1) * sizeof(*wide));
    if (wide == NULL)
    {
        CloseHandle(handle);
        errno = ENOMEM;
        return NULL;
    }
    DWORD written = GetFinalPathNameByHandleW(handle, wide, length + 1, FILE_NAME_NORMALIZED);
    DWORD error = GetLastError();
    CloseHandle(handle);
    if (written == 0 || written > length)
    {
        free(wide);
        set_windows_errno(written == 0 ? error : ERROR_FILENAME_EXCED_RANGE);
        return NULL;
    }

    if (wcsncmp(wide, L"\\\\?\\UNC\\", 8) == 0)
    {
        memmove(wide + 2, wide + 8, (wcslen(wide + 8) + 1) * sizeof(*wide));
        wide[0] = wide[1] = L'\\';
    }
    else if (wcsncmp(wide, L"\\\\?\\", 4) == 0)
        memmove(wide, wide + 4, (wcslen(wide + 4) + 1) * sizeof(*wide));
    for (wchar_t *part = wide; *part != L'\0'; ++part)
        if (*part == L'\\') *part = L'/';

    int bytes = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, -1, NULL, 0, NULL, NULL);
    if (bytes == 0 || (size_t)bytes > capacity)
    {
        error = bytes == 0 ? GetLastError() : ERROR_FILENAME_EXCED_RANGE;
        free(wide);
        set_windows_errno(error);
        return NULL;
    }
    int converted = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, -1,
        resolved, bytes, NULL, NULL);
    error = GetLastError();
    free(wide);
    if (converted == 0)
    {
        set_windows_errno(error);
        return NULL;
    }
    return resolved;
}

bool qfli_py_path_contains(const char *root, const char *path)
{
    wchar_t *wide_root = utf8_to_wide(root), *wide_path = utf8_to_wide(path);
    if (wide_root == NULL || wide_path == NULL)
    {
        free(wide_root);
        free(wide_path);
        return false;
    }
    size_t length = wcslen(wide_root), path_length = wcslen(wide_path);
    bool inside = length != 0 && path_length >= length &&
        CompareStringOrdinal(wide_root, (int)length, wide_path, (int)length, TRUE) == CSTR_EQUAL &&
        (wide_path[length] == L'\\' || wide_path[length] == L'\0' || wide_root[length - 1] == L'\\');
    free(wide_root);
    free(wide_path);
    return inside;
}

bool qfli_py_path_is_absolute(const char *path)
{
    return path[0] == '/' || path[0] == '\\' || (path[0] != '\0' && path[1] == ':');
}

const char *qfli_py_path_last_separator(const char *path)
{
    const char *last = NULL;
    for (; *path != '\0'; ++path)
        if (*path == '/' || *path == '\\') last = path;
    return last;
}

qfli_py_path_type_t qfli_py_path_type(const char *path)
{
    wchar_t *wide = windows_path(path);
    if (wide == NULL) return QFLI_PY_PATH_MISSING;
    DWORD attributes = GetFileAttributesW(wide);
    DWORD error = GetLastError();
    free(wide);
    if (attributes == INVALID_FILE_ATTRIBUTES)
    {
        set_windows_errno(error);
        return QFLI_PY_PATH_MISSING;
    }
    return (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0
        ? QFLI_PY_PATH_DIRECTORY : QFLI_PY_PATH_FILE;
}

int qfli_py_open(const char *path, int flags, int mode)
{
    wchar_t *wide = windows_path(path);
    if (wide == NULL) return -1;
    DWORD attributes = GetFileAttributesW(wide);
    if (attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0)
    {
        free(wide);
        errno = EISDIR;
        return -1;
    }
    int permissions = _S_IREAD | ((mode & 0222) != 0 ? _S_IWRITE : 0);
    int fd = _wopen(wide, flags | _O_BINARY | _O_NOINHERIT, permissions);
    free(wide);
    return fd;
}

int qfli_py_close(int fd) { return _close(fd); }
intptr_t qfli_py_read(int fd, void *buffer, size_t size)
{
    return _read(fd, buffer, (unsigned int)(size > INT_MAX ? INT_MAX : size));
}
intptr_t qfli_py_write(int fd, const void *buffer, size_t size)
{
    return _write(fd, buffer, (unsigned int)(size > INT_MAX ? INT_MAX : size));
}
int64_t qfli_py_seek(int fd, int64_t offset, int whence) { return _lseeki64(fd, offset, whence); }
int qfli_py_fd_is_regular(int fd)
{
    struct _stat64 info;
    if (_fstat64(fd, &info) != 0) return -1;
    return (info.st_mode & _S_IFMT) == _S_IFREG;
}

uint64_t qfli_py_monotonic_ns(void)
{
    LARGE_INTEGER frequency, counter;
    if (!QueryPerformanceFrequency(&frequency) || !QueryPerformanceCounter(&counter))
        return (uint64_t)GetTickCount64() * 1000000u;
    return (uint64_t)(counter.QuadPart / frequency.QuadPart) * 1000000000u +
        (uint64_t)(counter.QuadPart % frequency.QuadPart) * 1000000000u / (uint64_t)frequency.QuadPart;
}

uint64_t qfli_py_realtime_ns(void)
{
    FILETIME time;
    ULARGE_INTEGER ticks;
    GetSystemTimeAsFileTime(&time);
    ticks.LowPart = time.dwLowDateTime;
    ticks.HighPart = time.dwHighDateTime;
    return (ticks.QuadPart - 116444736000000000ull) * 100u;
}

void qfli_py_sleep_us(uint64_t us)
{
    if (us == 0)
    {
        Sleep(0);
        return;
    }
    if (us <= (uint64_t)INT64_MAX / 10)
    {
        HANDLE timer = CreateWaitableTimerW(NULL, TRUE, NULL);
        if (timer != NULL)
        {
            LARGE_INTEGER due;
            due.QuadPart = -(LONGLONG)(us * 10);
            if (SetWaitableTimer(timer, &due, 0, NULL, NULL, FALSE))
            {
                DWORD waited = WaitForSingleObject(timer, INFINITE);
                CloseHandle(timer);
                if (waited == WAIT_OBJECT_0) return;
            }
            else CloseHandle(timer);
        }
    }
    uint64_t ms = us / 1000u + (us % 1000u != 0);
    while (ms != 0)
    {
        DWORD chunk = ms >= MAXDWORD ? MAXDWORD - 1 : (DWORD)ms;
        Sleep(chunk);
        ms -= chunk;
    }
}

#else

#include <pthread.h>
#include <unistd.h>

static pthread_mutex_t runtime_lock = PTHREAD_MUTEX_INITIALIZER;

void qfli_py_runtime_lock(void) { pthread_mutex_lock(&runtime_lock); }
void qfli_py_runtime_unlock(void) { pthread_mutex_unlock(&runtime_lock); }

char *qfli_py_realpath(const char *path, char *resolved, size_t capacity)
{
    char *canonical = realpath(path, NULL);
    if (canonical == NULL) return NULL;
    size_t length = strlen(canonical) + 1;
    if (length > capacity)
    {
        free(canonical);
        errno = ENAMETOOLONG;
        return NULL;
    }
    memcpy(resolved, canonical, length);
    free(canonical);
    return resolved;
}

bool qfli_py_path_contains(const char *root, const char *path)
{
    size_t length = strlen(root);
    return length != 0 && strncmp(path, root, length) == 0 &&
        (path[length] == '/' || path[length] == '\0' || (length == 1 && root[0] == '/'));
}

bool qfli_py_path_is_absolute(const char *path) { return path[0] == '/'; }
const char *qfli_py_path_last_separator(const char *path) { return strrchr(path, '/'); }
qfli_py_path_type_t qfli_py_path_type(const char *path)
{
    struct stat info;
    if (stat(path, &info) != 0) return QFLI_PY_PATH_MISSING;
    if (S_ISDIR(info.st_mode)) return QFLI_PY_PATH_DIRECTORY;
    if (S_ISREG(info.st_mode)) return QFLI_PY_PATH_FILE;
    return QFLI_PY_PATH_OTHER;
}

int qfli_py_open(const char *path, int flags, int mode) { return open(path, flags | O_CLOEXEC | O_NOFOLLOW, mode); }
int qfli_py_close(int fd) { return close(fd); }
intptr_t qfli_py_read(int fd, void *buffer, size_t size) { return read(fd, buffer, size); }
intptr_t qfli_py_write(int fd, const void *buffer, size_t size) { return write(fd, buffer, size); }
int64_t qfli_py_seek(int fd, int64_t offset, int whence) { return lseek(fd, (off_t)offset, whence); }
int qfli_py_fd_is_regular(int fd)
{
    struct stat info;
    if (fstat(fd, &info) != 0) return -1;
    return S_ISREG(info.st_mode);
}

uint64_t qfli_py_monotonic_ns(void)
{
    struct timespec ts = {0, 0};
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}
uint64_t qfli_py_realtime_ns(void)
{
    struct timespec ts = {0, 0};
    clock_gettime(CLOCK_REALTIME, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}
void qfli_py_sleep_us(uint64_t us)
{
    struct timespec ts;
    ts.tv_sec = (time_t)(us / 1000000u);
    ts.tv_nsec = (long)((us % 1000000u) * 1000u);
    while (nanosleep(&ts, &ts) != 0 && errno == EINTR) { }
}

#endif
