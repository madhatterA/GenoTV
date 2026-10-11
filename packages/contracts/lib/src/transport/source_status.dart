import '../media/byte_range.dart';
import 'transport_failure.dart';

enum SourceState {
  resolving,
  metadata,
  buffering,
  ready,
  stalled,
  failed,
  closed,
}

/// The transport layer's report of one source's readiness. No percentage
/// field — a UI that wants a bar computes it from [available] and
/// [totalBytes] and knows what it is showing
/// (`research/technical/HTTP_STREAMING.md`: "Do not infer byte readiness
/// from percentage alone").
class SourceStatus {
  SourceStatus({
    required this.state,
    required this.available,
    required this.totalBytes,
    required this.bytesPerSecond,
    required this.peersOrConnections,
    this.failure,
  }) : assert(
         (state == SourceState.failed || state == SourceState.stalled) ==
             (failure != null),
         'failure must be non-null iff state is failed or stalled',
       );

  final SourceState state;
  final RangeSet available;

  /// Null before `Content-Length` or torrent metadata is known. Kept
  /// nullable rather than defaulting to 0 so every consumer has to handle
  /// "unknown size" explicitly.
  final int? totalBytes;
  final double bytesPerSecond;

  /// Peer count for torrent sources, connection count for HTTP — one `int`
  /// deliberately, so a torrent-shaped peer model does not leak into a
  /// contract HTTP would have to fake.
  final int peersOrConnections;

  /// Non-null iff [state] is [SourceState.failed] or [SourceState.stalled].
  final TransportFailure? failure;
}
