/// Severity of a [LogRecord].
enum LogLevel { debug, info, warn, error }

/// A single structured log entry.
class LogRecord {
  LogRecord({
    required this.level,
    required this.scope,
    required this.message,
    required this.timestamp,
    this.data,
    this.error,
    this.stack,
  });

  final LogLevel level;
  final String scope;
  final String message;
  final DateTime timestamp;
  final Object? data;
  final Object? error;
  final StackTrace? stack;

  @override
  String toString() =>
      '[$level] $scope: $message'
      '${data != null ? ' data=$data' : ''}'
      '${error != null ? ' error=$error' : ''}';
}
