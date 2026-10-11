#include "include/playback/playback_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "playback_plugin.h"

void PlaybackPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  playback::PlaybackPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
