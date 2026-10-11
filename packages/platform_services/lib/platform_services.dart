/// HDR, display mode switching, audio passthrough, lifecycle.
///
/// Owned by Part 05. See `planning/part-05-*/PART.md`.
library;

export 'src/channel/platform_channel.dart';
export 'src/channel/platform_dispatch.dart';
export 'src/channel/platform_events.dart';
export 'src/capabilities/capability_service.dart';
export 'src/diagnostics/diagnostics_collector.dart';
export 'src/display/display_mode_service_impl.dart';
export 'src/display/display_screen_service.dart';
export 'src/display/display_mode_lease_impl.dart';
export 'src/display/hdr_service.dart';
export 'src/display/mode_matcher.dart';
export 'src/display/mode_whitelist.dart';
export 'src/audio/audio_output_service_impl.dart';
export 'src/audio/fallback_chain.dart';
export 'src/audio/indicator.dart';
export 'src/audio/capability_model.dart';
export 'src/audio/passthrough_negotiator.dart';
export 'src/lifecycle/playback_lifecycle_service.dart';
export 'src/window/window_service.dart';
export 'src/process/open_file_limit.dart';

import 'package:contracts/contracts.dart';

import 'src/audio/audio_output_service_impl.dart';
import 'src/channel/platform_channel.dart';
import 'src/display/display_mode_service_impl.dart';

PlatformChannel _channel(PlatformChannel? channel) =>
    channel ?? MethodPlatformChannel();

DisplayModeService createDisplayModeService({PlatformChannel? channel}) =>
    DisplayModeServiceImpl(channel: _channel(channel));

AudioOutputService createAudioOutputService({PlatformChannel? channel}) =>
    AudioOutputServiceImpl(channel: _channel(channel));
