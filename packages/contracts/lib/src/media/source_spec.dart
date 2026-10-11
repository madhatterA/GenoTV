/// How to obtain a [MediaItem]'s bytes.
enum SourceKind { httpUrl, torrentMagnet, torrentFile, localFile, hlsUrl }

/// How to obtain the bytes. See `planning/CONTRACTS.md` §1.
class SourceSpec {
  SourceSpec({
    required this.kind,
    required this.uri,
    Map<String, String> headers = const <String, String>{},
    this.fileHint,
    this.expectedBytes,
    this.label,
    this.quality,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeTitle,
  }) : headers = Map<String, String>.unmodifiable(headers);

  final SourceKind kind;
  final Uri uri;

  /// HTTP only.
  final Map<String, String> headers;

  /// Multi-file torrents: which file is the media. Providers may also supply
  /// the known download filename here for display.
  final String? fileHint;

  /// When the caller already knows.
  final int? expectedBytes;

  /// Description shown in the stream list.
  final String? label;

  /// Resolution shown in the stream list, e.g. `1080p`.
  final String? quality;

  /// Requested season for episode-aware torrent file selection.
  final int? seasonNumber;

  /// Requested episode for episode-aware torrent file selection.
  final int? episodeNumber;

  /// Optional episode title used when matching torrent filenames.
  final String? episodeTitle;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SourceSpec &&
          other.kind == kind &&
          other.uri == uri &&
          other.fileHint == fileHint &&
          other.expectedBytes == expectedBytes &&
          other.label == label &&
          other.quality == quality &&
          other.seasonNumber == seasonNumber &&
          other.episodeNumber == episodeNumber &&
          other.episodeTitle == episodeTitle &&
          _mapEquals(other.headers, headers));

  @override
  int get hashCode => Object.hash(
    kind,
    uri,
    fileHint,
    expectedBytes,
    label,
    quality,
    seasonNumber,
    episodeNumber,
    episodeTitle,
    _mapHash(headers),
  );

  @override
  String toString() => 'SourceSpec($kind, $uri)';
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

// Order-independent, unlike Object.hash, since Map iteration order is not
// part of Map equality.
int _mapHash(Map<String, String> map) {
  var hash = 0;
  for (final entry in map.entries) {
    hash ^= Object.hash(entry.key, entry.value);
  }
  return hash;
}
