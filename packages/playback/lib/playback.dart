/// media_kit / libmpv playback engine boundary.
///
/// Owned by Part 02. See `planning/part-02-*/PART.md`.
library;

export 'package:contracts/contracts.dart';

export 'src/controller/preferred_tracks.dart';
export 'src/surface/hdr_policy.dart';

import 'package:core/core.dart';
import 'package:contracts/contracts.dart';

import 'src/controller/media_kit_playback_controller.dart';
import 'src/surface/hdr_policy.dart';
import 'src/surface/native_video_surface.dart';

/// Creates an independent media player and native engine instance.
PlaybackController createPlaybackController({
  required AppLogger logger,
  HdrPolicy hdrPolicy = HdrPolicy.auto,
}) => MediaKitPlaybackController(logger: logger, hdrPolicy: hdrPolicy);

/// Creates native output where shipped, with a diagnosed texture fallback.
VideoSurface createVideoSurface() => NativeVideoSurfaceAdapter();
