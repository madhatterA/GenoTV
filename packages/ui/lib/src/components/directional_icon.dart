import 'package:flutter/widgets.dart';

import '../l10n/app_text.dart';

/// An [Icon] whose arrow/chevron points the reading direction: mirrored in
/// Farsi, unchanged in English. Layout stays LTR (Part 07 p17); never use it
/// for media transport or physical scroll arrows.
class DirectionalIcon extends StatelessWidget {
  const DirectionalIcon(this.icon, {this.size, this.color, super.key});

  final IconData icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final child = Icon(icon, size: size, color: color);
    return isFarsi(context) ? Transform.flip(flipX: true, child: child) : child;
  }
}
