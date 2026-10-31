import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/rivulet_tokens.dart';

/// Counts the pages inside a shell that paint their own [AmbientBackground].
/// While it is above zero the shell skips its own full-screen glow, which
/// those opaque pages fully cover: the extra full-screen draw per frame cost
/// ~7 ms of raster on the TV's Mali-G52 (Part 08 task 26).
class AmbientCoverage extends InheritedWidget {
  const AmbientCoverage({required this.pages, required super.child, super.key});

  final ValueNotifier<int> pages;

  static ValueNotifier<int>? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AmbientCoverage>()?.pages;

  @override
  bool updateShouldNotify(AmbientCoverage old) => pages != old.pages;
}

/// The one page background (DESIGN_SPEC §3.3): `bgBase` plus a static warm
/// radial glow at the top-left, rendered once into a small image and drawn as
/// one textured quad (the gradient shader replayed every frame cost ~7 ms of
/// raster per full-screen draw on the TV's Mali-G52).
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({required this.child, this.shell = false, super.key});

  final Widget child;

  /// The shell's own glow: hidden while a page paints one.
  final bool shell;

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground> {
  ValueNotifier<int>? _pages;

  void _count(int by) {
    final pages = _pages;
    // After the frame: the shell rebuilds, never while a page is building.
    WidgetsBinding.instance.addPostFrameCallback((_) => pages!.value += by);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.shell || _pages != null) return;
    _pages = AmbientCoverage.maybeOf(context);
    if (_pages != null) _count(1);
  }

  @override
  void dispose() {
    if (_pages != null) _count(-1);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = RivuletTokens.of(context).colors;
    final layer = RepaintBoundary(
      child: _GlowLayer(base: colors.bgBase, glow: colors.ambientGlow),
    );
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        if (widget.shell)
          Positioned.fill(
            child: ValueListenableBuilder<int>(
              valueListenable: AmbientCoverage.maybeOf(context)!,
              builder: (_, pages, _) =>
                  pages > 0 ? const SizedBox.shrink() : layer,
            ),
          )
        else
          Positioned.fill(child: layer),
        widget.child,
      ],
    );
  }
}

class _GlowLayer extends StatefulWidget {
  const _GlowLayer({required this.base, required this.glow});

  final Color base;
  final Color glow;

  @override
  State<_GlowLayer> createState() => _GlowLayerState();
}

class _GlowLayerState extends State<_GlowLayer> {
  static const double _downscale = 8;

  ui.Image? _image;
  Size? _size;
  Color? _base;
  Color? _glow;

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _render(Size size) {
    if (size == _size && widget.base == _base && widget.glow == _glow) return;
    final small = Size(
      math.max(1, (size.width / _downscale).ceilToDouble()),
      math.max(1, (size.height / _downscale).ceilToDouble()),
    );
    final recorder = ui.PictureRecorder();
    _GlowPainter(widget.base, widget.glow).paint(Canvas(recorder), small);
    final picture = recorder.endRecording();
    _image?.dispose();
    _image = picture.toImageSync(small.width.toInt(), small.height.toInt());
    picture.dispose();
    _size = size;
    _base = widget.base;
    _glow = widget.glow;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      if (!size.isFinite || size.isEmpty) return const SizedBox.shrink();
      _render(size);
      return CustomPaint(painter: _GlowImagePainter(_image!, widget.base));
    },
  );
}

class _GlowImagePainter extends CustomPainter {
  const _GlowImagePainter(this.image, this.base);

  final ui.Image image;
  final Color base;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..blendMode = BlendMode.src,
    );
  }

  @override
  bool shouldRepaint(_GlowImagePainter old) =>
      !identical(old.image, image) || old.base != base;
}

class _GlowPainter extends CustomPainter {
  const _GlowPainter(this.base, this.glow);

  final Color base;
  final Color glow;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = base);
    final center = Offset(size.width * 0.12, 0);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(colors: <Color>[glow, glow.withAlpha(0)])
            .createShader(
              Rect.fromCircle(center: center, radius: size.width * 1.1),
            ),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.base != base || old.glow != glow;
}

/// Fades [child] (a hero/backdrop image plus its scrims) to fully transparent
/// over its bottom 45 %, so the [AmbientBackground] underneath continues
/// unbroken (DESIGN_SPEC §3.3 ruling): an alpha mask, never an opaque band.
class AmbientFade extends StatelessWidget {
  static const List<double> _fadeSteps = <double>[
    0,
    0,
    .1,
    .2,
    .3,
    .4,
    .5,
    .6,
    .7,
    .8,
    .9,
    1,
  ];
  static double _fadeAt(int i) => i == 0 ? 0 : .35 + .65 * _fadeSteps[i];

  const AmbientFade({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => ShaderMask(
    blendMode: BlendMode.dstIn,
    shaderCallback: (bounds) => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      // Smoothstep from opaque (35 %) to clear (100 %): no kink where the
      // fade starts, so no visible edge.
      colors: <Color>[
        for (final t in _fadeSteps)
          Color.fromARGB(255 - (255 * t * t * (3 - 2 * t)).round(), 0, 0, 0),
      ],
      stops: <double>[for (var i = 0; i < _fadeSteps.length; i++) _fadeAt(i)],
    ).createShader(bounds),
    child: child,
  );
}
