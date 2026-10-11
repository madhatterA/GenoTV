// File-system helpers for cache eviction: free disk blocks inside a file
// (punch_hole) and measure the blocks a file really occupies (allocated_bytes).
// One branch per OS. Only macOS is built and proved; the Linux/Android and
// Windows branches follow the vendor docs (fallocate(2) FALLOC_FL_PUNCH_HOLE,
// FSCTL_SET_ZERO_DATA / FSCTL_QUERY_ALLOCATED_RANGES) and compile in Part 07.
#define _GNU_SOURCE
#include "lt_shim.h"

#if defined(_WIN32)
#include <windows.h>
#include <winioctl.h>
#include <wchar.h>

static HANDLE open_path(const char* path, int32_t len, DWORD access) {
  wchar_t wide[4096];
  int n = MultiByteToWideChar(CP_UTF8, 0, path, len, wide, 4095);
  if (n <= 0) return INVALID_HANDLE_VALUE;
  wide[n] = 0;
  return CreateFileW(wide, access, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                     NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
}

int32_t transport_lt_fs_punch_hole(const char* path, int32_t path_len, int64_t offset, int64_t length) {
  if (!path || offset < 0 || length <= 0) return -1;
  HANDLE h = open_path(path, path_len, GENERIC_READ | GENERIC_WRITE);
  if (h == INVALID_HANDLE_VALUE) return -2;
  DWORD ret = 0;
  int32_t rc = 0;
  if (!DeviceIoControl(h, FSCTL_SET_SPARSE, NULL, 0, NULL, 0, &ret, NULL)) rc = -3;
  FILE_ZERO_DATA_INFORMATION zero;
  zero.FileOffset.QuadPart = offset;
  zero.BeyondFinalZero.QuadPart = offset + length;
  if (rc == 0 && !DeviceIoControl(h, FSCTL_SET_ZERO_DATA, &zero, sizeof zero, NULL, 0, &ret, NULL)) rc = -4;
  CloseHandle(h);
  return rc;
}

int64_t transport_lt_fs_allocated_bytes(const char* path, int32_t path_len, int64_t offset, int64_t length) {
  if (!path || offset < 0) return -1;
  HANDLE h = open_path(path, path_len, GENERIC_READ);
  if (h == INVALID_HANDLE_VALUE) return -2;
  LARGE_INTEGER size;
  if (!GetFileSizeEx(h, &size)) { CloseHandle(h); return -3; }
  int64_t end = length < 0 || offset + length > size.QuadPart ? size.QuadPart : offset + length;
  int64_t total = 0;
  while (offset < end) {
    FILE_ALLOCATED_RANGE_BUFFER query, out[64];
    query.FileOffset.QuadPart = offset;
    query.Length.QuadPart = end - offset;
    DWORD bytes = 0;
    BOOL ok = DeviceIoControl(h, FSCTL_QUERY_ALLOCATED_RANGES, &query, sizeof query, out, sizeof out, &bytes, NULL);
    if (!ok && GetLastError() != ERROR_MORE_DATA) { CloseHandle(h); return -4; }
    DWORD count = bytes / sizeof out[0];
    if (count == 0) break;
    for (DWORD i = 0; i < count; i++) total += out[i].Length.QuadPart;
    offset = out[count - 1].FileOffset.QuadPart + out[count - 1].Length.QuadPart;
  }
  CloseHandle(h);
  return total;
}

int64_t transport_lt_fs_free_bytes(const char* path, int32_t path_len) {
  if (!path) return -1;
  wchar_t wide[4096];
  int n = MultiByteToWideChar(CP_UTF8, 0, path, path_len, wide, 4095);
  if (n <= 0) return -2;
  wide[n] = 0;
  ULARGE_INTEGER available;
  if (!GetDiskFreeSpaceExW(wide, &available, NULL, NULL)) return -3;
  return (int64_t)available.QuadPart;
}

#else
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <sys/statvfs.h>
#if defined(__APPLE__)
#include <sys/mount.h>
#endif

static int open_path(const char* path, int32_t len, int flags) {
  char buffer[4096];
  if (len <= 0 || len >= (int32_t)sizeof buffer) return -1;
  memcpy(buffer, path, (size_t)len);
  buffer[len] = 0;
  return open(buffer, flags);
}

int32_t transport_lt_fs_punch_hole(const char* path, int32_t path_len, int64_t offset, int64_t length) {
  if (!path || offset < 0 || length <= 0) return -1;
  int fd = open_path(path, path_len, O_RDWR);
  if (fd < 0) return -2;
  int32_t rc = 0;
#if defined(__APPLE__)
  struct statfs fs;
  int64_t block = fstatfs(fd, &fs) == 0 && fs.f_bsize > 0 ? fs.f_bsize : 4096;
  // F_PUNCHHOLE needs block-aligned ranges: shrink inward, never punch live bytes.
  int64_t start = (offset + block - 1) / block * block;
  int64_t end = (offset + length) / block * block;
  if (end > start) {
    struct fpunchhole hole;
    memset(&hole, 0, sizeof hole);
    hole.fp_offset = start;
    hole.fp_length = end - start;
    if (fcntl(fd, F_PUNCHHOLE, &hole) != 0) rc = -3;
  }
#else
  struct stat st;
  int64_t block = fstat(fd, &st) == 0 && st.st_blksize > 0 ? st.st_blksize : 4096;
  int64_t start = (offset + block - 1) / block * block;
  int64_t end = (offset + length) / block * block;
  if (end > start && fallocate(fd, FALLOC_FL_PUNCH_HOLE | FALLOC_FL_KEEP_SIZE, start, end - start) != 0) rc = -3;
#endif
  close(fd);
  return rc;
}

int64_t transport_lt_fs_allocated_bytes(const char* path, int32_t path_len, int64_t offset, int64_t length) {
  if (!path || offset < 0) return -1;
  int fd = open_path(path, path_len, O_RDONLY);
  if (fd < 0) return -2;
  struct stat st;
  if (fstat(fd, &st) != 0) { close(fd); return -3; }
  int64_t end = length < 0 || offset + length > st.st_size ? st.st_size : offset + length;
  int64_t total = 0;
  int64_t pos = offset;
  while (pos < end) {
    off_t data = lseek(fd, (off_t)pos, SEEK_DATA);
    if (data < 0 || data >= end) break;  // ENXIO: only a hole remains
    off_t hole = lseek(fd, data, SEEK_HOLE);
    if (hole < 0 || hole > end) hole = (off_t)end;
    total += hole - data;
    pos = hole;
  }
  close(fd);
  return total;
}

int64_t transport_lt_fs_free_bytes(const char* path, int32_t path_len) {
  char buffer[4096];
  if (!path || path_len <= 0 || path_len >= (int32_t)sizeof buffer) return -1;
  memcpy(buffer, path, (size_t)path_len);
  buffer[path_len] = 0;
  struct statvfs fs;
  if (statvfs(buffer, &fs) != 0) return -2;
  return (int64_t)fs.f_bavail * (int64_t)fs.f_frsize;
}
#endif
