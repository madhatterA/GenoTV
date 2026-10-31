//
//  Generated file. Do not edit.
//

import Flutter
import Foundation

import cast
import media_kit_libs_tvos_video
import media_kit_video
import package_info_plus_tvos
import path_provider_tvos
import platform_services
import playback
import transport
import video_surface
import wakelock_plus_tvos

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  // The registry returns nil registrars when the Flutter engine is not
  // running (on a physical Apple TV the debug engine requires an attached
  // debugger). Nil crashes plugin registration, so bail out loudly.
  guard registry.registrar(forPlugin: "__flutter_tvos_engine_probe__") != nil else {
    NSLog("[GeneratedPluginRegistrant] Flutter engine is not running; skipping plugin registration. Debug builds on a physical Apple TV must be launched via 'flutter-tvos run' (the debug engine requires an attached debugger).")
    return
  }
  CastPlugin.register(with: registry.registrar(forPlugin: "CastPlugin"))
  MediaKitLibsTvosVideoPlugin.register(with: registry.registrar(forPlugin: "MediaKitLibsTvosVideoPlugin"))
  MediaKitVideoPlugin.register(with: registry.registrar(forPlugin: "MediaKitVideoPlugin"))
  FPPPackageInfoPlusPlugin.register(with: registry.registrar(forPlugin: "FPPPackageInfoPlusPlugin"))
  PathProviderPlugin.register(with: registry.registrar(forPlugin: "PathProviderPlugin"))
  PlatformServicesPlugin.register(with: registry.registrar(forPlugin: "PlatformServicesPlugin"))
  PlaybackPlugin.register(with: registry.registrar(forPlugin: "PlaybackPlugin"))
  TransportPlugin.register(with: registry.registrar(forPlugin: "TransportPlugin"))
  VideoSurfacePlugin.register(with: registry.registrar(forPlugin: "VideoSurfacePlugin"))
  WakelockPlusPlugin.register(with: registry.registrar(forPlugin: "WakelockPlusPlugin"))
}
