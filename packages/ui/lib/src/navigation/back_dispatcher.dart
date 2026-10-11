import 'package:flutter/foundation.dart';

typedef BackHandler = bool Function();

final class BackDispatcher {
  final List<BackHandler> _handlers = <BackHandler>[];

  VoidCallback register(BackHandler handler) {
    _handlers.add(handler);
    return () => _handlers.remove(handler);
  }

  bool dispatch() {
    if (_handlers.isEmpty) return false;
    return _handlers.last();
  }
}
