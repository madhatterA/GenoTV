import 'package:flutter/material.dart';

import '../theme/rivulet_tokens.dart';

/// The default panel/card/row fill (DESIGN_SPEC §3.2): a flat `tintFill` with
/// a 1 px `hairline` border and no blur. [TintedSurface.overMedia] is the
/// darker fill for anything placed over video or artwork.
class TintedSurface extends StatelessWidget {
  const TintedSurface({
    required this.child,
    this.radius = RivuletRadius.medium,
    this.padding,
    super.key,
  }) : _overMedia = false;

  const TintedSurface.overMedia({
    required this.child,
    this.radius = RivuletRadius.medium,
    this.padding,
    super.key,
  }) : _overMedia = true;

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final bool _overMedia;

  @override
  Widget build(BuildContext context) {
    final colors = RivuletTokens.of(context).colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _overMedia ? colors.tintFillOverMedia : colors.tintFill,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: colors.hairline),
      ),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );
  }
}
