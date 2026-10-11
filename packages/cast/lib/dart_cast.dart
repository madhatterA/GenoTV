/// A Dart package for casting media to Chromecast and DLNA devices.
library;

export 'src/remux/remuxer.dart';
export 'src/transform/audio_capability.dart';
export 'src/transform/media_transformer.dart';
export 'src/transform/device_media_transformer.dart';

// Core
export 'src/core/cast_device.dart';
export 'src/core/cast_exceptions.dart';
export 'src/core/cast_media.dart';
export 'src/core/cast_service.dart';
export 'src/core/cast_session.dart';
export 'src/core/discovery_manager.dart';
export 'src/core/media_transformer.dart';
export 'src/core/ts_hls_media_transformer.dart';
export 'src/core/discovery_provider.dart';
export 'src/core/hls_parser.dart';
export 'src/core/hls_stream_proxy.dart';
export 'src/core/media_proxy.dart';
export 'src/core/media_source.dart';
export 'src/core/subtitle_converter.dart';
export 'src/subtitles/subtitle_decoder.dart';

// AirPlay (Apple platforms, AVPlayer)
export 'src/airplay/airplay_session.dart';

// Protocols — Chromecast
export 'src/protocols/chromecast/chromecast_discovery_provider.dart';
export 'src/protocols/chromecast/chromecast_session.dart';

// Protocols — DLNA
export 'src/protocols/chromecast/capability.dart';
export 'src/protocols/dlna/capability.dart';
export 'src/protocols/dlna/dlna_controller.dart';
export 'src/protocols/dlna/overrides.dart';
export 'src/protocols/dlna/dlna_device.dart';
export 'src/protocols/dlna/dlna_discovery_provider.dart';
export 'src/protocols/dlna/dlna_session.dart';
export 'src/protocols/dlna/ssdp_discovery.dart';

// Devices
export 'src/devices/device_merge.dart';

// Utils
export 'src/utils/logger.dart';
export 'src/utils/mdns_discovery.dart';
export 'src/utils/network_utils.dart';
