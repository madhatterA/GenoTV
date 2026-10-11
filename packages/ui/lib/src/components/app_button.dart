import 'package:flutter/material.dart';

import '../focus/focusable_action.dart';
import '../l10n/app_text.dart';
import '../platform/adaptive_behavior.dart';
import '../theme/rivulet_tokens.dart';
import 'tinted_surface.dart';

/// The pill button (DESIGN_SPEC §9.1, §9.2): [AppButton.primary] is an
/// `accent` fill with an `onAccent` label, [AppButton.secondary] a
/// [TintedSurface] (`overMedia` when placed on artwork).
class AppButton extends StatelessWidget {
  const AppButton.primary({
    required this.label,
    this.onActivate,
    this.icon,
    this.focusNode,
    this.autofocus = false,
    this.expand = false,
    super.key,
  }) : _primary = true,
       overMedia = false;

  const AppButton.secondary({
    required this.label,
    this.onActivate,
    this.icon,
    this.focusNode,
    this.autofocus = false,
    this.overMedia = false,
    this.expand = false,
    super.key,
  }) : _primary = false;

  final String label;

  /// Null disables the button.
  final VoidCallback? onActivate;
  final IconData? icon;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool overMedia;

  /// Fills the available width (the phone Play link button).
  final bool expand;
  final bool _primary;

  static const double _horizontalPadding = 20;
  static const double _iconSize = 20;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final colors = tokens.colors;
    final sizes = AdaptiveBehavior.sizesOf(context);
    final foreground = _primary ? colors.onAccent : colors.textPrimary;
    final radius = BorderRadius.circular(RivuletRadius.full);
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: _iconSize, color: foreground),
            const SizedBox(width: RivuletSpacing.s8),
          ],
          Flexible(
            child: AppText(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.typeStyles.label.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    final Widget shaped = _primary
        ? DecoratedBox(
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: radius,
            ),
            child: content,
          )
        : overMedia
        ? TintedSurface.overMedia(radius: RivuletRadius.full, child: content)
        : TintedSurface(radius: RivuletRadius.full, child: content);
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
        height: sizes.buttonHeight,
        width: expand ? double.infinity : null,
        child: shaped,
      ),
    );
  }
}
