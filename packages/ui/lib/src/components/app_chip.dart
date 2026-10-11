import 'package:flutter/material.dart';

import '../focus/focusable_action.dart';
import '../l10n/app_text.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../theme/rivulet_tokens.dart';
import 'tinted_surface.dart';

/// A filter chip (DESIGN_SPEC §9.7): `tintFill`, `small` radius; selected is
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

  static const double _height = 36;
  static const double _heightTv = 44;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final colors = tokens.colors;
    final tv = AdaptiveBehavior.of(context).formFactor == FormFactor.tv;
    final radius = BorderRadius.circular(RivuletRadius.small);
    final foreground = selected ? colors.onAccent : colors.textPrimary;
    final text = Padding(
      padding: const EdgeInsets.symmetric(horizontal: RivuletSpacing.s16),
      child: Center(
        widthFactor: 1,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: RivuletSpacing.s8),
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
      onActivate: onActivate,
      enabled: onActivate != null,
      focusNode: focusNode,
      autofocus: autofocus,
      semanticLabel: label,
      minSize: AdaptiveBehavior.hitTargetOf(context),
      centered: true,
      focusRadius: radius,
      child: SizedBox(
        height: tv ? _heightTv : _height,
        child: selected
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: radius,
                ),
                child: text,
              )
            : TintedSurface(radius: RivuletRadius.small, child: text),
      ),
    );
  }
}
