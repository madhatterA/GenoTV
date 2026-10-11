import 'dart:async';

/// Coalesces rapid scrub requests into one in-flight engine command plus the
/// newest pending target. The final request is always issued.
final class SeekCoalescer {
  SeekCoalescer({
    required this.issue,
    this.epsilon = const Duration(milliseconds: 250),
  });

  final Future<void> Function(Duration target) issue;
  final Duration epsilon;
  Duration? _inFlight;
  Duration? _pending;
  final _waiters = <Completer<void>>[];

  Future<void> request(Duration target) {
    final current = _inFlight;
    final pending = _pending;
    if ((current != null && _near(current, target)) ||
        (pending != null && _near(pending, target))) {
      return Future<void>.value();
    }
    final completion = Completer<void>();
    _waiters.add(completion);
    if (current == null) {
      unawaited(_run(target));
    } else {
      _pending = target;
    }
    return completion.future;
  }

  bool _near(Duration a, Duration b) => (a - b).abs() <= epsilon;

  Future<void> _run(Duration target) async {
    _inFlight = target;
    Object? error;
    StackTrace? stack;
    try {
      await issue(target);
    } catch (e, s) {
      error = e;
      stack = s;
    }
    _inFlight = null;
    final next = _pending;
    _pending = null;
    if (next != null) {
      await _run(next);
      return;
    }
    final waiters = List<Completer<void>>.from(_waiters);
    _waiters.clear();
    for (final waiter in waiters) {
      if (error != null) {
        waiter.completeError(error, stack!);
      } else {
        waiter.complete();
      }
    }
  }
}
