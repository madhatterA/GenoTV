#ifndef CAST_REMUX_WINDOWS_FILES_H
#define CAST_REMUX_WINDOWS_FILES_H
#include <windows.h>
#include <direct.h>
#include <io.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static wchar_t *remux_wide_path(const char *path) {
    if (!path) { errno = EINVAL; return NULL; }
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, NULL, 0);
    if (!count) { errno = EINVAL; return NULL; }
    wchar_t *wide = malloc((size_t)count * sizeof(*wide));
    if (!wide) { errno = ENOMEM; return NULL; }
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wide, count)) {
        free(wide); errno = EINVAL; return NULL;
    }
    return wide;
}

static int remux_windows_open(const char *path, int flags, int mode) {
    wchar_t *wide = remux_wide_path(path);
    if (!wide) return -1;
    int result = _wopen(wide, flags | _O_BINARY, mode);
    free(wide);
    return result;
}

static int remux_windows_path_exists(const char *path) {
    wchar_t *wide = remux_wide_path(path);
    if (!wide) return -1;
    DWORD attributes = GetFileAttributesW(wide);
    DWORD error = GetLastError();
    free(wide);
    if (attributes != INVALID_FILE_ATTRIBUTES) return 0;
    errno = (error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND) ? ENOENT : EACCES;
    return -1;
}

static int remux_windows_mkdir(const char *path) {
    wchar_t *wide = remux_wide_path(path);
    if (!wide) return -1;
    int result = _wmkdir(wide);
    free(wide);
    return result;
}

static int remux_windows_unlink(const char *path) {
    wchar_t *wide = remux_wide_path(path);
    if (!wide) return -1;
    int result = _wunlink(wide);
    free(wide);
    return result;
}

static int remux_windows_regular_file(const char *path) {
    wchar_t *wide = remux_wide_path(path);
    if (!wide) return 0;
    struct _stat64 info;
    int result = _wstat64(wide, &info) == 0 && (info.st_mode & _S_IFMT) == _S_IFREG;
    free(wide);
    return result;
}

static char *remux_windows_strndup(const char *text, size_t length) {
    char *copy = malloc(length + 1);
    if (copy) { memcpy(copy, text, length); copy[length] = 0; }
    return copy;
}

static void remux_windows_remove_hls(const char *directory) {
    wchar_t *wide = remux_wide_path(directory);
    if (!wide) return;
    size_t length = wcslen(wide);
    wchar_t *entry_path = malloc((length + MAX_PATH + 2) * sizeof(*entry_path));
    if (!entry_path) { free(wide); return; }
    memcpy(entry_path, wide, length * sizeof(*wide));
    entry_path[length] = L'\\';
    entry_path[length + 1] = L'*';
    entry_path[length + 2] = 0;
    WIN32_FIND_DATAW entry;
    HANDLE search = FindFirstFileW(entry_path, &entry);
    if (search != INVALID_HANDLE_VALUE) {
        do {
            if (entry.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
            wcscpy(entry_path + length + 1, entry.cFileName);
            _wunlink(entry_path);
        } while (FindNextFileW(search, &entry));
        FindClose(search);
    }
    _wrmdir(wide);
    free(entry_path);
    free(wide);
}

#define open remux_windows_open
#define mkdir(path, mode) remux_windows_mkdir(path)
#define unlink remux_windows_unlink
#define write _write
#define close _close
#define lseek _lseeki64
#define off_t __int64
#define ssize_t int
#define stat _stat64
#define fstat _fstat64
#define strdup _strdup
#define strndup remux_windows_strndup
#endif
