// Ported from PlayTorrioV3 lib/services/scraper/sites/knaben.dart and
// lib/models/stream/stream_model.dart, commit 39b736f.
// GPL-3.0; see root README.md (Credits) and LICENSE.
import 'package:contracts/contracts.dart';
import 'package:core/core.dart';

import 'release_text.dart' as text;

class TorrentResult {
  TorrentResult._({
    required this.releaseName,
    required this.infoHash,
    required List<String> trackers,
    required this.source,
    required this.releaseGroup,
    this.fileName,
    this.leechers,
    this.sizeBytes,
    this.seeders = 0,
  }) : trackers = List<String>.unmodifiable(trackers);

  factory TorrentResult.fromMagnet(
    String magnet, {
    required String releaseName,
    required String source,
    int? sizeBytes,
    int? seeders,
    int? leechers,
    String? fileName,
    String? sourceProvider,
  }) {
    final uri = Uri.parse(magnet);
    if (uri.scheme != 'magnet' || uri.hasAuthority || uri.path.isNotEmpty) {
      throw const FormatException('Expected a magnet URI');
    }
    // Changed from PlayTorrio: parse URI parameters so encoded xt and every tr survive.
    final parameters = uri.queryParametersAll;
    final pattern = RegExp(r'^urn:btih:([a-zA-Z0-9]+)$', caseSensitive: false);
    final hashes = (parameters['xt'] ?? const <String>[])
        .map(pattern.firstMatch)
        .whereType<RegExpMatch>();
    if (hashes.isEmpty) {
      throw const FormatException('Missing BitTorrent info hash');
    }
    final hash = _normaliseHash(hashes.first.group(1)!);
    final bytes = sizeBytes ?? text.sizeBytes(releaseName);
    final seeds = seeders ?? text.seeders(releaseName) ?? 0;
    if (bytes != null && bytes < 0) {
      throw ArgumentError.value(bytes, 'sizeBytes');
    }
    if (seeds < 0) throw ArgumentError.value(seeds, 'seeders');
    if (leechers != null && leechers < 0) {
      throw ArgumentError.value(leechers, 'leechers');
    }
    return TorrentResult._(
      releaseName: releaseName,
      infoHash: hash,
      trackers: parameters['tr'] ?? const <String>[],
      source: source,
      releaseGroup: _releaseGroup(releaseName, sourceProvider),
      fileName: fileName,
      leechers: leechers,
      sizeBytes: bytes,
      seeders: seeds,
    );
  }

  final String releaseName;
  final String infoHash;
  final List<String> trackers;
  final int? sizeBytes;
  final int seeders;
  final String source;
  final String releaseGroup;
  final String? fileName;
  final int? leechers;

  SourceSpec toSourceSpec(MediaItem item) {
    var magnet =
        'magnet:?xt=urn:btih:$infoHash&dn=${Uri.encodeComponent(releaseName)}';
    for (final tracker in trackers) {
      magnet += '&tr=${Uri.encodeComponent(tracker)}';
    }
    final quality = text.quality(releaseName);
    final size = text.fileSize(releaseName) ?? _displaySize(sizeBytes);
    return SourceSpec(
      kind: SourceKind.torrentMagnet,
      uri: Uri.parse(magnet),
      fileHint: fileName,
      label: [
        releaseName,
        size,
        'Release group: $releaseGroup',
        'Seeders: $seeders',
        if (leechers != null) 'Leechers: $leechers',
      ].join('\n'),
      quality: quality == '4K' ? '2160p' : quality,
      expectedBytes: sizeBytes,
      seasonNumber: item.seasonNumber,
      episodeNumber: item.episodeNumber,
      episodeTitle: item.subtitle,
    );
  }
}

String _releaseGroup(String title, String? sourceProvider) {
  const known = {
    'yts': 'YTS',
    'yify': 'YIFY',
    'rarbg': 'RARBG',
    'tigole': 'Tigole',
    'qxr': 'QxR',
    'psa': 'PSA',
  };
  for (final entry in known.entries) {
    if (RegExp(
      '(?:^|[^a-zA-Z0-9])${entry.key}(?:[^a-zA-Z0-9]|\$)',
      caseSensitive: false,
    ).hasMatch(title)) {
      return entry.value;
    }
  }
  final parsed = _titleParser.parse(title)['group'] as String?;
  if (parsed != null &&
      !RegExp(
        r'^(?:web|dl|hd|dts|aac|hevc|avc|hdr|x26[45])$',
        caseSensitive: false,
      ).hasMatch(parsed)) {
    return parsed;
  }
  return sourceProvider?.trim().isNotEmpty == true
      ? sourceProvider!.trim()
      : 'Torrent';
}

final _titleParser = ParseTorrentTitle();

// Changed from PlayTorrio: validate hex and canonicalise base32 to the same 20-byte hash.
String _normaliseHash(String hash) {
  if (RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(hash)) return hash.toLowerCase();
  if (!RegExp(r'^[A-Z2-7]{32}$', caseSensitive: false).hasMatch(hash)) {
    throw const FormatException('Invalid BitTorrent info hash');
  }
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  var buffer = 0;
  var bits = 0;
  final hex = StringBuffer();
  for (final code in hash.toUpperCase().codeUnits) {
    buffer = (buffer << 5) | alphabet.indexOf(String.fromCharCode(code));
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      hex.write(((buffer >> bits) & 255).toRadixString(16).padLeft(2, '0'));
      buffer &= (1 << bits) - 1;
    }
  }
  return hex.toString();
}

String _displaySize(int? bytes) {
  if (bytes == null) return '';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final number = unit == 0 ? size.toInt().toString() : size.toStringAsFixed(1);
  return '$number ${units[unit]}';
}
