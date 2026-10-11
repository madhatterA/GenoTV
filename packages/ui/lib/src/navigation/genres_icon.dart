import 'package:flutter/material.dart';

import '../theme/rivulet_tokens.dart';

/// The Genres glyph: three rounded squares and a circle at top right.
class GenresIcon extends StatelessWidget {
  const GenresIcon({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    return SizedBox.square(
      dimension: theme.size ?? 24,
      child: CustomPaint(
        painter: _GenresPainter(
          theme.color ?? RivuletTokens.of(context).colors.textPrimary,
        ),
      ),
    );
  }
}

class _GenresPainter extends CustomPainter {
  const _GenresPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()..color = color;
    for (final origin in [
      const Offset(2, 2),
      const Offset(2, 13),
      const Offset(13, 13),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          origin & const Size(9, 9),
          const Radius.circular(2),
        ),
        paint,
      );
    }
    canvas.drawCircle(const Offset(17.5, 6.5), 4.5, paint);
  }

  @override
  bool shouldRepaint(_GenresPainter oldDelegate) => color != oldDelegate.color;
}
