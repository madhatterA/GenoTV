import '../../l10n_gen/app_strings.dart';

import 'dart:async';
import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/foundation.dart';

import 'stats_format.dart';

/// What the player knows about the stream it is playing, plus how to read its
/// live numbers. Supplied by the app; the UI never reaches into the transport.
String statsLabel(String label, AppStrings strings) => switch (label) {
  'Source' => strings.player_stats_Source,
  'Provider' => strings.player_stats_Provider,
  'Host' => strings.player_stats_Host,
  'Protocol' => strings.player_stats_Protocol,
  'TLS' => strings.player_stats_TLS,
  'Connections' => strings.player_stats_Connections,
  'Network' => strings.player_stats_Network,
  'Speed' => strings.player_stats_Speed,
  'Speed down' => strings.player_stats_Speed_down,
  'Speed up' => strings.player_stats_Speed_up,
  'Pieces' => strings.player_stats_Pieces,
  'Piece size' => strings.player_stats_Piece_size,
  'Swarm (tracker)' => strings.player_stats_Swarm_tracker_,
  'Availability' => strings.player_stats_Availability,
  'Info-hash' => strings.player_stats_Info_hash,
  'Time left' => strings.player_stats_Time_left,
  'Buffer' => strings.player_stats_Buffer,
  'Buffered ahead' => strings.player_stats_Buffered_ahead,
  'Cache in memory' => strings.player_stats_Cache_in_memory,
  'Cache read speed' => strings.player_stats_Cache_read_speed,
  'Video' => strings.player_stats_Video,
  'Codec' => strings.player_stats_Codec,
  'Resolution' => strings.player_stats_Resolution,
  'Display size' => strings.player_stats_Display_size,
  'Frame rate' => strings.player_stats_Frame_rate,
  'Bitrate' => strings.player_stats_Bitrate,
  'Pixel format' => strings.player_stats_Pixel_format,
  'Colour' => strings.player_stats_Colour,
  'Hardware decoding' => strings.player_stats_Hardware_decoding,
  'Dropped frames' => strings.player_stats_Dropped_frames,
  'A/V sync' => strings.player_stats_A_V_sync,
  'Audio' => strings.player_stats_Audio,
  'Channels' => strings.player_stats_Channels,
  'Sample rate' => strings.player_stats_Sample_rate,
  'Output' => strings.player_stats_Output,
  'Subtitles' => strings.player_stats_Subtitles,
  'Track' => strings.player_stats_Track,
  'Player' => strings.player_stats_Player,
  'Container' => strings.player_stats_Container,
  'Position' => strings.player_stats_Position,
  'Engine' => strings.player_stats_Engine,
  'Downloaded' => strings.player_stats_Downloaded,
  'Progress' => strings.player_stats_Progress,
  'Download speed' => strings.player_stats_Download_speed,
  'Upload speed' => strings.player_stats_Upload_speed,
  'Seeds connected' => strings.player_stats_Seeds_connected,
  'Peers connected' => strings.player_stats_Peers_connected,
  'Swarm' => strings.player_stats_Swarm,
  _ => label,
};

class PlayerStatsSource {
  const PlayerStatsSource({
    required this.kind,
    this.uri,
    this.providerName,
    this.readTransport,
    this.readEngine,
  });

  final SourceKind kind;

  /// The address the title was resolved to (host and scheme are shown).
  final Uri? uri;
  final String? providerName;

  /// Null for local files and direct (HLS) URLs: no download popover.
  final Future<TransportStats> Function()? readTransport;

  /// Reads mpv properties on demand; null when the engine cannot.
  final Future<Map<String, String>> Function(List<String> names)? readEngine;

  bool get isTorrent =>
      kind == SourceKind.torrentMagnet || kind == SourceKind.torrentFile;

  /// The download popover is shown only for HTTP(S) and torrent streams.
  bool get hasTransferStats => readTransport != null;
}

/// One 1-second reading.
class PlayerStatsSnapshot {
  const PlayerStatsSnapshot({
    this.transport,
    this.engine = const <String, String>{},
    this.downHistory = const <double>[],
    this.upHistory = const <double>[],
  });

  final TransportStats? transport;
  final Map<String, String> engine;

  /// The last 30 one-second download (and upload) speeds, oldest first.
  final List<double> downHistory;
  final List<double> upHistory;
}

/// Reads the stats once a second, only between [start] and [stop] — nothing
/// runs while the popover and overlay are both closed.
class PlayerStatsController extends ChangeNotifier {
  PlayerStatsController(this.source);

  final PlayerStatsSource source;
  static const int historyLength = 30;
  PlayerStatsSnapshot _snapshot = const PlayerStatsSnapshot();
  Timer? _timer;
  bool _reading = false;
  bool _disposed = false;
  int _users = 0;
  Object? error;

  PlayerStatsSnapshot get snapshot => _snapshot;
  bool get isPolling => _timer != null;

  /// Each open surface (popover, overlay) calls this; polling stays on until
  /// every one has called [stop].
  void start() {
    _users++;
    if (_timer != null) return;
    unawaited(_read());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _read());
  }

  void stop() {
    if (_users > 0) _users--;
    if (_users > 0) return;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _read() async {
    if (_reading || _disposed) return;
    _reading = true;
    try {
      final transportRead = source.readTransport?.call();
      final engineRead = source.readEngine?.call(playerStatsProperties);
      final transport = await transportRead;
      final engine = await engineRead;
      if (_disposed) return;
      List<double> push(List<double> history, double? value) => value == null
          ? history
          : [
              ...history.length >= historyLength
                  ? history.sublist(history.length - historyLength + 1)
                  : history,
              value,
            ];
      _snapshot = PlayerStatsSnapshot(
        transport: transport,
        engine: engine ?? _snapshot.engine,
        downHistory: push(
          _snapshot.downHistory,
          transport?.downloadBytesPerSecond,
        ),
        upHistory: push(
          _snapshot.upHistory,
          transport?.torrent?.uploadBytesPerSecond,
        ),
      );
      error = null;
      notifyListeners();
    } on Object catch (e) {
      error = e;
      if (!_disposed) notifyListeners();
    } finally {
      _reading = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

/// One labelled line of the overlay.
class StatsRow {
  const StatsRow(this.label, this.value, {this.copyValue, this.speedGraph});

  final String label;
  final String value;

  /// Text copied when the row is tapped (e.g. the full info-hash).
  final String? copyValue;

  /// True when the row draws the speed sparkline under it.
  final bool? speedGraph;
}

class StatsGroup {
  const StatsGroup(this.title, this.rows);
  final String title;
  final List<StatsRow> rows;
}

/// Every group of the "Stats for nerds" overlay, from one reading.
List<StatsGroup> buildStatsGroups(
  PlayerStatsSource source,
  PlayerStatsSnapshot snap,
) {
  final e = snap.engine;
  final t = snap.transport;
  final scheme = source.uri?.scheme;
  String? text(String key) => e[key];
  String number(String key, String Function(double) show) {
    final value = double.tryParse(e[key] ?? '');
    return value == null ? statsUnknown : show(value);
  }

  final protocol = source.isTorrent
      ? (source.kind == SourceKind.torrentMagnet
            ? 'BitTorrent (magnet)'
            : 'BitTorrent (.torrent)')
      : scheme == 'https'
      ? 'HTTPS'
      : scheme == 'http'
      ? 'HTTP/1.1'
      : statsUnknown;
  final torrent = t?.torrent;
  final groups = <StatsGroup>[
    StatsGroup('Source', [
      StatsRow('Provider', source.providerName ?? statsUnknown),
      StatsRow(
        'Host',
        source.isTorrent
            ? statsUnknown
            : (source.uri?.host.isNotEmpty ?? false)
            ? source.uri!.host
            : statsUnknown,
      ),
      StatsRow('Protocol', protocol),
      StatsRow(
        'TLS',
        scheme == 'https'
            ? 'yes'
            : (scheme == 'http' || source.isTorrent)
            ? 'no'
            : statsUnknown,
      ),
      StatsRow(
        'Connections',
        torrent != null
            ? '${torrent.seeds} seeds / ${torrent.peers} peers'
            : formatCount(t?.connections),
      ),
    ]),
  ];
  if (t != null) {
    groups.add(
      StatsGroup('Network', [
        if (torrent == null)
          StatsRow(
            'Speed',
            formatSpeed(t.downloadBytesPerSecond),
            speedGraph: true,
          )
        else ...[
          StatsRow(
            'Speed down',
            formatSpeed(t.downloadBytesPerSecond),
            speedGraph: true,
          ),
          StatsRow('Speed up', formatSpeed(torrent.uploadBytesPerSecond)),
        ],
        StatsRow(
          torrent == null ? 'Downloaded' : 'Progress',
          formatProgress(t.downloadedBytes, t.totalBytes),
        ),
        if (torrent != null) ...[
          StatsRow('Pieces', '${torrent.piecesHave} / ${torrent.piecesTotal}'),
          StatsRow('Piece size', formatBytes(torrent.pieceSize)),
          StatsRow(
            'Swarm (tracker)',
            torrent.swarmSeeds == null && torrent.swarmPeers == null
                ? statsUnknown
                : '${formatCount(torrent.swarmSeeds)} seeds / '
                      '${formatCount(torrent.swarmPeers)} peers',
          ),
          StatsRow('Availability', torrent.availability.toStringAsFixed(2)),
          StatsRow(
            'Info-hash',
            shortInfoHash(torrent.infoHash),
            copyValue: torrent.infoHash,
          ),
        ] else
          StatsRow('Time left', formatEta(t.timeLeft)),
        if (torrent != null) StatsRow('Time left', formatEta(t.timeLeft)),
      ]),
    );
  }
  final cacheState = _cacheState(e['demuxer-cache-state']);
  final width = text('video-params/w');
  final height = text('video-params/h');
  final dw = text('video-params/dw');
  final dh = text('video-params/dh');
  final pixelFormat = text('video-params/pixelformat');
  final depth = bitDepthOfPixelFormat(pixelFormat);
  final hwdec = text('hwdec-current');
  final avsync = double.tryParse(e['avsync'] ?? '');
  final sid = text('sid');
  final subLang = text('current-tracks/sub/lang');
  final subCodec = text('current-tracks/sub/codec');
  final audioFormat = text('audio-out-params/format');
  groups
    ..add(
      StatsGroup('Buffer', [
        StatsRow(
          'Buffered ahead',
          number('demuxer-cache-duration', (v) => '${v.toStringAsFixed(1)} s'),
        ),
        StatsRow(
          'Cache in memory',
          cacheState == null
              ? statsUnknown
              : '${(cacheState / (1024 * 1024)).toStringAsFixed(1)} MB',
        ),
        StatsRow('Cache read speed', number('cache-speed', formatSpeed)),
      ]),
    )
    ..add(
      StatsGroup('Video', [
        StatsRow('Codec', formatCodec(text('video-codec'))),
        StatsRow(
          'Resolution',
          width == null || height == null ? statsUnknown : '${width}x$height',
        ),
        StatsRow(
          'Display size',
          dw == null || dh == null ? statsUnknown : '${dw}x$dh',
        ),
        StatsRow(
          'Frame rate',
          '${number('container-fps', (v) => v.toStringAsFixed(3))} fps '
              '(playing ${number('estimated-vf-fps', (v) => v.toStringAsFixed(2))})',
        ),
        StatsRow(
          'Bitrate',
          number('video-bitrate', (v) => '${(v / 1000).round()} kbit/s'),
        ),
        StatsRow(
          'Pixel format',
          pixelFormat == null
              ? statsUnknown
              : '$pixelFormat${depth == null ? '' : ' ($depth-bit)'}',
        ),
        StatsRow(
          'Colour',
          '${text('video-params/primaries') ?? statsUnknown} / '
              '${text('video-params/gamma') ?? statsUnknown}',
        ),
        StatsRow(
          'Hardware decoding',
          hwdec == null
              ? statsUnknown
              : (hwdec == 'no' ? 'no' : 'yes ($hwdec)'),
        ),
        StatsRow(
          'Dropped frames',
          'decoder ${text('decoder-frame-drop-count') ?? statsUnknown}, '
              'output ${text('frame-drop-count') ?? statsUnknown}',
        ),
        StatsRow(
          'A/V sync',
          avsync == null
              ? statsUnknown
              : '${(avsync * 1000).toStringAsFixed(1)} ms',
        ),
      ]),
    )
    ..add(
      StatsGroup('Audio', [
        StatsRow('Codec', formatCodec(text('audio-codec'))),
        StatsRow('Channels', text('audio-params/hr-channels') ?? statsUnknown),
        StatsRow(
          'Sample rate',
          number('audio-params/samplerate', (v) => '${v.round()} Hz'),
        ),
        StatsRow(
          'Bitrate',
          number('audio-bitrate', (v) => '${(v / 1000).round()} kbit/s'),
        ),
        StatsRow(
          'Output',
          audioFormat == null
              ? statsUnknown
              : audioFormat.startsWith('spdif')
              ? 'passthrough ($audioFormat)'
              : 'PCM ($audioFormat)',
        ),
      ]),
    )
    ..add(
      StatsGroup('Subtitles', [
        StatsRow(
          'Track',
          (sid == null || sid == 'no') && subLang == null && subCodec == null
              ? 'off'
              : [subLang, subCodec].whereType<String>().join(' · '),
        ),
      ]),
    )
    ..add(
      StatsGroup('Player', [
        StatsRow('Container', text('file-format') ?? statsUnknown),
        StatsRow(
          'Position',
          '${number('time-pos', (v) => formatEta(Duration(milliseconds: (v * 1000).round())))}'
              ' / ${number('duration', (v) => formatEta(Duration(milliseconds: (v * 1000).round())))}',
        ),
        StatsRow(
          'Engine',
          '${text('mpv-version') ?? statsUnknown}, vo ${text('current-vo') ?? statsUnknown}',
        ),
      ]),
    );
  return groups;
}

/// `fw-bytes` of mpv's demuxer-cache-state JSON.
int? _cacheState(String? raw) {
  if (raw == null) return null;
  try {
    final state = jsonDecode(raw);
    final bytes = state is Map ? state['fw-bytes'] : null;
    return bytes is num ? bytes.round() : null;
  } on FormatException {
    return null;
  }
}

/// All values as text, for the Copy button ("copy debug info").
String statsAsText(List<StatsGroup> groups) => [
  for (final group in groups) ...[
    '[${group.title}]',
    for (final row in group.rows) '${row.label}: ${row.copyValue ?? row.value}',
    '',
  ],
].join('\n').trimRight();
