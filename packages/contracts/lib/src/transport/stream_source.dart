import '../media/source_spec.dart';
import 'source_status.dart';
import 'transport_options.dart';

/// Resolves a [SourceSpec] to a playable [StreamHandle]. Provided by
/// Part 03. Consumed by Part 04 (status display) and Part 07 (wiring).
/// Part 02 never imports this — the player only ever sees a `Uri`.
abstract interface class StreamSource {
  /// Resolves a spec to something a player can open. Does not start
  /// playback.
  ///
  /// [options] applies to this stream only; a later change reaches the
  /// next [open].
  Future<StreamHandle> open(
    SourceSpec spec, {
    TransportOptions options = const TransportOptions(),
  });

  /// Deletes the cached data (and its persisted transport state) of every
  /// stream that is not open. Open streams are untouched. Returns the bytes
  /// freed on disk.
  Future<int> clearCache();
}

/// What the player opens. A localhost Range URL for HTTP/torrent sources, a
/// `file://` URI for local files. Valid until [dispose].
///
/// Deliberately has no `Future<List<int>> read(ByteRange)`: that would let
/// Part 02 or Part 04 pull bytes and invent a second data path. The player
/// only ever gets a `Uri`.
///
/// **Invariants Part 03 must hold**
/// (`research/technical/PLAYER_ARCHITECTURE.md`), copied verbatim so they
/// travel with the interface:
///
/// 1. A read request creates source demand; identical demand is
///    deduplicated.
/// 2. A seek invalidates obsolete demand and moves the active window.
/// 3. `available` is ranges. Never report readiness from a percentage.
/// 4. `dispose()` leaves no running process, no open socket, no scheduled
///    piece deadline.
/// 5. The server never returns `200`/`206` for bytes it does not have — it
///    waits or fails.
abstract interface class StreamHandle {
  Uri get playbackUri;

  /// Null until known.
  int? get totalBytes;

  /// Broadcast, emits on change (not on a timer), and replays the latest
  /// value to a new listener — a UI that subscribes one frame late must
  /// not see an empty state forever.
  Stream<SourceStatus> get status;

  /// Control-plane hint that playback is moving to this byte offset.
  /// Advisory only: the authoritative demand signal is the Range request
  /// the player actually issues. Part 03 must not be correct only when
  /// hints arrive.
  Future<void> seekHint(int byteOffset);

  /// Idempotent; releases jobs, pieces, sockets.
  Future<void> dispose();
}
