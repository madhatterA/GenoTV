import 'package:flutter/material.dart';
import 'package:flutter_thinking_orbs/flutter_thinking_orbs.dart';

import '../accessibility/ui_accessibility.dart';

/// The only spinner (DESIGN_SPEC §9.9): flutter_thinking_orbs' dotted orb
/// (owner 2026-10-10). It pauses itself when its route is inactive
/// (`TickerMode`, P11) and shows a static frame under reduced motion.
class OrbLoader extends StatelessWidget {
  const OrbLoader.small({super.key, this.state = OrbState.working}) : size = 24;
  const OrbLoader.medium({super.key, this.state = OrbState.working})
    : size = 48;
  const OrbLoader.large({super.key, this.state = OrbState.working}) : size = 72;

  final double size;
  final OrbState state;

  /// The package animates from a real-time clock, so goldens would catch a
  /// random frame; tests show its fixed reduced-motion frame instead.
  @visibleForTesting
  static bool staticFrame = false;

  @override
  Widget build(BuildContext context) {
    final orb = ThinkingOrb(
      state: state,
      size: size,
      semanticLabel: UiAccessibility.labelsOf(context).loading,
    );
    return RepaintBoundary(
      child: staticFrame
          ? MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: orb,
            )
          : orb,
    );
  }
}
