import 'package:flutter/widgets.dart';

/// Lays the TV UI out on a 960-wide canvas and scales it to the screen.
///
/// Android TV reports 960x540 logical pixels (1080p at density 2); Apple TV
/// reports 1920x1080, so the same sizes looked half as big there (owner,
/// 2026-10-30). Screens up to [maxUnscaledWidth] are left alone, which keeps
/// Android TV unchanged. Hit testing and focus rings follow the transform, and
/// the pixel density is raised by the same factor so artwork stays sharp.
class TvScale extends StatelessWidget {
  const TvScale({required this.child, super.key});

  final Widget child;

  /// Logical width of the canvas the TV layout is designed for.
  static const double designWidth = 960;

  /// Wider screens than this are scaled down to [designWidth].
  static const double maxUnscaledWidth = 1280;

  /// The scale for a screen [width] logical pixels wide.
  static double factorFor(double width) =>
      width > maxUnscaledWidth ? width / designWidth : 1;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final k = factorFor(media.size.width);
    if (k == 1) return child;
    final inner = media.size / k;
    return FittedBox(
      fit: BoxFit.fill,
      child: SizedBox.fromSize(
        size: inner,
        child: MediaQuery(
          data: media.copyWith(
            size: inner,
            devicePixelRatio: media.devicePixelRatio * k,
            padding: media.padding / k,
            viewPadding: media.viewPadding / k,
            viewInsets: media.viewInsets / k,
            systemGestureInsets: media.systemGestureInsets / k,
          ),
          child: child,
        ),
      ),
    );
  }
}
