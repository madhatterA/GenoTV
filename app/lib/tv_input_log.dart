import 'package:core/core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:ui/ui.dart' show SiriRemote;

/// GENOTV_DEBUG_LOG only: every raw key, pointer, Siri touch and focus change
/// the app receives, so the real remote's behaviour is read from the log.
void logTvInput(AppLogger logger, SiriRemote remote) {
  final log = logger.scoped('tvinput');
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  log.debug(
    'view size=${view.physicalSize} dpr=${view.devicePixelRatio} '
    'padding=${view.padding.top}/${view.padding.left}/${view.padding.bottom}/${view.padding.right}',
  );
  HardwareKeyboard.instance.addHandler((KeyEvent e) {
    log.debug(
      'key ${e.runtimeType} logical=${e.logicalKey.keyLabel.isEmpty ? e.logicalKey.debugName : e.logicalKey.keyLabel}'
      ' (0x${e.logicalKey.keyId.toRadixString(16)}) physical=${e.physicalKey.debugName}',
    );
    return false;
  });
  GestureBinding.instance.pointerRouter.addGlobalRoute((PointerEvent e) {
    if (e is PointerHoverEvent) return;
    log.debug('pointer ${e.runtimeType} kind=${e.kind} pos=${e.position}');
  });
  remote.touches.listen(
    (t) => log.debug('siri touch ${t.phase} x=${t.x.toStringAsFixed(2)} y=${t.y.toStringAsFixed(2)}'),
  );
  FocusManager.instance.addListener(() {
    final node = FocusManager.instance.primaryFocus;
    log.debug(
      'focus -> ${node?.debugLabel ?? node.runtimeType} '
      'rect=${node is FocusScopeNode || node == null ? '-' : _ltrb(node.rect)} '
      'owner=${node?.context?.widget.runtimeType}',
    );
  });
}

String _ltrb(Rect r) =>
    '${r.left.round()},${r.top.round()},${r.right.round()},${r.bottom.round()}';
