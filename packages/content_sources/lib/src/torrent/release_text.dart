// Ported from PlayTorrioV3 lib/models/stream/stream_model.dart, commit 39b736f.
// GPL-3.0; see root README.md (Credits) and LICENSE.
final _fileSizeRegex = RegExp(
  r'(\d+(?:[\.,]\d+)?)\s*(TB|TiB|GB|GiB|MB|MiB|KB|KiB)|(TB|TiB|GB|GiB|MB|MiB|KB|KiB)\s*(\d+(?:[\.,]\d+)?)',
  caseSensitive: false,
);

final _seederPatterns = [
  // Changed from PlayTorrio: match emoji code points, not shared surrogate halves.
  RegExp(r'[👤👥🌱⚡]\s*(\d+)', caseSensitive: false, unicode: true),
  RegExp(r'(?:seeds?|seeders?|peers?|s)\s*[:=]\s*(\d+)', caseSensitive: false),
  RegExp(r'(\d+)\s*(?:seeds?|seeders?)', caseSensitive: false),
  RegExp(r'\[\s*(\d+)\s*(?:s|seeds?)', caseSensitive: false),
  RegExp(r'/\s*(\d+)\s*peers?', caseSensitive: false),
  RegExp(r'(\d+)\s*/\s*\d+\s*(?:peers?|seeds?)?', caseSensitive: false),
];

String? quality(String releaseText) {
  final text = releaseText.toLowerCase();
  if (text.contains('2160') || text.contains('4k') || text.contains('uhd')) {
    return '4K';
  }
  if (text.contains('1080')) return '1080p';
  if (text.contains('720')) return '720p';
  if (text.contains('480')) return '480p';
  return null;
}

bool isHDR(String releaseText) {
  final text = releaseText.toLowerCase();
  // Changed from PlayTorrio: DV must be a tag, not the letters in DVD/Adventure.
  return text.contains('hdr') ||
      text.contains('dolby vision') ||
      RegExp(r'\bdv\b').hasMatch(text);
}

String? codec(String releaseText) {
  final text = releaseText.toLowerCase();
  if (text.contains('hevc') ||
      text.contains('x265') ||
      text.contains('h.265') ||
      text.contains('h265')) {
    return 'HEVC';
  }
  if (text.contains('x264') ||
      text.contains('h.264') ||
      text.contains('h264') ||
      text.contains('avc')) {
    return 'H.264';
  }
  if (text.contains('av1')) return 'AV1';
  return null;
}

String? fileSize(String text) {
  final match = _fileSizeRegex.firstMatch(text);
  if (match != null) {
    final numStr = match.group(1) ?? match.group(4);
    final unit = (match.group(2) ?? match.group(3))?.toUpperCase();
    if (numStr != null && unit != null) return '$numStr $unit';
  }
  return null;
}

int? sizeBytes(String text) {
  final match = _fileSizeRegex.firstMatch(text);
  if (match != null) {
    final numStr = match.group(1) ?? match.group(4);
    final unit = (match.group(2) ?? match.group(3))?.toUpperCase();
    if (numStr != null && unit != null) {
      final val = double.tryParse(numStr.replaceAll(',', '.'));
      // Changed from PlayTorrio: SourceSpec uses integer bytes; truncate the binary-unit result.
      if (val != null) {
        if (unit.startsWith('T')) {
          return (val * 1024 * 1024 * 1024 * 1024).toInt();
        }
        if (unit.startsWith('G')) return (val * 1024 * 1024 * 1024).toInt();
        if (unit.startsWith('M')) return (val * 1024 * 1024).toInt();
        if (unit.startsWith('K')) return (val * 1024).toInt();
      }
    }
  }
  return null;
}

int? seeders(String text) {
  for (final pattern in _seederPatterns) {
    final match = pattern.firstMatch(text);
    if (match != null) {
      final val = int.tryParse(match.group(1) ?? '');
      if (val != null) return val;
    }
  }
  return null;
}

int qualityRank(String text) {
  switch (quality(text)) {
    case '4K':
      return 4;
    case '1080p':
      return 3;
    case '720p':
      return 2;
    case '480p':
      return 1;
    default:
      return 0;
  }
}
