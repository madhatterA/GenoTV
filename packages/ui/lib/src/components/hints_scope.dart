import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/rivulet_tokens.dart';
import 'app_toast.dart';

/// Remembers which one-time hints were shown. The app backs it with its settings
/// store (values not listed in Settings); without a scope hints never show.
class HintsScope extends InheritedWidget {
  const HintsScope({
    required this.seen,
    required this.markSeen,
    required super.child,
    super.key,
  });

  final bool Function(String id) seen;
  final void Function(String id) markSeen;

  static HintsScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HintsScope>();

  @override
  bool updateShouldNotify(HintsScope oldWidget) => false;
}

/// Shows [text] as a 5 s toast the first time [id] is requested, then never
/// again. Runs after the frame, and waits (without using the hint up) while
/// another toast is showing.
void showHintOnce(BuildContext context, String id, String text) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    final scope = HintsScope.maybeOf(context);
    if (scope == null || scope.seen(id) || appToastActive) return;
    scope.markSeen(id);
    showAppToast(
      context,
      PhosphorIconsRegular.lightbulb,
      text,
      duration: RivuletMotion.toastLong,
    );
  });
}
