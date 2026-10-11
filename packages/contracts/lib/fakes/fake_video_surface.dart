import 'package:contracts/contracts.dart';
import 'package:flutter/widgets.dart';

/// Paints a solid colour with the controller's current position drawn on
/// it, keyed `fake-video-surface`, so a widget test can assert the surface
/// is present, sized and stable while overlays animate
/// (`planning/CONTRACTS.md` §4).
class FakeVideoSurface implements VideoSurface {
  const FakeVideoSurface();

  @override
  Stream<SurfaceMode> get mode => Stream.value(
    const SurfaceMode(
      SurfaceModeKind.texture,
      'Fake video surface (no native rendering)',
    ),
  );

  @override
  Widget build(
    BuildContext context,
    PlaybackController controller, {
    BoxFit fit = BoxFit.contain,
    Color background = const Color(0xFF000000),
  }) {
    return ColoredBox(
      key: const Key('fake-video-surface'),
      color: background,
      child: StreamBuilder<PlaybackState>(
        stream: controller.state,
        initialData: controller.currentState,
        builder: (context, snapshot) {
          final position = snapshot.data?.position ?? Duration.zero;
          return Center(
            child: Text(
              position.toString(),
              key: const Key('fake-video-surface-position'),
              style: const TextStyle(color: Color(0xFFFFFFFF)),
            ),
          );
        },
      ),
    );
  }
}
