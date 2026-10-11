import 'package:contracts/contracts.dart';

String? parseQuality(String? value) {
  if (value == null) return null;
  if (RegExp(r'\b(4k|uhd)\b', caseSensitive: false).hasMatch(value)) {
    return '2160p';
  }
  final match = RegExp(
    r'(?<!\d)(4320|2160|1440|1080|720|576|480|360|240)p?',
    caseSensitive: false,
  ).firstMatch(value);
  return match == null ? null : '${match[1]}p';
}

int? parseSizeBytes(Object? value) {
  if (value is int) return value >= 0 ? value : null;
  if (value is! String) return null;
  final text = value.replaceAll(',', '').trim();
  final plain = int.tryParse(text);
  if (plain != null) return plain >= 0 ? plain : null;
  final match = RegExp(
    r'^(\d+(?:\.\d+)?)\s*(B|KB|MB|GB|TB)$',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return null;
  final power = ['B', 'KB', 'MB', 'GB', 'TB'].indexOf(match[2]!.toUpperCase());
  return (double.parse(match[1]!) *
          [1, 1024, 1048576, 1073741824, 1099511627776][power])
      .round();
}

List<SourceSpec> orderStreams(Iterable<SourceSpec> specs) {
  final result = specs.toList();
  result.sort((a, b) {
    if (a.kind == SourceKind.hlsUrl && b.kind != SourceKind.hlsUrl) return -1;
    if (b.kind == SourceKind.hlsUrl && a.kind != SourceKind.hlsUrl) return 1;
    if (a.kind == SourceKind.hlsUrl) return 0;
    final quality = (int.tryParse(b.quality?.replaceAll('p', '') ?? '') ?? -1)
        .compareTo(int.tryParse(a.quality?.replaceAll('p', '') ?? '') ?? -1);
    return quality != 0
        ? quality
        : (b.expectedBytes ?? -1).compareTo(a.expectedBytes ?? -1);
  });
  return result;
}
