import 'dart:ui';

import 'package:flutter/material.dart';

import '../platform/adaptive_behavior.dart';
import '../theme/rivulet_tokens.dart';

/// A layer that floats over other content (DESIGN_SPEC §3.1): blurred
/// `glassFill` where [AdaptiveBehavior] allows blur, solid `glassFillSolid`
/// otherwise (TV, high-contrast), always with a 1 px `hairline` border.
///
/// This is the only file in the app that creates a blur (DESIGN_SPEC P1).
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    required this.child,
    this.radius = RivuletRadius.large,
    this.borderRadius,
    this.padding,
    super.key,
  });

  final Widget child;
  final double radius;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = RivuletTokens.of(context).colors;
    final blur = AdaptiveBehavior.of(context).blurAllowed;
    final highContrast = MediaQuery.maybeOf(context)?.highContrast ?? false;
    final borderRadius = this.borderRadius ?? BorderRadius.circular(radius);

    final panel = DecoratedBox(
      decoration: BoxDecoration(
        color: blur ? colors.glassFill : colors.glassFillSolid,
        borderRadius: borderRadius,
        border: Border.all(
          color: highContrast ? colors.textPrimary : colors.hairline,
          width: highContrast ? 2 : 1,
        ),
      ),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );

    if (!blur) return ClipRRect(borderRadius: borderRadius, child: panel);

    final filter = ImageFilter.blur(
      sigmaX: RivuletTokens.glassSigma,
      sigmaY: RivuletTokens.glassSigma,
    );
    return ClipRRect(
      borderRadius: borderRadius,
      // Surfaces under one app-root BackdropGroup share a single backdrop
      // capture (Flutter's BackdropFilter.grouped).
      child: BackdropGroup.of(context) == null
          ? BackdropFilter(filter: filter, child: panel)
          : BackdropFilter.grouped(filter: filter, child: panel),
    );
  }
}
