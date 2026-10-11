import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/widgets.dart';

import '../controller/media_kit_playback_controller.dart';
import 'media_kit_video_surface.dart';

/// Adapts the controller-owned native output to the shared surface contract.
final class NativeVideoSurfaceAdapter implements VideoSurface {
  final _mode = ValueNotifier<SurfaceMode>(
    const SurfaceMode(SurfaceModeKind.texture, 'video output not initialized'),
  );
  MediaKitPlaybackController? _controller;

  @override
  Stream<SurfaceMode> get mode => Stream.multi((events) {
    events.add(_mode.value);
    void changed() => events.add(_mode.value);
    _mode.addListener(changed);
    events.onCancel = () => _mode.removeListener(changed);
  }, isBroadcast: true);

  void _changed() => _mode.value = _controller!.surfaceOutput.mode.value;

  @override
  Widget build(
    BuildContext context,
    PlaybackController controller, {
    BoxFit fit = BoxFit.contain,
    Color background = const Color(0xFF000000),
  }) {
    if (controller is! MediaKitPlaybackController) {
      throw ArgumentError.value(
        controller,
        'controller',
        'VideoSurface requires the controller created by playback',
      );
    }
    if (!identical(_controller, controller)) {
      _controller?.surfaceOutput.mode.removeListener(_changed);
      _controller = controller;
      controller.surfaceOutput.mode.addListener(_changed);
      _changed();
    }
    return ListenableBuilder(
      listenable: controller.surfaceOutput.mode,
      builder: (context, _) {
        final native = controller.surfaceOutput.nativeSurface;
        if (native != null) {
          return ColoredBox(color: background, child: native.build());
        }
        if (!controller.hasTextureOutput) return ColoredBox(color: background);
        return const MediaKitVideoSurface().build(
          context,
          controller,
          fit: fit,
          background: background,
        );
      },
    );
  }
}
