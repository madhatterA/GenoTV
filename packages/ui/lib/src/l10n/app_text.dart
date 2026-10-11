import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' show Bidi;

import '../theme/rivulet_tokens.dart';

bool isFarsi(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'fa';

/// The one text widget for UI strings (DESIGN_SPEC §10.3). In Farsi the text
/// shapes right-to-left and the style takes the role's Farsi line height; the
/// widget's position never changes. [paragraph] blocks align right in Farsi.
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
    var effective = style;
    if (fa) {
      final base = effective ?? DefaultTextStyle.of(context).style;
      final height = _faHeight(RivuletTokens.of(context).typeStyles, base);
      if (height != null) effective = base.copyWith(height: height);
    }
    return Text(
      text,
      style: effective,
      textDirection:
          textDirection ?? (rtl ? TextDirection.rtl : TextDirection.ltr),
      textAlign:
          textAlign ??
          (rtl ? (paragraph ? TextAlign.right : TextAlign.left) : null),
      softWrap: softWrap,
      maxLines: maxLines,
      overflow: overflow,
    );
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
