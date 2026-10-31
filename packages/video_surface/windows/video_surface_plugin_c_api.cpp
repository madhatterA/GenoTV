#include "include/video_surface/video_surface_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "video_surface_plugin.h"

void VideoSurfacePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  video_surface::VideoSurfacePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
