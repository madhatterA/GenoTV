import 'package:flutter/widgets.dart';

import '../l10n/app_text.dart' show isFarsi;
import '../platform/adaptive_behavior.dart';
import '../theme/rivulet_tokens.dart';
import 'app_shell.dart';

/// The page top content inset (DESIGN_SPEC §4.3): the space a non-hero page
/// leaves above its content for the floating menu pill row. Phone adds the
/// top safe area. Hero pages (Home, Movie/Series detail, Play source) start
/// at y = 0 and do not use it.
double pageTopInsetOf(BuildContext context) {
  final formFactor = AdaptiveBehavior.formFactorOf(context);
  return RivuletSpacing.contentTop(formFactor) +
      MediaQuery.paddingOf(context).top;
}

/// Where the menu pill sits (or would sit, when a page is shown without the
/// shell, e.g. in tests): headers and the back button align to it.
Rect menuSlotOf(BuildContext context) {
  final pill = AppShellScope.pillRectOf(context);
  if (pill != Rect.zero) return pill;
  final formFactor = AdaptiveBehavior.formFactorOf(context);
  return Rect.fromLTWH(
    RivuletSpacing.gutterOf(context) + menuPillShiftOf(context),
    MediaQuery.paddingOf(context).top + RivuletSpacing.controlTop(formFactor),
    0,
    AdaptiveBehavior.sizesOf(context).menuPillHeight,
  );
}

/// Width the pill gives up on the left on a page that has a back button: the
/// icon-button size plus an 8 px gap. Order on screen: back, then pill.
double menuBackSlotOf(BuildContext context) =>
    AdaptiveBehavior.sizesOf(context).iconButton + RivuletSpacing.s8;

/// How far the pill steps right for a back button: none in Farsi, where the
/// back button sits on the right edge instead.
double menuPillShiftOf(BuildContext context) =>
    isFarsi(context) ? 0 : menuBackSlotOf(context);
