#ifndef FLUTTER_PLUGIN_PLAYBACK_PLUGIN_H_
#define FLUTTER_PLUGIN_PLAYBACK_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace playback {

class PlaybackPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  PlaybackPlugin();

  virtual ~PlaybackPlugin();

  // Disallow copy and assign.
  PlaybackPlugin(const PlaybackPlugin&) = delete;
  PlaybackPlugin& operator=(const PlaybackPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace playback

#endif  // FLUTTER_PLUGIN_PLAYBACK_PLUGIN_H_
