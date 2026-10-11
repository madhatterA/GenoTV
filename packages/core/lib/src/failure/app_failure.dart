import 'failure_codes.dart';

export 'failure_codes.dart';

/// Failures are values, not strings — every Part extends this with its own
/// leaves. See `planning/CONTRACTS.md` §0.
///
/// Shape: `abstract base class`, not `sealed`. A `sealed` hierarchy restricts
/// every direct subtype to this file's own library, which would stop each
/// Part from adding a leaf inside its own package. `base` still forces every
/// subtype to be declared via `extends` (never `implements`), so this
/// class's invariants — the constructor always runs, `code` and `message`
/// are always set — hold for every leaf, wherever it lives.
abstract base class AppFailure {
  const AppFailure({
    required this.code,
    required this.message,
    this.cause,
    this.stack,
  });

  /// Stable, machine-readable: e.g. `'transport.range.unsatisfiable'`.
  final String code;

  /// Developer-facing.
  final String message;
  final Object? cause;
  final StackTrace? stack;

  @override
  String toString() =>
      cause == null ? '$code: $message' : '$code: $message ($cause)';
}

/// A failure with no more specific leaf to reach for. Prefer a Part-owned
/// leaf; this exists for the boundary code that cannot yet know which.
final class UnexpectedFailure extends AppFailure {
  const UnexpectedFailure({required super.cause, super.stack})
      : super(
          code: FailureCodes.appUnexpected,
          message: 'An unexpected error occurred',
        );
}

/// An operation was cancelled rather than failed.
final class CancelledFailure extends AppFailure {
  const CancelledFailure({super.message = 'Operation was cancelled'})
      : super(code: FailureCodes.appCancelled);
}
