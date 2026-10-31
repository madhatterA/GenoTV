#ifndef FLUTTER_PLUGIN_VIDEO_SURFACE_PLUGIN_H_
#define FLUTTER_PLUGIN_VIDEO_SURFACE_PLUGIN_H_

#include <windows.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <map>
#include <optional>
#include <memory>

namespace video_surface {

// One child HWND per media_kit Player; mpv (vo=gpu-next, d3d11) renders into it.
struct Instance {
  HWND hwnd = nullptr;
  void* mpv = nullptr;
  bool hdr_source = false;
  bool hdr_display = false;
  bool pq_output = false;  // libmpv can drive a PQ swapchain (libplacebo + d3d11)
  double headroom = 1.0;
  int req[4] = {0, 0, 0, 0};  // last rect Dart asked for (x, y, w, h)
};

class VideoSurfacePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit VideoSurfacePlugin(flutter::PluginRegistrarWindows* registrar);
  ~VideoSurfacePlugin() override;

 private:
  using Result = flutter::MethodResult<flutter::EncodableValue>;
  void Handle(const flutter::MethodCall<flutter::EncodableValue>& call,
              std::unique_ptr<Result> result);
  void RefreshScreens();
  flutter::EncodableMap Screen(int id, Instance& inst);

  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::map<int, Instance> instances_;
  int next_id_ = 1;
  int delegate_id_ = -1;
};

}  // namespace video_surface

#endif
