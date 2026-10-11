/// A moment's transfer numbers for one open stream, read on demand (the
/// player's download popover and stats overlay) — never pushed or polled by
/// the transport on its own. A field is null when the transport genuinely
/// cannot know it right now (e.g. an HTTP server that sent no size).
class TransportStats {
  const TransportStats({
    required this.downloadBytesPerSecond,
    required this.downloadedBytes,
    this.totalBytes,
    this.connections,
    this.torrent,
  });

  final double downloadBytesPerSecond;

  /// Bytes of the stream on disk now.
  final int downloadedBytes;

  /// Null until the server or torrent metadata says.
  final int? totalBytes;

  /// Open HTTP connections; null for torrents (see [torrent]).
  final int? connections;

  /// Present only for torrent streams.
  final TorrentStats? torrent;

  /// Remaining time at the current speed; null when the size or the speed is
  /// unknown or the speed is zero.
  Duration? get timeLeft {
    final total = totalBytes;
    if (total == null || downloadBytesPerSecond <= 0) return null;
    final remaining = total - downloadedBytes;
    if (remaining <= 0) return Duration.zero;
    return Duration(
      milliseconds: (remaining * 1000 / downloadBytesPerSecond).round(),
    );
  }
}

/// The torrent-only part of [TransportStats] (libtorrent `torrent_status`).
class TorrentStats {
  const TorrentStats({
    required this.uploadBytesPerSecond,
    required this.seeds,
    required this.peers,
    required this.piecesHave,
    required this.piecesTotal,
    required this.pieceSize,
    required this.availability,
    required this.infoHash,
    this.swarmSeeds,
    this.swarmPeers,
  });

  final double uploadBytesPerSecond;

  /// Seeds / peers this client is connected to now.
  final int seeds;
  final int peers;

  /// What the tracker reports for the whole swarm; null when it sent none.
  final int? swarmSeeds;
  final int? swarmPeers;
  final int piecesHave;
  final int piecesTotal;
  final int pieceSize;

  /// libtorrent's distributed copies (how many full copies the connected
  /// peers hold together).
  final double availability;
  final String infoHash;
}

/// Implemented by stream handles that can report [TransportStats]. Local
/// files and direct-URL (HLS) handles do not implement it.
abstract interface class TransportStatsProvider {
  Future<TransportStats> readStats();
}
