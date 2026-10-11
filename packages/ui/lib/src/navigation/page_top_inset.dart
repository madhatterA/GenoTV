import 'package:flutter/widgets.dart';

import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../theme/rivulet_tokens.dart';
import 'app_shell.dart';

/// The page top content inset (DESIGN_SPEC §4.3): the space a non-hero page
/// leaves above its content for the floating menu pill row. Phone adds the
/// top safe area. Hero pages (Home, Movie/Series detail, Play source) start
/// at y = 0 and do not use it.
double pageTopInsetOf(BuildContext context) {
  final formFactor = AdaptiveBehavior.of(context).formFactor;
  return RivuletSpacing.topInset(formFactor) +
      (formFactor == FormFactor.phone ? MediaQuery.paddingOf(context).top : 0);
}

/// Where the menu pill sits (or would sit, when a page is shown without the
/// shell, e.g. in tests): headers and the back button align to it.
Rect menuSlotOf(BuildContext context) {
  final pill = AppShellScope.pillRectOf(context);
  if (pill != Rect.zero) return pill;
  final formFactor = AdaptiveBehavior.of(context).formFactor;
  return Rect.fromLTWH(
    RivuletSpacing.gutter(formFactor) + menuBackSlotOf(context),
    MediaQuery.paddingOf(context).top + 12,
    0,
    AdaptiveBehavior.sizesOf(context).menuPillHeight,
  );
}

/// Width the pill gives up on the left on a page that has a back button: the
/// icon-button size plus an 8 px gap. Order on screen: back, then pill.
double menuBackSlotOf(BuildContext context) =>
    AdaptiveBehavior.sizesOf(context).iconButton + RivuletSpacing.s8;
