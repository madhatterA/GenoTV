import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/services.dart';

const _logcat = MethodChannel('com.genotv.video_player/log');

void writeAndroidLog(LogRecord record) {
  if (!Platform.isAndroid || record.level == LogLevel.debug && !genotvDebugLog) return;
  final priority = record.level.index + 3;
  assert(priority >= 3 && priority <= 6);
  unawaited(
    _logcat
        .invokeMethod<void>('write', {
          'priority': priority,
          'message': record.toString(),
        })
        .catchError((Object error, StackTrace stack) {
          ConsoleLogger.developerSink(
            LogRecord(
              level: LogLevel.error,
              scope: 'app.androidLog',
              message: 'Logcat delivery failed',
              timestamp: DateTime.now(),
              error: error,
              stack: stack,
            ),
          );
        }),
  );
}

/// Debug-log build only: the app's external files dir (adb-pullable without
/// root) and a one-line device description; null off Android.
Future<({Directory logs, String device})?> androidDebugInfo() async {
  if (!Platform.isAndroid) return null;
  final info = await _logcat.invokeMapMethod<String, String>('debugInfo');
  final dir = info?['logDir'];
  if (dir == null) return null;
  return (
    logs: Directory('$dir${Platform.pathSeparator}logs'),
    device: info?['device'] ?? '',
  );
}
