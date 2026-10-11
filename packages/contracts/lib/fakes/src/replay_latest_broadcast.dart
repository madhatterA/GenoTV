import 'dart:async';

/// Replays the latest added value to every new listener of a broadcast
/// stream — without it, a subscriber attaching one frame late sees an
/// empty state forever (the number-one cause of "the UI shows loading
/// forever").
class ReplayLatestBroadcast<T> {
  final StreamController<T> _controller = StreamController<T>.broadcast();
  T? _latest;
  bool _hasValue = false;

  void add(T value) {
    _latest = value;
    _hasValue = true;
    if (!_controller.isClosed) _controller.add(value);
  }

  bool get hasValue => _hasValue;
  T get latest => _latest as T;

  /// Drops the cached value so a subscriber after [close] gets nothing,
  /// not a stale replay.
  void clear() => _hasValue = false;

  Stream<T> get stream async* {
    if (_hasValue) yield _latest as T;
    yield* _controller.stream;
  }

  Future<void> close() => _controller.close();
}
