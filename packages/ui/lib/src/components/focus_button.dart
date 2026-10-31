import 'package:flutter/material.dart';

import '../focus/focusable_action.dart';
import '../l10n/app_text.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../theme/rivulet_tokens.dart';

/// Layout shape for a [FocusButton]. Each variant keeps a fixed box size
/// across normal/focused/pressed/disabled states — [FocusableAction]
/// already guarantees this by scaling as a paint transform rather than a
/// resize, so a variant only needs to hand it a fixed-size child.
import 'tinted_surface.dart';

enum FocusButtonVariant { pill, circle, icon, row }

/// A glass-styled activatable control in one of four Rivulet shapes:
///  - [FocusButtonVariant.pill] — a tier-L label capsule, at least 4 x L wide.
///  - [FocusButtonVariant.circle] — the tier-L icon-only circle.
///  - [FocusButtonVariant.icon] — a bare tier-M icon button.
///  - [FocusButtonVariant.row] — a full-width glass row (icon + label),
///    used by settings/list-style actions.
///
/// Activation (Select key, Enter, tap, or click) is forwarded verbatim to
/// [onActivate] — the same single entry point [FocusableAction] already
/// funnels every input source through, so this widget adds no second
/// activation path for the command pipeline to reconcile.
class FocusButton extends StatelessWidget {
  const FocusButton({
    required this.variant,
    this.onActivate,
    this.icon,
    this.label,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
    this.semanticLabel,
    super.key,
  }) : assert(
         icon != null || label != null,
         'FocusButton needs an icon, a label, or both.',
       );

  final FocusButtonVariant variant;
  final VoidCallback? onActivate;
  final IconData? icon;
  final String? label;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final colors = tokens.colors;
    final ff = AdaptiveBehavior.formFactorOf(context);
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 14;
    final l = RivuletControlSize.l.height(ff);
    final m = RivuletControlSize.m.height(ff);

    final Widget shaped;
    final BorderRadius focusRadius;
    switch (variant) {
      case FocusButtonVariant.pill:
        focusRadius = BorderRadius.circular(RivuletRadius.full);
        shaped = _glass(
          focusRadius,
          Container(
            constraints: BoxConstraints(minHeight: l, minWidth: 4 * l),
            padding: EdgeInsets.symmetric(
              horizontal: RivuletControlSize.l.horizontalPadding(ff),
              vertical: largeText ? RivuletSpacing.s8 : 0,
            ),
            child: Center(child: _content(colors, ff, RivuletControlSize.l)),
          ),
        );
      case FocusButtonVariant.circle:
        focusRadius = BorderRadius.circular(RivuletRadius.full);
        shaped = _glass(
          focusRadius,
          SizedBox(
            width: l,
            height: l,
            child: Center(
              child: _content(colors, ff, RivuletControlSize.l, label: false),
            ),
          ),
        );
      case FocusButtonVariant.icon:
        focusRadius = BorderRadius.circular(RivuletRadius.full);
        shaped = SizedBox(
          width: m,
          height: m,
          child: Center(
            child: _content(colors, ff, RivuletControlSize.m, label: false),
          ),
        );
      case FocusButtonVariant.row:
        focusRadius = BorderRadius.circular(RivuletRadius.medium);
        shaped = _glass(
          focusRadius,
          Container(
            constraints: const BoxConstraints(minHeight: 56),
            width: double.infinity,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: RivuletSpacing.s16,
                vertical: largeText ? RivuletSpacing.s12 : 0,
              ),
              child: _content(
                colors,
                ff,
                RivuletControlSize.m,
                expand: true,
              ),
            ),
          ),
        );
    }

    return FocusableAction(
      onActivate: onActivate,
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled,
      semanticLabel: semanticLabel ?? label,
      focusRadius: focusRadius,
      child: shaped,
    );
  }

  Widget _glass(BorderRadius radius, Widget child) =>
      TintedSurface.overMedia(radius: radius.topLeft.x, child: child);

  Widget _content(
    RivuletColors colors,
    FormFactor ff,
    RivuletControlSize tier, {
    bool label = true,
    bool expand = false,
  }) {
    final withLabel = label;
    final iconWidget = icon == null
        ? null
        : Icon(icon, color: colors.textPrimary, size: tier.glyph(ff));
    if (!withLabel || this.label == null) {
      return iconWidget ?? const SizedBox.shrink();
    }
    final text = AppText(
      this.label!,
      style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
    );
    if (iconWidget == null) {
      return expand
          ? Align(alignment: AlignmentDirectional.centerStart, child: text)
          : text;
    }
    return Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        iconWidget,
        SizedBox(width: tier.iconGap(ff)),
        Flexible(child: text),
      ],
    );
  }
}
