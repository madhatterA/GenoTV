import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../focus/focusable_action.dart';
import '../l10n/app_text.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/app_haptics.dart';
import '../theme/rivulet_tokens.dart';
import 'tinted_surface.dart';

/// A filter chip (DESIGN_SPEC §9.7): `tintFill`, `full` radius (capsule); selected is
/// an `accent` fill with `onAccent` text.
class AppChip extends StatelessWidget {
  const AppChip({
    required this.label,
    this.selected = false,
    this.icon,
    this.onActivate,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  final String label;
  final bool selected;

  /// Optional leading glyph (the sort chip's `sortAscending`).
  final IconData? icon;

  /// Null disables the chip.
  final VoidCallback? onActivate;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final colors = tokens.colors;
    final ff = AdaptiveBehavior.formFactorOf(context);
    final radius = BorderRadius.circular(RivuletRadius.full);
    // Selected = fill + check; focus = ring only (never the same signal).
    final glyph = icon ?? (selected ? PhosphorIconsBold.check : null);
    final foreground = selected ? colors.onAccent : colors.textPrimary;
    final text = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: RivuletControlSize.s.horizontalPadding(ff),
      ),
      child: Center(
        widthFactor: 1,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (glyph != null) ...<Widget>[
              Icon(glyph, size: RivuletControlSize.s.glyph(ff), color: foreground),
              SizedBox(width: RivuletControlSize.s.iconGap(ff)),
            ],
            Flexible(
              child: AppText(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.typeStyles.label.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
    return FocusableAction(
      onActivate: onActivate == null
          ? null
          : () {
              AppHaptics.selection(context);
              onActivate!();
            },
      enabled: onActivate != null,
      focusNode: focusNode,
      autofocus: autofocus,
      semanticLabel: label,
      minSize: AdaptiveBehavior.hitTargetOf(context),
      centered: true,
      focusRadius: radius,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: RivuletControlSize.s.height(ff),
        ),
        child: selected
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: radius,
                ),
                child: text,
              )
            : TintedSurface(radius: RivuletRadius.full, child: text),
      ),
    );
  }
}
