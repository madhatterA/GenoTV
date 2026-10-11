import 'package:contracts/contracts.dart';

/// Project-specific thresholds, not a libtorrent default or a value from any
/// upstream spec: libtorrent reports progress/peer counts continuously and
/// leaves "stalled" and "no peers" undefined at the alert layer, so this
/// project defines them itself. Chosen as a starting point (not yet tuned by
/// Part 08's measurement pass) to be long enough to absorb a normal lull in
/// piece-progress/tracker-announce timing on a slow real swarm, but short
/// enough that a genuinely stuck download surfaces to the UI in single-digit
/// seconds rather than leaving playback silently buffering indefinitely.
const Duration torrentStallThreshold = Duration(seconds: 10);
const Duration torrentNoPeersThreshold = Duration(seconds: 15);

enum TorrentAlertKind {
  metadataReceived,
  pieceFinished,
  torrentError,
  fileError,
  trackerError,
  torrentFinished,
  stateChanged,
  peerDisconnected,
}

class TorrentAlert {
  const TorrentAlert(this.kind, {this.piece, this.peerCount, this.error});
  final TorrentAlertKind kind;
  final int? piece;
  final int? peerCount;
  final Object? error;
}

class AlertRouter {
  SourceState state = SourceState.metadata;
  int peers = 0;
  int? playHeadPiece;
  bool waitingForPlayHead = false;
  DateTime? waitingSince;
  TransportFailure? failure;
  bool _hasMetadata = false;
  DateTime? _zeroPeersSince;

  void route(TorrentAlert alert, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    switch (alert.kind) {
      case TorrentAlertKind.metadataReceived:
        _hasMetadata = true;
        state = SourceState.buffering;
        break;
      case TorrentAlertKind.pieceFinished:
        if (waitingForPlayHead && alert.piece == playHeadPiece) {
          waitingForPlayHead = false;
          _recover();
        } else if (waitingForPlayHead) {
          // The swarm is delivering: a slow multi-piece window (a tail read
          // for an MP4 index) is not a stall, only no progress at all is.
          waitingSince = clock;
        }
        break;
      case TorrentAlertKind.torrentError:
        failure = TransportFailure.torrentStalled(cause: alert.error);
        state = SourceState.failed;
        break;
      case TorrentAlertKind.fileError:
        failure = TransportFailure.torrentFileError(cause: alert.error);
        state = SourceState.failed;
        break;
      case TorrentAlertKind.trackerError:
        break;
      case TorrentAlertKind.peerDisconnected:
        updatePeers(alert.peerCount ?? peers, now: clock);
        break;
      case TorrentAlertKind.torrentFinished:
      case TorrentAlertKind.stateChanged:
        if (alert.peerCount != null) peers = alert.peerCount!;
        break;
    }
  }

  void updatePeers(int count, {DateTime? now}) {
    peers = count;
    if (!_hasMetadata || count > 0) {
      _zeroPeersSince = null;
      return;
    }
    final clock = now ?? DateTime.now();
    _zeroPeersSince ??= clock;
    if (clock.difference(_zeroPeersSince!) >= torrentNoPeersThreshold) {
      failure = const TransportFailure.torrentNoPeers(
        cause: 'no connected peers after metadata',
      );
      state = SourceState.failed;
    }
  }

  /// Playback now needs [piece]. A piece already on disk is not a wait: it
  /// would never raise a pieceFinished alert, and the stall timer would fire
  /// on a healthy stream. A new wait also clears an earlier stall (the stall
  /// is about the previous wait); real failures stay.
  void waitAt(int piece, {bool have = false, DateTime? now}) {
    playHeadPiece = piece;
    if (state == SourceState.failed) return;
    _recover();
    waitingForPlayHead = !have;
    waitingSince = now ?? DateTime.now();
    if (!have) state = SourceState.buffering;
  }

  // A stall is transient: it ends when the awaited data arrives or playback
  // asks for something else. Failures never end here.
  void _recover() {
    if (state == SourceState.failed) return;
    if (state == SourceState.stalled) failure = null;
    state = SourceState.ready;
  }

  void checkStall({DateTime? now}) {
    final clock = now ?? DateTime.now();
    if (waitingForPlayHead &&
        waitingSince != null &&
        state != SourceState.failed &&
        clock.difference(waitingSince!) >= torrentStallThreshold) {
      failure = const TransportFailure.torrentStalled(
        cause: 'no piece finished while playback was waiting',
      );
      state = SourceState.stalled;
    }
  }
}
