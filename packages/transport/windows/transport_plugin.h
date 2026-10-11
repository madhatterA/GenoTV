#ifndef FLUTTER_PLUGIN_TRANSPORT_PLUGIN_H_
#define FLUTTER_PLUGIN_TRANSPORT_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace transport {

class TransportPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  TransportPlugin();

  virtual ~TransportPlugin();

  // Disallow copy and assign.
  TransportPlugin(const TransportPlugin&) = delete;
  TransportPlugin& operator=(const TransportPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace transport

#endif  // FLUTTER_PLUGIN_TRANSPORT_PLUGIN_H_
