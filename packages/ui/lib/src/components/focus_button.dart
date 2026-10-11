import 'package:flutter/material.dart';

import '../focus/focusable_action.dart';
import '../l10n/app_text.dart';
import '../theme/rivulet_tokens.dart';

/// Layout shape for a [FocusButton]. Each variant keeps a fixed box size
/// across normal/focused/pressed/disabled states — [FocusableAction]
/// already guarantees this by scaling as a paint transform rather than a
/// resize, so a variant only needs to hand it a fixed-size child.
import 'tinted_surface.dart';

enum FocusButtonVariant { pill, circle, icon, row }

/// A glass-styled activatable control in one of four Rivulet shapes:
///  - [FocusButtonVariant.pill] — `HeroButtonRowView.swift:186-187`'s
///    250x66 label pill (radius = height / 2, `:208`).
///  - [FocusButtonVariant.circle] — the 66x66 icon-only circle
///    (`HeroButtonRowView.swift:354,387-388`).
///  - [FocusButtonVariant.icon] — a bare 44x44 minimum-hit-area icon button.
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
    this.compact = false,
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
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final geometry = tokens.geometry;
    final colors = tokens.colors;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 14;
    final compactScale = (MediaQuery.sizeOf(context).width / 1280).clamp(
      1.0,
      1.08,
    );

    final Widget shaped;
    final BorderRadius focusRadius;
    switch (variant) {
      case FocusButtonVariant.pill:
        focusRadius = BorderRadius.circular(
          compact ? 24 : geometry.heroButtonRadius,
        );
        shaped = _glass(
          focusRadius,
          Container(
            width: compact ? 176 * compactScale : geometry.heroPillWidth,
            constraints: BoxConstraints(
              minHeight: compact ? 44 * compactScale : geometry.heroPillHeight,
            ),
            padding: largeText
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                : EdgeInsets.zero,
            child: Center(child: _content(colors, withLabel: true)),
          ),
        );
      case FocusButtonVariant.circle:
        focusRadius = BorderRadius.circular(geometry.heroCircleDiameter / 2);
        shaped = _glass(
          focusRadius,
          SizedBox(
            width: geometry.heroCircleDiameter,
            height: geometry.heroCircleDiameter,
            child: Center(child: _content(colors, withLabel: false)),
          ),
        );
      case FocusButtonVariant.icon:
        focusRadius = BorderRadius.circular(22);
        shaped = SizedBox(
          width: 44,
          height: 44,
          child: Center(child: _content(colors, withLabel: false)),
        );
      case FocusButtonVariant.row:
        focusRadius = BorderRadius.circular(12);
        shaped = _glass(
          focusRadius,
          Container(
            constraints: const BoxConstraints(minHeight: 56),
            width: double.infinity,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: largeText ? 12 : 0,
              ),
              child: _content(colors, withLabel: true, expand: true),
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
    RivuletColors colors, {
    required bool withLabel,
    bool expand = false,
  }) {
    final iconWidget = icon == null
        ? null
        : Icon(icon, color: colors.textPrimary, size: compact ? 18 : 22);
    if (!withLabel || label == null) {
      return iconWidget ?? const SizedBox.shrink();
    }
    final text = AppText(
      label!,
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
        const SizedBox(width: 10),
        Flexible(child: text),
      ],
    );
  }
}
