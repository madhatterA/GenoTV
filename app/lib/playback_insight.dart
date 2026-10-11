import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier;

/// What the Advanced page shows about the video playing now. The playback
/// session fills it; it is empty ("Not playing") otherwise.
final class PlaybackInsight {
  /// mpv property name -> mpv's value text, from the engine's observers.
  final ValueNotifier<Map<String, String>> diagnostics =
      ValueNotifier<Map<String, String>>(const {});

  /// [diagnostics] as the labelled rows the page shows.
  final ValueNotifier<Map<String, String>> rows =
      ValueNotifier<Map<String, String>>(diagnosticRows(const {}));

  void update(Map<String, String> raw) {
    diagnostics.value = raw;
    rows.value = diagnosticRows(raw);
  }

  /// Custom mpv option lines the engine rejected, null when all were taken.
  final ValueNotifier<String?> customOptionsNote = ValueNotifier<String?>(null);
}

/// Label and shown text for each observed mpv property, in display order.
const Map<String, String> diagnosticLabels = {
  'video-codec': 'Video codec',
  'hwdec-current': 'Decoder',
  'video-params/w': 'Video width',
  'video-params/h': 'Video height',
  'video-params/pixelformat': 'Pixel format',
  'video-params/colormatrix': 'Color matrix',
  'video-params/gamma': 'Transfer function',
  'video-params/primaries': 'Color primaries',
  'video-params/sig-peak': 'HDR signal peak',
  'video-params/max-cll': 'HDR max CLL',
  'video-params/max-fall': 'HDR max FALL',
  'frame-drop-count': 'Dropped frames (output)',
  'decoder-frame-drop-count': 'Dropped frames (decoder)',
  'video-bitrate': 'Video bitrate',
  'audio-bitrate': 'Audio bitrate',
  'demuxer-cache-duration': 'Buffered (seconds)',
  'demuxer-cache-state': 'Buffered (bytes)',
  'audio-codec': 'Audio codec',
  'audio-params/format': 'Audio format',
  'audio-params/samplerate': 'Audio sample rate',
  'audio-params/channels': 'Audio channels',
  'current-ao': 'Audio output',
  'audio-out-params/format': 'Audio output format',
  'audio-out-params/samplerate': 'Audio output sample rate',
  'audio-out-params/channels': 'Audio output channels',
};

/// The text shown for one property: mpv's own text, except bitrates (kbit/s)
/// and the cache state (its `fw-bytes`).
String shownDiagnostic(String property, String raw) {
  switch (property) {
    case 'video-bitrate' || 'audio-bitrate':
      final bps = int.tryParse(raw);
      return bps == null ? raw : '${(bps / 1000).round()} kbit/s';
    case 'demuxer-cache-state':
      final state = jsonDecode(raw);
      return state is Map && state['fw-bytes'] != null
          ? '${state['fw-bytes']} bytes'
          : raw;
    case 'audio-out-params/format':
      return raw.startsWith('spdif') ? '$raw (passthrough)' : raw;
  }
  return raw;
}

/// The rows of the diagnostics page for [raw] (empty = not playing).
Map<String, String> diagnosticRows(Map<String, String> raw) => raw.isEmpty
    ? const {'Playback': 'Not playing'}
    : {
        for (final entry in diagnosticLabels.entries)
          if (raw.containsKey(entry.key))
            entry.value: shownDiagnostic(entry.key, raw[entry.key]!),
      };
