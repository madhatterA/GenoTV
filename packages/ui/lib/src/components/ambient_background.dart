import 'package:flutter/material.dart';

import '../theme/rivulet_tokens.dart';

/// The one page background (DESIGN_SPEC §3.3): `bgBase` plus a static warm
/// radial glow at the top-left. Painted once inside a [RepaintBoundary].
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = RivuletTokens.of(context).colors;
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _GlowPainter(colors.bgBase, colors.ambientGlow),
            ),
          ),
        ),
        child,
      ],
    );
  }
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
