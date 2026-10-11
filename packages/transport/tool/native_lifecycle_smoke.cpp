#include "../src/lt_shim/lt_shim.h"

#include <cstdio>

int main() {
  for (int i = 0; i < 100; ++i) {
    auto session = transport_lt_session_create();
    if (!session) return 2;
    auto torrent = transport_lt_add_magnet(
      session, "not-a-magnet", 12, "/data/local/tmp/transport-native", 31, 0);
    if (torrent) return 3;
    transport_lt_session_destroy(session);
    transport_lt_session_destroy(session);
  }
  std::puts("android native lifecycle: 100 create/destroy + duplicate destroy cycles passed");
  return 0;
}
