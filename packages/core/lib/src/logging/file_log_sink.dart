import 'dart:io';

import 'log_record.dart';

/// Appends records to `app.log` in a directory, keeping the last two files of
/// up to [maxBytes] each (`app.log`, `app.1.log`). Info and above are always
/// written; debug records only while [verbose] returns true. Records logged
/// before [attach] are held and written when the directory is known. Writes
/// are queued and appended asynchronously; [flush] waits for them.
class RotatingFileLogSink {
  RotatingFileLogSink({this.maxBytes = 5 * 1024 * 1024});

  final int maxBytes;
  bool Function() verbose = () => false;
  File? _file;
  int _size = 0;
  bool _reported = false;
  final List<LogRecord> _early = [];
  final List<String> _queue = [];
  bool _scheduled = false;
  Future<void> _tail = Future<void>.value();

  /// The folder the log files live in; null until [attach].
  Directory? get directory => _file?.parent;

  void attach(Directory directory, {required bool Function() verbose}) {
    this.verbose = verbose;
    final file = File('${directory.path}${Platform.pathSeparator}app.log');
    _size = file.existsSync() ? file.lengthSync() : 0;
    _file = file;
    final early = List<LogRecord>.of(_early);
    _early.clear();
    early.forEach(write);
  }

  void write(LogRecord record) {
    if (record.level == LogLevel.debug && !verbose()) return;
    final file = _file;
    if (file == null) {
      if (_early.length < 500) _early.add(record);
      return;
    }
    final line = StringBuffer(
      '${record.timestamp.toIso8601String()} ${record.level.name.toUpperCase()} '
      '${record.scope}: ${record.message}',
    );
    if (record.data != null) line.write(' data=${record.data}');
    if (record.error != null) line.write(' error=${record.error}');
    line.writeln();
    if (record.stack != null) line.writeln(record.stack);
    _queue.add(line.toString());
    // Never touch the disk on the caller's turn: a synchronous append blocks
    // the UI isolate, and a block of ~100 ms while TLS handshakes are in
    // flight stalls them for good on Windows (bug_history 2026-10-09).
    if (!_scheduled) {
      _scheduled = true;
      _tail = _tail.then((_) => Future<void>.delayed(Duration.zero)).then((_) => _drain());
    }
  }

  /// Completes once every record logged so far is on disk.
  Future<void> flush() => _tail;

  Future<void> _drain() async {
    _scheduled = false;
    final file = _file;
    if (file == null) return;
    final batch = List<String>.of(_queue);
    _queue.clear();
    // A logger must never throw into the code that is logging (EMFILE, disk
    // full, folder removed): report the first failure on stderr, keep going.
    try {
      final chunk = StringBuffer();
      Future<void> append() async {
        if (chunk.isEmpty) return;
        await file.writeAsString(chunk.toString(), mode: FileMode.append, flush: true);
        chunk.clear();
      }

      for (final text in batch) {
        if (_size + text.length > maxBytes) {
          await append();
          await file.rename(
            '${file.parent.path}${Platform.pathSeparator}app.1.log',
          );
          _size = 0;
        }
        chunk.write(text);
        _size += text.length;
      }
      await append();
    } on FileSystemException catch (e) {
      if (!_reported) {
        _reported = true;
        stderr.writeln('log file write failed (reported once): $e');
      }
    }
  }
}
