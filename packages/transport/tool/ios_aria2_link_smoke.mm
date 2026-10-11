#include "../ios/Classes/aria2_shim.h"

#include <cstdio>

int main() {
  auto first = transport_aria2_create();
  if (!first) return 2;
  auto second = transport_aria2_create();
  if (!second) return 3;
  transport_aria2_destroy(first);
  transport_aria2_destroy(first);
  transport_aria2_destroy(second);
  std::puts("ios simulator aria2: create/destroy/idempotence passed");
  return 0;
}
