import 'package:contracts/contracts.dart';

/// Produces one redacted, copyable diagnostic snapshot.
final class DiagnosticsCollector {
  DiagnosticsCollector({required this.os, required this.appVersion});

  final String os;
  final String appVersion;
  Map<String, String> _snapshot = const {};

  Map<String, String> get snapshot => Map.unmodifiable(_snapshot);

  Map<String, String> collect({
    CapabilityReport? capabilities,
    Map<String, String> display = const {},
    Map<String, String> audio = const {},
    Map<String, String> playback = const {},
  }) {
    final merged = <String, String>{};
    if (capabilities != null) merged.addAll(capabilities.diagnostics);
    merged.addAll(display);
    merged.addAll(audio);
    merged.addAll(playback);
    _snapshot = merged.map((key, value) => MapEntry(key, _redact(value)));
    return snapshot;
  }

  String toReportText() {
    final lines = <String>['OS: $os', 'App version: $appVersion'];
    final keys = _snapshot.keys.toList()..sort();
    lines.addAll(keys.map((key) => '$key: ${_snapshot[key]}'));
    return lines.join('\n');
  }

  static String _redact(String value) {
    final uri = Uri.tryParse(value);
    if (uri != null &&
        uri.hasScheme &&
        (uri.host.isNotEmpty || uri.userInfo.isNotEmpty)) {
      final safe = uri.replace(userInfo: '', query: '', fragment: '');
      return safe.toString();
    }
    if (value.contains('/') || value.contains('\\')) {
      return value.replaceAll('\\', '/').split('/').last;
    }
    return value;
  }
}
