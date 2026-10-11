import 'dart:typed_data';

import '../media/source_spec.dart';

/// Download and torrent state that must survive a restart. Written by
/// Part 03 only.
class DownloadRecord {
  DownloadRecord({
    required this.sourceKey,
    required this.kind,
    this.filePath,
    this.totalBytes,
    this.validator,
    required this.lastUsedAt,
  }) : assert(lastUsedAt.isUtc, 'lastUsedAt must be stored as UTC — convert at the edge');

  final String sourceKey;
  final SourceKind kind;

  /// The partial file on disk.
  final String? filePath;
  final int? totalBytes;

  /// `ETag`/`Last-Modified`, so a resumed HTTP download can detect the
  /// `transport.http.validator_changed` case across an app restart, not
  /// just within a session.
  final String? validator;

  /// Drives cache eviction in Part 08.
  final DateTime lastUsedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DownloadRecord &&
          other.sourceKey == sourceKey &&
          other.kind == kind &&
          other.filePath == filePath &&
          other.totalBytes == totalBytes &&
          other.validator == validator &&
          other.lastUsedAt == lastUsedAt);

  @override
  int get hashCode =>
      Object.hash(sourceKey, kind, filePath, totalBytes, validator, lastUsedAt);
}

/// Provided by `packages/persistence` (Part 01).
abstract interface class TransportStateRepository {
  Future<DownloadRecord?> get(String sourceKey);
  Future<void> upsert(DownloadRecord record);
  Future<List<DownloadRecord>> all();
  Future<void> delete(String sourceKey);

  Future<Uint8List?> torrentResumeData(String infoHash);
  Future<void> putTorrentResumeData(String infoHash, Uint8List data);
}

/// Derives the stable key Parts 03, 07 and 08 all compute for a given
/// [SourceSpec]: `kind` + a normalised `uri` + `fileHint`, joined —
/// deliberately **excluding `headers`**, which carry expiring tokens;
/// including them would mint a new key every session, so nothing would
/// ever resume and the cache would grow forever.
///
/// This is a composite string, not a cryptographic digest: `Object.hash`/
/// `hashCode` are not guaranteed stable across Dart SDK versions, and using
/// them for a key that must stay valid across an app upgrade would
/// silently orphan every cached [DownloadRecord] the next time the SDK
/// changes — the same "quiet, expensive bug" shape as including headers.
/// `packages/contracts` may not gain a new dependency for a proper hash
/// function, and the plain composite string is already stable and unique
/// enough for this purpose.
///
/// URI normalisation: lowercases the host and strips one trailing slash
/// from the path (so `.../file` and `.../file/` key the same). Scheme,
/// port and query are left untouched.
String deriveSourceKey(SourceSpec spec) {
  final uri = _normalizeUri(spec.uri);
  return '${spec.kind.name}|$uri|${spec.fileHint ?? ''}';
}

Uri _normalizeUri(Uri uri) {
  var path = uri.path;
  if (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return uri.replace(host: uri.host.toLowerCase(), path: path);
}
