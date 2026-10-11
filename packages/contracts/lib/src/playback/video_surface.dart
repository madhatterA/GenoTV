import 'package:flutter/widgets.dart';

import 'playback_controller.dart';

/// The platform texture/surface widget for a [PlaybackController]. Part 04
/// places it; it never wraps it in anything that rebuilds on every frame.
///
/// Part 04 must be able to lay out and test the player screen without
/// libmpv present — the fake paints a solid colour with the current
/// position drawn on it, so a UI test can assert the surface is present,
/// sized, and stable while overlays animate.
///
/// This is the only reason `packages/contracts` depends on Flutter.
abstract interface class VideoSurface {
  /// Emits the current output and subsequent changes, including the reason for
  /// falling back when HDR output becomes unavailable during playback.
  Stream<SurfaceMode> get mode;

  Widget build(
    BuildContext context,
    PlaybackController controller, {
    BoxFit fit = BoxFit.contain,
    Color background = const Color(0xFF000000),
  });
}

/// The rendering path currently used by a video surface.
enum SurfaceModeKind { hdrNative, sdrNative, texture }

/// Surface output and the diagnostic reason for using it.
final class SurfaceMode {
  const SurfaceMode(this.kind, this.reason);

  final SurfaceModeKind kind;
  final String reason;
}
