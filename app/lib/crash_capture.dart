import 'dart:isolate';
import 'dart:ui';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

/// Keeps fatal persistence independent of the app logger's asynchronous queue.
class CrashCapture {
  CrashCapture(this.log, this.logger);

  final CrashLog log;
  final AppLogger logger;
  FlutterExceptionHandler? _framework;
  ErrorCallback? _dispatcher;
  RawReceivePort? _errors;
  final Set<Isolate> _isolates = {};
  bool _capturing = false;

  void capture(String origin, Object error, StackTrace stack) {
    if (_capturing) {
      Error.throwWithStackTrace(error, stack);
    }
    _capturing = true;
    try {
      log.capture(origin, error, stack);
      logger.error('$origin uncaught error', error: error, stack: stack);
    } finally {
      _capturing = false;
    }
  }

  void install() {
    if (_errors != null) throw StateError('Crash capture already installed');
    _framework = FlutterError.onError;
    _dispatcher = PlatformDispatcher.instance.onError;
    _errors = RawReceivePort((dynamic message) {
      final error = message as List<dynamic>;
      capture(
        'isolate',
        error[0] as String,
        StackTrace.fromString(error[1] as String? ?? ''),
      );
    });
    FlutterError.onError = (details) {
      capture(
        'Flutter',
        details.exception,
        details.stack ?? StackTrace.current,
      );
      _framework?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      capture('Dart', error, stack);
      return _dispatcher?.call(error, stack) ?? false;
    };
  }

  /// Attach paused child isolates before resuming to retain their fatal errors.
  void listenTo(Isolate isolate) {
    final errors = _errors;
    if (errors == null) throw StateError('Crash capture is not installed');
    if (_isolates.add(isolate)) isolate.addErrorListener(errors.sendPort);
  }

  void dispose() {
    final errors = _errors;
    if (errors == null) return;
    for (final isolate in _isolates) {
      isolate.removeErrorListener(errors.sendPort);
    }
    _isolates.clear();
    errors.close();
    _errors = null;
    FlutterError.onError = _framework;
    PlatformDispatcher.instance.onError = _dispatcher;
  }
}
