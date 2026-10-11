#include "lt_shim.h"

#include <stdio.h>
#include <string.h>
#include <sys/resource.h>
#include <unistd.h>

static long rss(void) {
  struct rusage usage;
  return getrusage(RUSAGE_SELF, &usage) == 0 ? usage.ru_maxrss : -1;
}

int main(int argc, char **argv) {
  if (argc != 3) {
    fprintf(stderr, "usage: %s <magnet> <save-path>\n", argv[0]);
    return 2;
  }
  for (int i = 0; i < 20; ++i) {
    transport_lt_session warmup = transport_lt_session_create();
    if (!warmup) return 3;
    transport_lt_session_destroy(warmup);
  }
  const long before = rss();
  for (int i = 0; i < 20; ++i) {
    transport_lt_session session = transport_lt_session_create();
    if (!session) return 3;
    transport_lt_session_destroy(session);
  }
  printf("create_destroy_20 rss_before=%ld rss_after=%ld\n", before, rss());

  transport_lt_session session = transport_lt_session_create();
  transport_lt_torrent invalid = transport_lt_add_magnet(
      session, "invalid", 7, argv[2], (int32_t)strlen(argv[2]), 0);
  printf("invalid_magnet result=%s\n", invalid ? "unexpected-handle" : "typed-error");
  if (invalid) return 4;

  transport_lt_torrent torrent = transport_lt_add_magnet(
      session, argv[1], (int32_t)strlen(argv[1]), argv[2], (int32_t)strlen(argv[2]), 0);
  if (!torrent) return 5;
  char hash[41] = {0};
  if (transport_lt_torrent_info_hash(torrent, hash, sizeof(hash)) != 40) return 6;
  printf("info_hash=%s\n", hash);
  for (int i = 0; i < 600 && transport_lt_torrent_metadata_ready(torrent) == 0; ++i) {
    transport_lt_alert alerts[64];
    char messages[4096];
    transport_lt_pop_alerts(session, alerts, 64, messages, sizeof(messages));
    usleep(100000);
  }
  if (transport_lt_torrent_metadata_ready(torrent) != 1) return 7;
  transport_lt_file_info info;
  const int32_t caught = transport_lt_torrent_file_info(torrent, 2147483647, &info, 0, 0);
  printf("forced_cpp_exception result=%d process_alive=yes\n", caught);
  if (caught != -1) return 8;
  transport_lt_session_destroy(session);
  return 0;
}
