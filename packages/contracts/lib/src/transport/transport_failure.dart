import 'package:core/core.dart';

/// Transport (aria2/libtorrent/local range server) failures. `transport.*`
/// prefix — three sub-namespaces (`transport.http.*`, `transport.torrent.*`,
/// `transport.range.*`), owned by Part 03
/// (`planning/CONTRACTS.md` §0 registry).
///
/// Lives in `packages/contracts`, not `packages/transport`: it is a field
/// of [SourceStatus], a contract type.
final class TransportFailure extends AppFailure {
  /// Server ignored `Range` or lacks `Accept-Ranges`
  /// (`research/technical/HTTP_STREAMING.md`: "validate Accept-Ranges,
  /// Content-Length, validators, and redirects").
  const TransportFailure.httpNoRangeSupport({required super.cause, super.stack})
    : super(
        code: _httpNoRangeSupport,
        message: 'Server ignored Range or lacks Accept-Ranges',
      );

  /// `ETag`/`Last-Modified` changed mid-download (same citation as above).
  const TransportFailure.httpValidatorChanged({super.cause, super.stack})
    : super(
        code: _httpValidatorChanged,
        message: 'ETag/Last-Modified changed mid-download',
      );

  /// (`research/technical/HTTP_STREAMING.md`: "exposes readiness and
  /// errors to the player/range server").
  const TransportFailure.httpUnreachable({required super.cause, super.stack})
    : super(code: _httpUnreachable, message: 'The HTTP source is unreachable');

  /// The 416 case (`research/technical/HTTP_STREAMING.md`: "prevents the
  /// player from reading beyond a safe hole, or waits for that hole to
  /// fill").
  const TransportFailure.rangeUnsatisfiable({super.cause, super.stack})
    : super(
        code: _rangeUnsatisfiable,
        message: 'The requested byte range cannot be satisfied',
      );

  /// (`research/technical/TORRENT_STREAMING.md`: "Metadata retrieval and
  /// magnet handling must complete before this mapping is reliable").
  const TransportFailure.torrentNoMetadata({super.cause, super.stack})
    : super(code: _torrentNoMetadata, message: 'Magnet metadata never arrived');

  /// (`research/technical/TORRENT_STREAMING.md`: "peer availability,
  /// alerts").
  const TransportFailure.torrentNoPeers({super.cause, super.stack})
    : super(
        code: _torrentNoPeers,
        message: 'No peers are available for this torrent',
      );

  /// No progress at the play head past a threshold
  /// (`research/technical/TORRENT_STREAMING.md`: "Observe piece_finished,
  /// read-piece, state, and peer/availability alerts").
  const TransportFailure.torrentStalled({super.cause, super.stack})
    : super(
        code: _torrentStalled,
        message: 'No progress at the play head past the stall threshold',
      );

  const TransportFailure.torrentFileError({required super.cause, super.stack})
    : super(
        code: _torrentFileError,
        message: 'The torrent could not read or write its files',
      );

  /// `fileHint` matched nothing (`research/technical/TORRENT_STREAMING.md`:
  /// "select the media file and map file-relative offsets to torrent piece
  /// indexes").
  const TransportFailure.torrentFileNotFound({super.cause, super.stack})
    : super(
        code: _torrentFileNotFound,
        message: 'fileHint matched no file in the torrent',
      );

  /// aria2/libtorrent missing or failed to start — an operational/
  /// environment failure, not specific to either research note.
  const TransportFailure.engineUnavailable({required super.cause, super.stack})
    : super(
        code: _engineUnavailable,
        message: 'aria2/libtorrent is missing or failed to start',
      );

  static const String _httpNoRangeSupport = 'transport.http.no_range_support';
  static const String _httpValidatorChanged =
      'transport.http.validator_changed';
  static const String _httpUnreachable = 'transport.http.unreachable';
  static const String _rangeUnsatisfiable = 'transport.range.unsatisfiable';
  static const String _torrentNoMetadata = 'transport.torrent.no_metadata';
  static const String _torrentNoPeers = 'transport.torrent.no_peers';
  static const String _torrentStalled = 'transport.torrent.stalled';
  static const String _torrentFileError = 'transport.torrent.file_error';
  static const String _torrentFileNotFound = 'transport.torrent.file_not_found';
  static const String _engineUnavailable = 'transport.engine.unavailable';
}
