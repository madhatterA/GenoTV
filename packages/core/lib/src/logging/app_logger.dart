export 'log_record.dart';

/// Logging surface every Part logs through. No `print`, no `debugPrint`,
/// anywhere in the app — see `planning/CONTRACTS.md` §0.
///
/// No global singleton: pass an [AppLogger] by constructor argument
/// (`planning/CONTRACTS.md` §7).
abstract interface class AppLogger {
  void debug(String message, {Object? data});
  void info(String message, {Object? data});
  void warn(String message, {Object? error, StackTrace? stack});
  void error(String message, {required Object error, StackTrace? stack});

  /// Returns a child logger whose records carry `parent.child` as scope.
  AppLogger scoped(String name);
}
