#include "../src/lt_shim/lt_shim.h"

int main() {
  transport_lt_session session = transport_lt_session_create();
  if (session == nullptr) return 2;
  transport_lt_session_destroy(session);
  transport_lt_session_destroy(session);
  return 0;
}
