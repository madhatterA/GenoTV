import '../logging/app_logger.dart';
import 'app_failure.dart';

/// The one-line path that makes surfacing a failure cheaper than swallowing
/// it. Scopes the record under the failure's own code, so failures are
/// filterable by code wherever the logger's records end up.
extension FailureLogging on AppLogger {
  void failure(AppFailure f) {
    scoped(f.code).error(f.message, error: f, stack: f.stack);
  }
}
