import 'dart:io';

import 'file_log_sink.dart';
import 'log_record.dart';

/// Build flag `--dart-define=GENOTV_DEBUG_LOG=true`: every logger at debug,
/// mpv at verbose, and a full log file per run. Off = behaviour unchanged.
const genotvDebugLog = bool.fromEnvironment('GENOTV_DEBUG_LOG');

/// Version + build shown in the log file name; override with
/// `--dart-define=GENOTV_APP_VERSION=...` (pubspec `version`).
const genotvAppVersion = String.fromEnvironment(
  'GENOTV_APP_VERSION',
  defaultValue: '0.1.0+1',
);

/// A sink writing one `genotv_<version>_<yyyyMMdd-HHmmss>.log` per run into
/// [directory], debug included, with a header line first.
RotatingFileLogSink debugFileLogSink(
  Directory directory, {
  required String device,
  DateTime? now,
}) {
  final t = (now ?? DateTime.now());
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp =
      '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}';
  final sink = RotatingFileLogSink(
    maxBytes: 1 << 40,
    fileName: 'genotv_${genotvAppVersion}_$stamp.log',
  );
  directory.createSync(recursive: true);
  sink.attach(directory, verbose: () => true);
  sink.write(LogRecord(
    level: LogLevel.info,
    scope: 'debuglog',
    message: 'app=$genotvAppVersion GENOTV_DEBUG_LOG=true device=$device '
        'os=${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    timestamp: t,
  ));
  return sink;
}
