import 'package:flutter/material.dart';

import '../focus/focusable_action.dart';
import '../platform/adaptive_behavior.dart';
import '../theme/rivulet_tokens.dart';
import 'glass_surface.dart';
import 'tinted_surface.dart';

/// The circular icon button (DESIGN_SPEC §9.3). [glass] is for the top
/// controls only; [overMedia] is for buttons placed on artwork or video.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    required this.icon,
    required this.semanticLabel,
    this.onActivate,
    this.glass = false,
    this.overMedia = false,
    this.size = RivuletControlSize.m,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  final IconData icon;

  /// Required: also the pointer tooltip.
  final String semanticLabel;

  /// Null disables the button.
  final VoidCallback? onActivate;
  final bool glass;
  final bool overMedia;

  /// Diameter and glyph tier (Part 07 p02); heroes use L.
  final RivuletControlSize size;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final colors = RivuletTokens.of(context).colors;
    final ff = AdaptiveBehavior.formFactorOf(context);
    final glyph = Center(
      child: Icon(icon, size: size.glyph(ff), color: colors.textPrimary),
    );
    const radius = RivuletRadius.full;
    final Widget surface = glass
        ? GlassSurface(radius: radius, child: glyph)
        : overMedia
        ? TintedSurface.overMedia(radius: radius, child: glyph)
        : TintedSurface(radius: radius, child: glyph);
    final button = FocusableAction(
      onActivate: onActivate,
      enabled: onActivate != null,
      focusNode: focusNode,
      autofocus: autofocus,
      semanticLabel: semanticLabel,
      minSize: AdaptiveBehavior.hitTargetOf(context),
      centered: true,
      focusRadius: BorderRadius.circular(radius),
      child: SizedBox.square(dimension: size.height(ff), child: surface),
    );
    return AdaptiveBehavior.of(context).inputMode == InputMode.pointer
        ? Tooltip(
            message: semanticLabel,
            excludeFromSemantics: true,
            child: button,
          )
        : button;
  }
}
