import 'app_logger.dart';

/// An [AppLogger] that keeps the last [capacity] records in memory instead
/// of writing them anywhere. Every Part's tests use this to assert that a
/// failure was logged — the "no swallowed errors" rule is only testable
/// with it.
///
/// A [scoped] child shares the same backing list as its parent, so a test
/// holding the root logger sees records logged through any of its children.
class MemoryLogger implements AppLogger {
  MemoryLogger({this.capacity = 200})
      : _scope = 'app',
        _records = <LogRecord>[];

  MemoryLogger._child(this.capacity, this._scope, this._records);

  final int capacity;
  final String _scope;
  final List<LogRecord> _records;

  /// Records logged so far, oldest first, capped at [capacity].
  List<LogRecord> get records => List.unmodifiable(_records);

  void _emit(
    LogLevel level,
    String message, {
    Object? data,
    Object? error,
    StackTrace? stack,
  }) {
    _records.add(LogRecord(
      level: level,
      scope: _scope,
      message: message,
      timestamp: DateTime.now(),
      data: data,
      error: error,
      stack: stack,
    ));
    if (_records.length > capacity) _records.removeAt(0);
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
  AppLogger scoped(String name) =>
      MemoryLogger._child(capacity, '$_scope.$name', _records);
}
