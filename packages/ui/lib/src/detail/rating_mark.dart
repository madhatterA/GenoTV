import 'package:intl/intl.dart';

import '../l10n_gen/app_strings.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Icon + score for the metadata line: the IMDb logo mark with [imdb], or a
/// Rotten Tomatoes tomato with [rottenTomatoes] (e.g. "87%"; red tomato at
/// 60% and above, green splat below), or the TMDB mark with [tmdb] (e.g.
/// "7.0"; the backup when OMDb has no score). Exactly one of the three is given.
import '../l10n/app_text.dart';
import '../theme/rivulet_tokens.dart';

class RatingMark extends StatelessWidget {
  const RatingMark({
    super.key,
    this.imdb,
    this.rottenTomatoes,
    this.tmdb,
    required this.scale,
    this.textStyle,
  }) : assert(
         (imdb == null ? 0 : 1) +
                 (rottenTomatoes == null ? 0 : 1) +
                 (tmdb == null ? 0 : 1) ==
             1,
       );

  final String? imdb;
  final String? rottenTomatoes;
  final String? tmdb;
  final double scale;

  /// Score text style; null keeps the legacy 24 pt bold white score.
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final isImdb = imdb != null;
    final score = imdb ?? tmdb ?? rottenTomatoes!;
    final percent = int.tryParse(score.replaceAll(RegExp(r'[^0-9]'), ''));
    final fresh = percent == null || percent >= 60;
    final raw = score.replaceAll('%', '');
    final value = num.tryParse(raw);
    final digits = raw.contains('.') ? raw.split('.').last.length : 0;
    final displayScore = !isFarsi(context) || value == null
        ? score
        : score.endsWith('%')
        ? '${NumberFormat('0', 'fa').format(value)}٪'
        : NumberFormat(
            digits == 0 ? '0' : '0.${'0' * digits}',
            'fa',
          ).format(value);
    final size = 22 * scale;
    return Semantics(
      label: isImdb
          ? AppStrings.of(context).rating_imdb(displayScore)
          : tmdb != null
          ? AppStrings.of(context).rating_tmdb(displayScore)
          : fresh
          ? AppStrings.of(context).rating_tomatoFresh(displayScore)
          : AppStrings.of(context).rating_tomatoRotten(displayScore),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (isImdb)
            _PlateLogo(
              height: size,
              text: 'IMDb',
              plate: RatingBrandPalette.imdb,
              ink: RatingBrandPalette.imdbInk,
            )
          else if (tmdb != null)
            _PlateLogo(
              height: size,
              text: 'TMDB',
              plate: RatingBrandPalette.tmdb,
              ink: RatingBrandPalette.tmdbInk,
            )
          else
            CustomPaint(
              size: Size.square(size),
              painter: _TomatoPainter(fresh: fresh),
            ),
          SizedBox(width: 7 * scale),
          AppText(
            displayScore,
            style:
                textStyle ??
                TextStyle(
                  fontSize: 24 * scale,
                  fontWeight: FontWeight.w700,
                  color: RatingBrandPalette.score,
                ),
          ),
        ],
      ),
    );
  }
}

/// A brand mark: bold wordmark on a rounded plate (IMDb yellow, TMDB navy).
class _PlateLogo extends StatelessWidget {
  const _PlateLogo({
    required this.height,
    required this.text,
    required this.plate,
    required this.ink,
  });

  final double height;
  final String text;
  final Color plate;
  final Color ink;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: EdgeInsets.symmetric(horizontal: height * .2),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: plate,
      borderRadius: BorderRadius.circular(height * .2),
    ),
    child: AppText(
      text,
      style: TextStyle(
        fontSize: height * .68,
        height: 1,
        fontWeight: FontWeight.w900,
        color: ink,
      ),
    ),
  );
}

class _TomatoPainter extends CustomPainter {
  const _TomatoPainter({required this.fresh});

  final bool fresh;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    if (fresh) {
      canvas.drawOval(
        Rect.fromLTWH(0, w * .16, w, w * .84),
        Paint()..color = RatingBrandPalette.tomato,
      );
      final leaf = Paint()..color = RatingBrandPalette.leaf;
      final stem = Path()
        ..moveTo(w * .5, w * .32)
        ..lineTo(w * .28, w * .1)
        ..lineTo(w * .42, w * .2)
        ..lineTo(w * .5, w * 0)
        ..lineTo(w * .58, w * .2)
        ..lineTo(w * .72, w * .1)
        ..close();
      canvas.drawPath(stem, leaf);
    } else {
      // Rotten: a green splat, three lobes around the centre.
      final splat = Path();
      for (var i = 0; i <= 64; i++) {
        final a = i / 64 * 2 * math.pi;
        final r = w * (.42 + .06 * math.cos(a * 3 + .5));
        final point = Offset(w / 2 + r * math.cos(a), w / 2 + r * math.sin(a));
        i == 0
            ? splat.moveTo(point.dx, point.dy)
            : splat.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(splat, Paint()..color = RatingBrandPalette.rotten);
    }
  }

  @override
  bool shouldRepaint(_TomatoPainter old) => old.fresh != fresh;
}
