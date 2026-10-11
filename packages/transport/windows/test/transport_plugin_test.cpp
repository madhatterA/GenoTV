#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>
#include <memory>

#include "transport_plugin.h"

namespace transport {
namespace test {

namespace {

}  // namespace

TEST(TransportPlugin, Constructs) {
  TransportPlugin plugin;
  SUCCEED();
}

}  // namespace test
}  // namespace transport
