import 'package:flutter/material.dart';

import 'rivulet_tokens.dart';

/// The one (dark) theme, DESIGN_SPEC §4.8. [tv] selects the TV type sizes.
abstract final class AppTheme {
  static ThemeData dark({required bool tv}) =>
      _build(RivuletTokens.dark(tv: tv));

  /// Compatibility accessor: text styles by role, backed by
  /// `RivuletTokens.type`.
  static RivuletTypeStyles textStylesOf(BuildContext context) {
    final tokens = Theme.of(context).extension<RivuletTokens>();
    if (tokens == null) {
      throw StateError('AppTheme.textStylesOf requires AppTheme.dark');
    }
    return tokens.typeStyles;
  }

  static ThemeData _build(RivuletTokens tokens) {
    final colors = tokens.colors;
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: RivuletTokens.themeFontFamily,
      scaffoldBackgroundColor: colors.bgBase,
      colorScheme: ColorScheme(
        brightness: Brightness.dark,
        primary: colors.accent,
        onPrimary: colors.onAccent,
        secondary: colors.accent,
        onSecondary: colors.onAccent,
        error: colors.danger,
        onError: colors.bgBase,
        surface: colors.bgBase,
        onSurface: colors.textPrimary,
      ),
    );
    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[tokens],
      cardTheme: CardThemeData(
        color: colors.surfaceRaised,
        // Generic app-wide Material card radius, not a Rivulet screen
        // constant (no card in Rivulet's own design uses a shared default —
        // every card there sets its own radius per view). Kept at the
        // existing pre-phase value so this phase's token rewiring does not
        // silently reshape every default-styled Card in the app; screens
        // that need a cited Rivulet radius set it explicitly per phase.
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      focusColor: colors.accent,
    );
  }
}
