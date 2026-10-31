import 'dart:convert';
import 'dart:io';

import 'console_logger.dart';
import 'log_record.dart';

/// Crash-only synchronous persistence; ordinary app logging stays asynchronous.
class CrashLog {
  CrashLog(this.directory, {this.maxBytes = 5 * 1024 * 1024}) {
    if (maxBytes < 128) throw ArgumentError.value(maxBytes, 'maxBytes');
    directory.createSync(recursive: true);
    _logger = ConsoleLogger(scope: 'crash', sink: _write);
    var crashed = _marker.existsSync();
    final native = File(nativePendingPath);
    if (native.existsSync() && native.lengthSync() > 0) {
      final handle = native.openSync();
      late final String record;
      try {
        record = utf8.decode(handle.readSync(maxBytes), allowMalformed: true);
      } finally {
        handle.closeSync();
      }
      _logger.error('native fatal crash', error: record);
      crashed = true;
      native.deleteSync();
    }
    previousCrash = crashed;
    if (_marker.existsSync()) _marker.deleteSync();
  }

  final Directory directory;
  final int maxBytes;
  late final ConsoleLogger _logger;
  late final bool previousCrash;
  File get _file => File('${directory.path}${Platform.pathSeparator}crash.log');
  File get _rotated =>
      File('${directory.path}${Platform.pathSeparator}crash.1.log');
  File get _marker =>
      File('${directory.path}${Platform.pathSeparator}dart.pending');
  String get nativePendingPath =>
      '${directory.path}${Platform.pathSeparator}native.pending';

  void capture(String origin, Object error, StackTrace stack) {
    _logger.error('$origin uncaught error', error: error, stack: stack);
    _marker.writeAsStringSync('crash\n', flush: true);
  }

  void _write(LogRecord record) {
    final text =
        '${record.timestamp.toIso8601String()} ERROR ${record.scope}: '
        '${record.message} error=${record.error}\n${record.stack ?? ''}\n';
    final encoded = utf8.encode(text);
    var end = encoded.length;
    if (end > maxBytes) {
      end = maxBytes;
      // Keep the last UTF-8 code point whole so exported logs remain readable.
      while (end > 0 && (encoded[end] & 0xc0) == 0x80) {
        end--;
      }
    }
    final bytes = encoded.sublist(0, end);
    if (_file.existsSync() && _file.lengthSync() + bytes.length > maxBytes) {
      if (_rotated.existsSync()) _rotated.deleteSync();
      _file.renameSync(_rotated.path);
    }
    _file.writeAsBytesSync(bytes, mode: FileMode.append, flush: true);
  }

  String readLogs() => [
    for (final file in [_rotated, _file])
      if (file.existsSync()) file.readAsStringSync(),
  ].join('\n');
}
