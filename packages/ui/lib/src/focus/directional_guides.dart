import 'package:flutter/widgets.dart';

/// Keeps a row's left/right order explicit instead of relying on geometric nearest focus.
class DirectionalFocusGuide extends StatelessWidget {
  const DirectionalFocusGuide({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      FocusTraversalGroup(policy: OrderedTraversalPolicy(), child: child);
}
