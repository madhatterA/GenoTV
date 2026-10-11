#include "include/platform_services/platform_services_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "platform_services_plugin.h"

void PlatformServicesPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  platform_services::PlatformServicesPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
