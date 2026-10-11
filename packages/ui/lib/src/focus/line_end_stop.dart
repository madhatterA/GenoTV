import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

/// Keeps Right on the line (DESIGN_SPEC §6.4 rules 1 and 3): while [active],
/// Right pressed on [child] (the last item of a row or grid line) does
/// nothing instead of jumping to the nearest focusable elsewhere on screen.
class LineEndStop extends StatelessWidget {
  const LineEndStop({required this.active, required this.child, super.key});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (_, event) =>
        active &&
            event is! KeyUpEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowRight
        ? KeyEventResult.handled
        : KeyEventResult.ignored,
    child: child,
  );
}
