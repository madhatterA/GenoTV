import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' show Bidi;

import '../theme/rivulet_tokens.dart';

bool isFarsi(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'fa';

/// The one text widget for UI strings (DESIGN_SPEC §10.3). In Farsi the text
/// shapes right-to-left and the style takes the role's Farsi line height; the
/// widget's position never changes. Farsi UI labels and [paragraph] blocks align right (Part 07 p17).
class AppText extends StatelessWidget {
  const AppText(
    this.text, {
    this.style,
    this.paragraph = false,
    this.textAlign,
    this.softWrap,
    this.textDirection,
    this.maxLines,
    this.overflow,
    super.key,
  }) : _content = false;

  /// Content strings (titles, overviews, names): direction comes from the text
  /// itself in both languages.
  const AppText.content(
    this.text, {
    this.style,
    this.paragraph = false,
    this.textAlign,
    this.softWrap,
    this.textDirection,
    this.maxLines,
    this.overflow,
    super.key,
  }) : _content = true;

  final String text;
  final TextStyle? style;
  final bool paragraph;

  /// Overrides the alignment the widget would pick (centred copy stays centred).
  final TextAlign? textAlign;
  final bool? softWrap;
  final TextDirection? textDirection;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool _content;

  @override
  Widget build(BuildContext context) {
    final fa = isFarsi(context);
    final rtl = _content ? Bidi.detectRtlDirectionality(text) : fa;
    final effective = effectiveStyle(context, style);
    return Text(
      text,
      style: effective,
      textDirection:
          textDirection ?? (rtl ? TextDirection.rtl : TextDirection.ltr),
      textAlign:
          textAlign ??
          (rtl
              ? (paragraph || !_content ? TextAlign.right : TextAlign.left)
              : null),
      softWrap: softWrap,
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  /// The style [AppText] really draws with (tracking / Farsi line height).
  /// Anything that measures text to match an [AppText] must use this.
  static TextStyle? effectiveStyle(BuildContext context, TextStyle? style) {
    final fa = isFarsi(context);
    var effective = style;
    final tokens = Theme.of(context).extension<RivuletTokens>();
    if (!fa && tokens != null) {
      // English display/title tracking -0.5% (Part 07 p01); Farsi stays 0 so letters join.
      final base = effective ?? DefaultTextStyle.of(context).style;
      final roles = tokens.typeStyles;
      final size = base.fontSize;
      if (size == roles.display.fontSize || size == roles.title.fontSize) {
        effective = base.copyWith(letterSpacing: -0.005 * size!);
      }
    }
    if (fa) {
      final base = effective ?? DefaultTextStyle.of(context).style;
      final height = _faHeight(RivuletTokens.of(context).typeStyles, base);
      if (height != null) effective = base.copyWith(height: height);
    }
    return effective;
  }

  static double? _faHeight(RivuletTypeStyles roles, TextStyle style) {
    final size = style.fontSize;
    if (size == roles.display.fontSize) {
      return RivuletTypeStyles.displayHeightFa;
    }
    if (size == roles.title.fontSize) return RivuletTypeStyles.titleHeightFa;
    if (size == roles.headline.fontSize) {
      return RivuletTypeStyles.headlineHeightFa;
    }
    if (size == roles.body.fontSize) return RivuletTypeStyles.bodyHeightFa;
    if (size == roles.label.fontSize) return RivuletTypeStyles.labelHeightFa;
    if (size == roles.caption.fontSize) {
      return RivuletTypeStyles.captionHeightFa;
    }
    return null;
  }
}
