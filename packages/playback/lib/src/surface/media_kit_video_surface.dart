import 'package:contracts/contracts.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import '../controller/media_kit_playback_controller.dart';

final class MediaKitVideoSurface implements VideoSurface {
  const MediaKitVideoSurface();

  @override
  Stream<SurfaceMode> get mode => Stream.value(
    const SurfaceMode(SurfaceModeKind.texture, 'media_kit texture surface'),
  );

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
    return _StableVideo(
      controller: controller,
      fit: fit,
      background: background,
    );
  }
}

final class _StableVideo extends StatefulWidget {
  const _StableVideo({
    required this.controller,
    required this.fit,
    required this.background,
  });

  final MediaKitPlaybackController controller;
  final BoxFit fit;
  final Color background;

  @override
  State<_StableVideo> createState() => _StableVideoState();
}

final class _StableVideoState extends State<_StableVideo> {
  late mkv.VideoController _videoController;

  @override
  void initState() {
    super.initState();
    _videoController = widget.controller.videoController;
  }

  @override
  void didUpdateWidget(covariant _StableVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _videoController = widget.controller.videoController;
    }
  }

  @override
  Widget build(BuildContext context) => mkv.Video(
    key: const ValueKey<String>('media-kit-video-surface'),
    controller: _videoController,
    fit: widget.fit,
    fill: widget.background,
    controls: mkv.NoVideoControls,
  );
}
