import 'package:flutter/foundation.dart';

typedef BackHandler = bool Function();

/// Notifies when the first handler registers or the last one leaves.
final class BackDispatcher extends ChangeNotifier {
  final List<BackHandler> _handlers = <BackHandler>[];

  VoidCallback register(BackHandler handler) {
    _handlers.add(handler);
    notifyListeners();
    return () {
      if (_handlers.remove(handler)) notifyListeners();
    };
  }

  bool get hasHandlers => _handlers.isNotEmpty;

  bool dispatch() {
    if (_handlers.isEmpty) return false;
    return _handlers.last();
  }
}
