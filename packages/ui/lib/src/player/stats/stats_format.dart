/// Shown in place of any value that is not known at this moment.
const String statsUnknown = '—';

String formatBytes(num? bytes) {
  if (bytes == null || bytes < 0) return statsUnknown;
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return unit == 0
      ? '${value.round()} B'
      : '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
}

String formatSpeed(num? bytesPerSecond) =>
    bytesPerSecond == null ? statsUnknown : '${formatBytes(bytesPerSecond)}/s';

/// "m:ss" or "h:mm:ss"; unknown for null.
String formatEta(Duration? left) {
  if (left == null || left.isNegative) return statsUnknown;
  final h = left.inHours;
  final m = left.inMinutes % 60;
  final s = left.inSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${left.inMinutes}:${two(s)}';
}

/// "12.3 MB / 1.2 GB (1%)"; the total and percent are unknown without a size.
String formatProgress(int downloaded, int? total) {
  if (total == null || total <= 0) {
    return '${formatBytes(downloaded)} / $statsUnknown';
  }
  final percent = (downloaded * 100 / total).clamp(0, 100);
  return '${formatBytes(downloaded)} / ${formatBytes(total)} '
      '(${percent.toStringAsFixed(percent < 10 ? 1 : 0)}%)';
}

String formatCount(int? value) => value == null ? statsUnknown : '$value';

/// mpv codec text like "h264 ((null))" -> "h264".
String formatCodec(String? raw) {
  if (raw == null || raw.isEmpty) return statsUnknown;
  final cut = raw.indexOf(' (');
  return cut < 0 ? raw : raw.substring(0, cut);
}

/// Bits per colour component read from an FFmpeg pixel-format name:
/// `yuv420p10le` -> 10; a name without a depth suffix (`yuv420p`, `nv12`) is
/// 8-bit by FFmpeg's naming rule.
int? bitDepthOfPixelFormat(String? name) {
  if (name == null || name.isEmpty) return null;
  final suffixed = RegExp(r'(\d+)(?:le|be)$').firstMatch(name);
  if (suffixed != null) {
    final depth = int.parse(suffixed.group(1)!);
    if (depth >= 9 && depth <= 16) return depth;
  }
  return RegExp(r'^(yuv|nv|gray|rgb|bgr)').hasMatch(name) ? 8 : null;
}

String shortInfoHash(String hash) => hash.length <= 16
    ? hash
    : '${hash.substring(0, 8)}…${hash.substring(hash.length - 6)}';
