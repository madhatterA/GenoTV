/// Implemented by playback controllers backed by an engine that can read
/// named properties on demand (mpv). Reads only when called: the stats
/// overlay asks once a second while it is open and nothing runs otherwise.
abstract interface class EngineProperties {
  /// The current text of each property in [names]. A property the engine
  /// does not have (or has no value for right now) is left out of the result.
  Future<Map<String, String>> readProperties(List<String> names);
}

/// The mpv properties the "Stats for nerds" overlay reads (mpv manual,
/// `research/technical/playback/mpv/DOCS/man/input.rst`, checked against the
/// real bundled libmpv by `packages/playback/test/engine_properties_test.dart`).
const List<String> playerStatsProperties = <String>[
  'file-format',
  'mpv-version',
  'current-vo',
  'duration',
  'time-pos',
  'video-codec',
  'video-params/w',
  'video-params/h',
  'video-params/dw',
  'video-params/dh',
  'video-params/pixelformat',
  'video-params/primaries',
  'video-params/gamma',
  'video-params/colormatrix',
  'container-fps',
  'estimated-vf-fps',
  'video-bitrate',
  'hwdec-current',
  'frame-drop-count',
  'decoder-frame-drop-count',
  'avsync',
  'audio-codec',
  'audio-params/hr-channels',
  'audio-params/samplerate',
  'audio-bitrate',
  'audio-out-params/format',
  'current-ao',
  'demuxer-cache-duration',
  'demuxer-cache-state',
  'cache-speed',
  'current-tracks/sub/lang',
  'current-tracks/sub/codec',
  'sid',
];
