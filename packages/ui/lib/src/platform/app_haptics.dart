import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'adaptive_behavior.dart';
import 'form_factor.dart';

/// Light haptic ticks, phone only (Part 07 phase 05). Desktop and TV no-op.
class AppHaptics {
  const AppHaptics._();

  /// A toggle or chip change.
  static void selection(BuildContext context) {
    if (_phone(context)) HapticFeedback.selectionClick();
  }

  /// A long-press menu, double-tap seek or skip-marker snap.
  static void light(BuildContext context) {
    if (_phone(context)) HapticFeedback.lightImpact();
  }

  static bool _phone(BuildContext context) =>
      AdaptiveBehavior.formFactorOf(context) == FormFactor.phone;
}
