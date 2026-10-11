#include "../src/lt_shim/lt_shim.h"

#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

typedef transport_lt_session (*session_create_fn)(void);
typedef void (*session_destroy_fn)(transport_lt_session);
typedef int32_t (*session_error_fn)(transport_lt_session, char *, int32_t);
typedef transport_lt_torrent (*add_magnet_fn)(transport_lt_session, const char *, int32_t, const char *, int32_t);
typedef void (*torrent_close_fn)(transport_lt_torrent);
typedef int32_t (*close_complete_fn)(transport_lt_torrent);
typedef int32_t (*metadata_ready_fn)(transport_lt_torrent);
typedef int32_t (*piece_length_fn)(transport_lt_torrent);
typedef int32_t (*file_info_fn)(transport_lt_torrent, int32_t, transport_lt_file_info *, char *, int32_t);
typedef int32_t (*piece_available_fn)(transport_lt_torrent, int32_t);
typedef int32_t (*read_fn)(transport_lt_torrent, int32_t, int64_t, uint8_t *, int32_t);
typedef int32_t (*deadline_fn)(transport_lt_torrent, int32_t, int32_t);
typedef int32_t (*pop_alerts_fn)(transport_lt_session, transport_lt_alert *, int32_t, char *, int32_t);

static void *load(void *handle, const char *name) {
  void *symbol = dlsym(handle, name);
  if (!symbol) {
    fprintf(stderr, "missing symbol: %s\n", name);
    exit(3);
  }
  return symbol;
}

static int wait_piece(piece_available_fn available, pop_alerts_fn pop, transport_lt_torrent torrent,
    transport_lt_session session, int piece) {
  transport_lt_alert alerts[256];
  char messages[16384];
  for (int i = 0; i < 600; ++i) {
    if (available(torrent, piece) == 1) return 0;
    pop(session, alerts, 256, messages, sizeof(messages));
    usleep(100000);
  }
  return 1;
}

static int expect_pattern(const uint8_t *bytes, int32_t length, int64_t offset) {
  if (length != 4096) return 1;
  for (int32_t i = 0; i < length; ++i) {
    if (bytes[i] != (uint8_t)((offset + i) % 251)) return 1;
  }
  return 0;
}

int main(int argc, char **argv) {
  if (argc != 4) {
    fprintf(stderr, "usage: %s <bundle-shim.dylib> <magnet> <save-path>\n", argv[0]);
    return 2;
  }
  void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!library) {
    fprintf(stderr, "dlopen failed: %s\n", dlerror());
    return 3;
  }
  session_create_fn create = load(library, "transport_lt_session_create");
  session_destroy_fn destroy = load(library, "transport_lt_session_destroy");
  session_error_fn last_error = load(library, "transport_lt_session_last_error");
  add_magnet_fn add_magnet = load(library, "transport_lt_add_magnet");
  torrent_close_fn close_torrent = load(library, "transport_lt_torrent_close");
  close_complete_fn close_complete = load(library, "transport_lt_torrent_close_complete");
  metadata_ready_fn metadata_ready = load(library, "transport_lt_torrent_metadata_ready");
  piece_length_fn piece_length = load(library, "transport_lt_torrent_piece_length");
  file_info_fn file_info = load(library, "transport_lt_torrent_file_info");
  piece_available_fn piece_available = load(library, "transport_lt_torrent_piece_available");
  read_fn read_bytes = load(library, "transport_lt_torrent_read");
  deadline_fn set_deadline = load(library, "transport_lt_torrent_set_piece_deadline");
  pop_alerts_fn pop_alerts = load(library, "transport_lt_pop_alerts");

  Dl_info image = {0};
  if (dladdr((void *)create, &image) == 0 || !image.dli_fname || strstr(image.dli_fname, ".app/Contents/Frameworks/") == NULL) {
    fprintf(stderr, "loaded image is outside app Frameworks: %s\n", image.dli_fname ? image.dli_fname : "<unknown>");
    return 4;
  }
  printf("LOADED_IMAGE=%s\n", image.dli_fname);

  transport_lt_session session = create();
  if (!session) return 5;
  transport_lt_torrent invalid = add_magnet(session, "invalid", 7, argv[3], (int32_t)strlen(argv[3]));
  if (invalid) return 6;
  char error[1024] = {0};
  int32_t error_length = last_error(session, error, sizeof(error));
  printf("ERROR_MAPPING=typed length=%d text=%.*s\n", error_length, error_length, error);

  transport_lt_torrent torrent = add_magnet(session, argv[2], (int32_t)strlen(argv[2]), argv[3], (int32_t)strlen(argv[3]));
  if (!torrent) return 7;
  for (int i = 0; i < 600 && metadata_ready(torrent) == 0; ++i) {
    transport_lt_alert alerts[256];
    char messages[16384];
    pop_alerts(session, alerts, 256, messages, sizeof(messages));
    usleep(100000);
  }
  if (!metadata_ready(torrent)) return 8;
  printf("METADATA=ready\n");
  transport_lt_file_info info = {0};
  char path[1024] = {0};
  if (file_info(torrent, 0, &info, path, sizeof(path)) < 0) return 9;
  int32_t length = piece_length(torrent);
  if (length <= 0 || wait_piece(piece_available, pop_alerts, torrent, session, 0) != 0) return 10;
  uint8_t bytes[4096];
  int32_t read_length = read_bytes(torrent, 0, 0, bytes, sizeof(bytes));
  if (expect_pattern(bytes, read_length, 0) != 0) return 11;
  printf("READ=offset=0 bytes=%d path=%s\n", read_length, path);

  const int64_t seek_offset = 24LL * 1024 * 1024;
  const int seek_piece = (int)(seek_offset / length);
  if (set_deadline(torrent, seek_piece, 0) != 0 || wait_piece(piece_available, pop_alerts, torrent, session, seek_piece) != 0) return 12;
  read_length = read_bytes(torrent, 0, seek_offset, bytes, sizeof(bytes));
  if (expect_pattern(bytes, read_length, seek_offset) != 0) return 13;
  printf("SEEK_READ=offset=%lld piece=%d bytes=%d\n", seek_offset, seek_piece, read_length);

  close_torrent(torrent);
  for (int i = 0; i < 600 && close_complete(torrent) == 0; ++i) usleep(10000);
  printf("DISPOSE=close_complete=%d\n", close_complete(torrent));
  destroy(session);
  dlclose(library);
  printf("LIFECYCLE=destroyed\n");
  return 0;
}
