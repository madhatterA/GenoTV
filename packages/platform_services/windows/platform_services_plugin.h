#ifndef FLUTTER_PLUGIN_PLATFORM_SERVICES_PLUGIN_H_
#define FLUTTER_PLUGIN_PLATFORM_SERVICES_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>

#include <flutter/event_sink.h>

#include <memory>
#include <string>
#include <vector>

#include "windows_audio.h"
#include "windows_media_session.h"

namespace platform_services {

class PlatformServicesPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  PlatformServicesPlugin();

  virtual ~PlatformServicesPlugin();

  // Disallow copy and assign.
  PlatformServicesPlugin(const PlatformServicesPlugin&) = delete;
  PlatformServicesPlugin& operator=(const PlatformServicesPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void SetView(flutter::FlutterView* view);
  void SetEventSink(std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink);
  // Platform thread only: invalidates the endpoint cache and notifies Dart.
  void OnAudioRouteChanged();
  // Platform thread only: WM_DISPLAYCHANGE (monitor hot-plug, mode change).
  void OnDisplayChanged();
  // Platform thread only: drains SMTC / media-key commands to Dart.
  void OnMediaCommands();
  void SetRegistrar(flutter::PluginRegistrarWindows* registrar);

 private:
  flutter::EncodableMap EnumerateDisplayModes() const;
  flutter::EncodableMap ApplyDisplayMode(const flutter::EncodableValue* arguments);
  flutter::EncodableMap RestoreDisplayMode();
  flutter::EncodableMap SetFullscreen(const flutter::EncodableValue* arguments);
  flutter::EncodableMap DisplayScreens(const flutter::EncodableValue* select);
  const wchar_t* Device() const { return selected_device_.empty() ? nullptr : selected_device_.c_str(); }
  const std::vector<audio::Endpoint>& Endpoints();
  flutter::EncodableMap AudioDevices(const flutter::EncodableValue* arguments);
  flutter::EncodableMap NegotiateAudio(const flutter::EncodableValue* arguments);
  flutter::EncodableMap ProbeMedia(const flutter::EncodableValue* arguments) const;
  void RestorePendingDisplayMode();
  flutter::EncodableMap UpdateMediaSession(const flutter::EncodableValue* arguments);
  flutter::EncodableMap ClearMediaSession();
  void EmitMediaCommand(const media::Command& command);

  DEVMODEW previous_display_mode_{};
  bool has_previous_display_mode_ = false;
  std::wstring previous_device_;
  std::wstring selected_device_;  // empty = primary (Kodi "Default")
  std::string selected_monitor_;
  flutter::FlutterView* view_ = nullptr;
  bool fullscreen_ = false;
  LONG windowed_style_ = 0;
  WINDOWPLACEMENT windowed_placement_{};
  flutter::PluginRegistrarWindows* registrar_ = nullptr;
  int display_proc_id_ = 0;
  std::unique_ptr<media::Session> media_;
  bool keep_awake_ = false;
  std::vector<audio::Endpoint> endpoints_;
  std::vector<std::string> audio_log_;
  std::string audio_error_;
  bool endpoints_valid_ = false;
  HWND window_ = nullptr;
  std::unique_ptr<audio::RouteWatcher> watcher_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;
};

}  // namespace platform_services

#endif  // FLUTTER_PLUGIN_PLATFORM_SERVICES_PLUGIN_H_
