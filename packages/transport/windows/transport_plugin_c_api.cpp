#include "include/transport/transport_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "transport_plugin.h"

void TransportPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  transport::TransportPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
