import 'dart:developer' as developer;

import 'app_logger.dart';

/// Where a [LogRecord] goes once it clears the minimum level.
typedef LogSink = void Function(LogRecord record);

/// Default [AppLogger] implementation. Despite the name, its default sink
/// writes through `dart:developer`'s `log()`, not stdout — that keeps
/// records structured (visible in DevTools' Logging view) and out of
/// release-build stdout, unlike `print`.
///
/// `dart:developer` `log()` truncates very long messages on some platforms;
/// this is not worked around here until something is actually truncated
/// (see phase-01-logging.md "Pitfalls").
class ConsoleLogger implements AppLogger {
  ConsoleLogger({
    this.minimumLevel = LogLevel.debug,
    LogSink? sink,
    this.scope = 'app',
  }) : _sink = sink ?? developerSink;

  final LogLevel minimumLevel;
  final LogSink _sink;
  final String scope;

  /// The default sink; public so an app can add a file sink beside it.
  static void developerSink(LogRecord record) {
    developer.log(
      record.message,
      time: record.timestamp,
      level: _levelToSeverity(record.level),
      name: record.scope,
      error: record.error,
      stackTrace: record.stack,
    );
  }

  // Maps onto package:logging's Level scale, which dart:developer log()'s
  // `level` documents itself against.
  static int _levelToSeverity(LogLevel level) => switch (level) {
        LogLevel.debug => 500,
        LogLevel.info => 800,
        LogLevel.warn => 900,
        LogLevel.error => 1000,
      };

  void _emit(
    LogLevel level,
    String message, {
    Object? data,
    Object? error,
    StackTrace? stack,
  }) {
    if (level.index < minimumLevel.index) return;
    _sink(LogRecord(
      level: level,
      scope: scope,
      message: message,
      timestamp: DateTime.now(),
      data: data,
      error: error,
      stack: stack,
    ));
  }

  @override
  void debug(String message, {Object? data}) =>
      _emit(LogLevel.debug, message, data: data);

  @override
  void info(String message, {Object? data}) =>
      _emit(LogLevel.info, message, data: data);

  @override
  void warn(String message, {Object? error, StackTrace? stack}) =>
      _emit(LogLevel.warn, message, error: error, stack: stack);

  @override
  void error(String message, {required Object error, StackTrace? stack}) =>
      _emit(LogLevel.error, message, error: error, stack: stack ?? StackTrace.current);

  @override
  AppLogger scoped(String name) => ConsoleLogger(
        minimumLevel: minimumLevel,
        sink: _sink,
        scope: '$scope.$name',
      );
}
