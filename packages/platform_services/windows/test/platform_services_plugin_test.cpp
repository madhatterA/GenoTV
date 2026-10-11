#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>
#include <windows.h>

#include <memory>
#include <string>
#include <variant>

#include "platform_services_plugin.h"

namespace platform_services {
namespace test {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResultFunctions;

}  // namespace

TEST(PlatformServicesPlugin, VersionIsStructured) {
  PlatformServicesPlugin plugin;
  // Save the reply value from the success callback.
  EncodableMap result_map;
  plugin.HandleMethodCall(
      MethodCall("capabilities.version", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          [&result_map](const EncodableValue* result) {
            result_map = std::get<EncodableMap>(*result);
          },
          nullptr, nullptr));

  EXPECT_TRUE(result_map.contains(EncodableValue("os")));
  EXPECT_TRUE(result_map.contains(EncodableValue("plugin")));
}

}  // namespace test
}  // namespace platform_services
