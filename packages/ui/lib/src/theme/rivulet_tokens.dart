import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';

/// Rivulet-derived design vocabulary: color, geometry, motion, focus and
/// type. Every raw `Color(0x…)` and `Duration(…)` literal in `packages/ui`
/// lives in this file and nowhere else — see `CLAUDE.md` and
/// `planning/part-04-ui/EXECUTION.md`.
///
/// Geometry and motion values are cited to `research/Rivulet/Rivulet/...`
/// in the phase report; the brand palette (surface/raised/onSurface/muted/
/// accent/danger) is an explicit owner decision recorded in
/// `phase-01-design-tokens.md`'s "Locked decisions" table, not a Rivulet
/// source value — Rivulet has no central color file.
@immutable
final class RivuletTokens extends ThemeExtension<RivuletTokens> {
  const RivuletTokens({
    required this.colors,
    required this.geometry,
    required this.motion,
    required this.focus,
    required this.typeStyles,
  });

  /// The one theme (DESIGN_SPEC §4.8). [tv] selects the TV type column.
  factory RivuletTokens.dark({required bool tv}) => RivuletTokens(
    colors: RivuletColors.dark(),
    geometry: RivuletGeometry.standard,
    motion: RivuletMotion.standard,
    focus: RivuletFocusMetrics.standard,
    typeStyles: RivuletTypeStyles.forColors(RivuletColors.dark(), tv: tv),
  );

  /// The only font family (DESIGN_SPEC §4.2); bundled by `packages/ui`.
  static const String fontFamily = 'Vazirmatn';
  static const String fontPackage = 'ui';

  /// Family name for `ThemeData.fontFamily`, which needs the package prefix.
  static const String themeFontFamily = 'packages/$fontPackage/$fontFamily';

  /// The one blur sigma (DESIGN_SPEC P4).
  static const double glassSigma = 20;

  final RivuletColors colors;
  final RivuletGeometry geometry;
  final RivuletMotion motion;
  final RivuletFocusMetrics focus;
  final RivuletTypeStyles typeStyles;

  static RivuletTokens of(BuildContext context) {
    final tokens = Theme.of(context).extension<RivuletTokens>();
    if (tokens == null) {
      throw StateError('RivuletTokens.of requires AppTheme.dark');
    }
    return tokens;
  }

  @override
  RivuletTokens copyWith({
    RivuletColors? colors,
    RivuletGeometry? geometry,
    RivuletMotion? motion,
    RivuletFocusMetrics? focus,
    RivuletTypeStyles? typeStyles,
  }) => RivuletTokens(
    colors: colors ?? this.colors,
    geometry: geometry ?? this.geometry,
    motion: motion ?? this.motion,
    focus: focus ?? this.focus,
    typeStyles: typeStyles ?? this.typeStyles,
  );

  @override
  RivuletTokens lerp(ThemeExtension<RivuletTokens>? other, double t) {
    if (other is! RivuletTokens) return this;
    return RivuletTokens(
      colors: colors.lerp(other.colors, t),
      geometry: t < 0.5 ? geometry : other.geometry,
      motion: t < 0.5 ? motion : other.motion,
      focus: t < 0.5 ? focus : other.focus,
      typeStyles: typeStyles.lerp(other.typeStyles, t),
    );
  }
}

/// Palette (DESIGN_SPEC §4.1), surface fills and the player fields
/// later phases delete as their last user goes.
@immutable
final class RivuletColors {
  const RivuletColors({
    required this.bgBase,
    required this.ambientGlow,
    required this.surfaceRaised,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.decorative,
    required this.accent,
    required this.onAccent,
    required this.danger,
    required this.success,
    required this.glassFill,
    required this.glassFillSolid,
    required this.tintFill,
    required this.tintFillOverMedia,
    required this.tintFillHover,
    required this.tintFillSelected,
    required this.hairline,
    required this.orbWhite,
    required this.scrim,

    required this.railButtonIdle,
    required this.railPlateFill,
    required this.railBorder,

    required this.playerPillBorder,
    required this.playerScrim,
    required this.panelRowSelectedFill,
    required this.panelRowSelectedForeground,
  });

  factory RivuletColors.dark() => const RivuletColors(
    bgBase: Color(0xFF121212),
    ambientGlow: Color(0xFF3B2223),
    surfaceRaised: Color(0xFF202020),
    textPrimary: Color(0xFFF4F4F4),
    textSecondary: Color(0xADFFFFFF),
    textTertiary: Color(0x99FFFFFF),
    decorative: Color(0x70FFFFFF),
    accent: Color(0xFFFFD166),
    onAccent: Color(0xFF1A1300),
    danger: Color(0xFFFF6B6B),
    success: Color(0xFF3DDC97),
    glassFill: Color(0x99121212),
    glassFillSolid: Color(0xF51C1C1E),
    tintFill: Color(0x0FFFFFFF),
    tintFillOverMedia: Color(0xCC000000),
    tintFillHover: Color(0x1AFFFFFF),
    tintFillSelected: Color(0x29FFD166),
    hairline: Color(0x1AFFFFFF),
    orbWhite: Color(0x99FFFFFF),
    scrim: Color(0x99000000),
    // HeroButtonRowView.swift:218,305 — pill idle fill: white at 20% alpha.

    // HeroButtonRowView.swift:364,439 — circle idle fill: white at 12% alpha.

    // HeroButtonRowView.swift:230,376 — stroke color: white at 20% alpha
    // (the "0.5" in the same lines is stroke line WIDTH in points, not an
    // alpha; see comment at HeroButtonRowView.swift:14, "white-20% 0.5pt
    // stroke").

    // TransportControlButton.swift:55 — idle background: white at 10% alpha
    railButtonIdle: Color(0x1AFFFFFF),
    // PlayerRailView.swift:90 — tintView: rgb(18,20,26) at 50% alpha.
    railPlateFill: Color(0x8012141A),
    // PlayerRailView.swift:80 — border: white at 10% alpha.
    railBorder: Color(0x1AFFFFFF),
    // No Rivulet macOS source exists (tvOS/iOS only). measured from
    // infuse-ref/macos/macos_1.png: sampled the flattened pill interior at
    // several points (e.g. (1550,975)->rgb(23,28,34), (850,1000)->rgb(23,23,23))
    // — near-black dark glass, not the pale/light translucent white this
    // token previously held (that was the ch03-p02 visual-polish bug).

    // measured from infuse-ref/macos/macos_1.png — same subtle white
    // hairline edge as the TV rail's own border (railBorder).
    playerPillBorder: Color(0x1AFFFFFF),
    // measured from infuse-ref/tvos/IMG_8303.jpg — soft black gradient
    // scrim rising from the bottom edge behind the resting TV chrome
    // (no boxed plate on TV, per the owner's ch03-p02 rejection).
    playerScrim: Color(0xFF000000),
    // Muted glass selection keeps content and geometry steady in every panel.
    panelRowSelectedFill: Color(0x24FFFFFF),
    panelRowSelectedForeground: Color(0xFFF4F4F4),
  );

  final Color bgBase;
  final Color ambientGlow;
  final Color surfaceRaised;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// Non-text decoration (icons, skeleton blocks); too dim for text.
  final Color decorative;

  /// The only accent (DESIGN_SPEC §4.1).
  final Color accent;
  final Color onAccent;
  final Color danger;
  final Color success;
  final Color glassFill;
  final Color glassFillSolid;
  final Color tintFill;
  final Color tintFillOverMedia;
  final Color tintFillHover;
  final Color tintFillSelected;
  final Color hairline;

  /// White at 60 % — the second `OrbLoader` circle (§9.9).
  final Color orbWhite;
  final Color scrim;

  final Color railButtonIdle;
  final Color railPlateFill;
  final Color railBorder;

  final Color playerPillBorder;
  final Color playerScrim;
  final Color panelRowSelectedFill;
  final Color panelRowSelectedForeground;

  /// Hero/backdrop bottom fade into [bgBase] (DESIGN_SPEC §4.1); the caller
  /// places it over the bottom 45 % of the image.
  LinearGradient get scrimBottom => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[bgBase.withAlpha(0), bgBase],
  );

  /// Text-side darkening of a hero (DESIGN_SPEC §4.1); the caller places it
  /// over the left 55 % of the image.
  LinearGradient get scrimSide => const LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: <Color>[Color(0xBF000000), Color(0x00000000)],
  );

  /// Behind the floating top controls while the page is scrolled
  /// (DESIGN_SPEC §7.2): black 45 % → 0 over 96 px (the caller sizes it).
  LinearGradient get scrimTopBar => const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[Color(0x73000000), Color(0x00000000)],
  );

  /// Black over the page while the menu panel is open (DESIGN_SPEC §7.3):
  /// 50 %, faded in with the panel.
  Color get scrimMenu => const Color(0x80000000);

  RivuletColors lerp(RivuletColors other, double t) => RivuletColors(
    bgBase: Color.lerp(bgBase, other.bgBase, t)!,
    ambientGlow: Color.lerp(ambientGlow, other.ambientGlow, t)!,
    surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
    textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
    textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
    textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
    decorative: Color.lerp(decorative, other.decorative, t)!,
    accent: Color.lerp(accent, other.accent, t)!,
    onAccent: Color.lerp(onAccent, other.onAccent, t)!,
    danger: Color.lerp(danger, other.danger, t)!,
    success: Color.lerp(success, other.success, t)!,
    glassFill: Color.lerp(glassFill, other.glassFill, t)!,
    glassFillSolid: Color.lerp(glassFillSolid, other.glassFillSolid, t)!,
    tintFill: Color.lerp(tintFill, other.tintFill, t)!,
    tintFillOverMedia: Color.lerp(
      tintFillOverMedia,
      other.tintFillOverMedia,
      t,
    )!,
    tintFillHover: Color.lerp(tintFillHover, other.tintFillHover, t)!,
    tintFillSelected: Color.lerp(tintFillSelected, other.tintFillSelected, t)!,
    hairline: Color.lerp(hairline, other.hairline, t)!,
    orbWhite: Color.lerp(orbWhite, other.orbWhite, t)!,
    scrim: Color.lerp(scrim, other.scrim, t)!,

    railButtonIdle: Color.lerp(railButtonIdle, other.railButtonIdle, t)!,
    railPlateFill: Color.lerp(railPlateFill, other.railPlateFill, t)!,
    railBorder: Color.lerp(railBorder, other.railBorder, t)!,

    playerPillBorder: Color.lerp(playerPillBorder, other.playerPillBorder, t)!,
    playerScrim: Color.lerp(playerScrim, other.playerScrim, t)!,
    panelRowSelectedFill: Color.lerp(
      panelRowSelectedFill,
      other.panelRowSelectedFill,
      t,
    )!,
    panelRowSelectedForeground: Color.lerp(
      panelRowSelectedForeground,
      other.panelRowSelectedForeground,
      t,
    )!,
  );
}

/// TV-reference (1920 canvas) geometry, cited to
/// `research/Rivulet/Rivulet/...`. See the phase report's
/// `## Source citations` for the resolving line for every field.
@immutable
final class RivuletGeometry {
  const RivuletGeometry({
    required this.posterWidth,
    required this.posterHeight,
    required this.cwWidth,
    required this.cwHeight,
    required this.shelfPosterCount,
    required this.shelfCwCount,
    required this.heroItemCap,
    required this.railHeight,
    required this.railPadV,
    required this.railPadH,
    required this.railButtonGap,
    required this.railTopRowGap,
    required this.railButtonDiameter,
  });

  /// MediaRowMetrics.swift:53-54 — `posterWidth = 296`, `posterHeight = 444`.
  final double posterWidth;
  final double posterHeight;

  /// MediaRowMetrics.swift:63-64 — `cwWidth = 357`, `cwHeight = 277`.
  final double cwWidth;
  final double cwHeight;

  /// MediaRowMetrics.swift:67-68 — `posterFullCount = 6`, `cwFullCount = 5`.
  final int shelfPosterCount;
  final int shelfCwCount;

  /// PlexHomeViewController.swift:3536 — `heroItemCap = 9`.
  final int heroItemCap;

  /// PlayerRailView.swift:19 — `railHeight = 260`.
  final double railHeight;

  /// PlayerRailView.swift:22-23 — `padV = 34`, `padH = 42`.
  final double railPadV;
  final double railPadH;

  /// PlayerRailView.swift:24-26 — `buttonGap = 20`, `topRowGap = 32`,
  /// `buttonDiameter = 74`.
  final double railButtonGap;
  final double railTopRowGap;
  final double railButtonDiameter;

  static const RivuletGeometry standard = RivuletGeometry(
    posterWidth: 296,
    posterHeight: 444,
    cwWidth: 357,
    cwHeight: 277,
    shelfPosterCount: 6,
    shelfCwCount: 5,
    heroItemCap: 9,
    railHeight: 260,
    railPadV: 34,
    railPadH: 48,
    railButtonGap: 20,
    railTopRowGap: 32,
    railButtonDiameter: 74,
  );
}

/// Motion timings, cited to `research/Rivulet/Rivulet/...`.
@immutable
final class RivuletMotion {
  const RivuletMotion({
    required this.holdThreshold,
    required this.seekCoalesce,
    required this.actionDedupe,
    required this.transportDedupe,
    required this.scrubNudgeDedupe,
    required this.blockDismiss,
    required this.heroAutoScrollGate,
    required this.heroStripIdleGate,
  });

  /// DESIGN_SPEC §5.1 curves. `Curves.easeIn` is never used.
  static const Curve easeOut = Cubic(0.23, 1, 0.32, 1);
  static const Curve easeInOut = Cubic(0.77, 0, 0.175, 1);
  static const Curve drawer = Cubic(0.32, 0.72, 0, 1);

  /// DESIGN_SPEC §5.1 durations.
  static const Duration press = Duration(milliseconds: 120);
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration panel = Duration(milliseconds: 260);
  static const Duration page = Duration(milliseconds: 240);

  /// How long a toast stays: short, and long (TV, Undo, one-time hints).
  static const Duration toast = Duration(seconds: 3);
  static const Duration toastLong = Duration(seconds: 5);

  /// Window for the second Back that leaves the app (Android).
  static const Duration backExit = Duration(seconds: 2);

  /// Seek/volume badge: held this long, then fades over the same time.
  static const Duration seekBadge = Duration(milliseconds: 600);

  /// Key seeks closer than this continue from the previous target.
  static const Duration keySeekStack = Duration(milliseconds: 400);

  /// Presses closer than this add up in the seek badge ("+20 s").
  static const Duration seekBadgeStack = Duration(milliseconds: 600);

  /// InputConfig.swift:14 — `holdThreshold: TimeInterval = 0.4`.
  final Duration holdThreshold;

  /// InputConfig.swift:15 — `seekCoalesceInterval: TimeInterval = 0.05`.
  final Duration seekCoalesce;

  /// InputConfig.swift:16 — `actionDedupeWindow: TimeInterval = 0.08`.
  final Duration actionDedupe;

  /// InputConfig.swift:17 — `transportDedupeWindow: TimeInterval = 0.35`.
  final Duration transportDedupe;

  /// InputConfig.swift:28 — `scrubNudgeDedupeWindow: TimeInterval = 0.25`.
  final Duration scrubNudgeDedupe;

  /// InputConfig.swift:29 — `blockDismissTimeout: TimeInterval = 0.3`.
  final Duration blockDismiss;

  /// PlexHomeViewController.swift:1507 — `asyncAfter(deadline: .now() + 2)`
  /// before the deferred auto-scroll runs.
  final Duration heroAutoScrollGate;

  /// PlexHomeViewController.swift:1306 — `asyncAfter(deadline: .now() + 3)`
  /// before the idle strip return runs.
  final Duration heroStripIdleGate;

  static const RivuletMotion standard = RivuletMotion(
    holdThreshold: Duration(milliseconds: 400),
    seekCoalesce: Duration(milliseconds: 50),
    actionDedupe: Duration(milliseconds: 80),
    transportDedupe: Duration(milliseconds: 350),
    scrubNudgeDedupe: Duration(milliseconds: 250),
    blockDismiss: Duration(milliseconds: 300),
    heroAutoScrollGate: Duration(seconds: 2),
    heroStripIdleGate: Duration(seconds: 3),
  );
}

/// Focus/press scale metrics (DESIGN_SPEC §4.7, §5.2). [railFocusScale] is
/// the player transport button's own scale (player unchanged).
@immutable
final class RivuletFocusMetrics {
  const RivuletFocusMetrics({
    required this.tileFocusScale,
    required this.tileFocusScaleTv,
    required this.tileHoverScale,
    required this.railFocusScale,
    required this.pressScale,
    required this.focusGrowthPadding,
  });

  /// Focused card/poster scale on phone and desktop (§4.7).
  final double tileFocusScale;

  /// Focused card/poster scale on TV (§4.7).
  final double tileFocusScaleTv;

  /// Pointer hover scale of a card/poster (§5.2).
  final double tileHoverScale;

  /// TransportControlButton.swift:141 — `CGAffineTransform(scaleX: 1.15, y: 1.15)`.
  final double railFocusScale;

  /// Press-down scale of every pressable (§5.2).
  final double pressScale;

  /// MediaRowMetrics.swift:74 — `focusGrowthPadding: CGFloat = 48`.
  final double focusGrowthPadding;

  static const RivuletFocusMetrics standard = RivuletFocusMetrics(
    tileFocusScale: 1.04,
    tileFocusScaleTv: 1.06,
    tileHoverScale: 1.03,
    railFocusScale: 1.15,
    pressScale: 0.97,
    focusGrowthPadding: 48,
  );
}

/// Text styles by role. Font sizes are the pre-existing implementation
/// values (36/24/16/14/12); Rivulet has no shared type-scale file and no
/// phase source map row names one, so these are not cited as Rivulet
/// constants — only the role names replace the discarded `AppTypeScale`.
@immutable
final class RivuletTypeStyles {
  const RivuletTypeStyles({
    required this.display,
    required this.title,
    required this.headline,
    required this.body,
    required this.label,
    required this.caption,
    required this.panelRow,
    required this.panelRowCaption,
  });

  /// Six roles from DESIGN_SPEC §4.2; [tv] picks the TV size column. Letter
  /// spacing is 0 everywhere (Persian joining). `height` is the English line
  /// height; the Farsi heights are the `*HeightFa` constants (used by ch04).
  factory RivuletTypeStyles.forColors(
    RivuletColors colors, {
    required bool tv,
  }) {
    // TV secondary text is 75% white (Part 07 p01).
    final secondary = tv ? const Color(0xBFFFFFFF) : colors.textSecondary;
    TextStyle style(
      double phoneDesktop,
      double tvSize,
      FontWeight weight,
      double height,
      Color color,
    ) => TextStyle(
      fontFamily: RivuletTokens.fontFamily,
      package: RivuletTokens.fontPackage,
      fontSize: tv ? tvSize : phoneDesktop,
      fontWeight: weight,
      height: height,
      letterSpacing: 0,
      color: color,
    );
    return RivuletTypeStyles(
      display: style(34, 38, FontWeight.w700, 1.15, colors.textPrimary),
      title: style(24, 28, FontWeight.w700, 1.2, colors.textPrimary),
      headline: style(19, 22, FontWeight.w600, 1.25, colors.textPrimary),
      body: style(16, 20, FontWeight.w400, 1.45, colors.textPrimary),
      label: style(15, 18, FontWeight.w500, 1.3, colors.textPrimary),
      caption: style(14, 17, FontWeight.w500, 1.3, secondary),
      panelRow: TextStyle(
        fontFamily: RivuletTokens.fontFamily,
        package: RivuletTokens.fontPackage,
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
      panelRowCaption: TextStyle(
        fontFamily: RivuletTokens.fontFamily,
        package: RivuletTokens.fontPackage,
        fontSize: 18,
        color: secondary,
      ),
    );
  }

  /// Farsi line heights per role (DESIGN_SPEC §4.2), applied in ch04.
  static const double displayHeightFa = 1.3;
  static const double titleHeightFa = 1.4;
  static const double headlineHeightFa = 1.5;
  static const double bodyHeightFa = 1.8;
  static const double labelHeightFa = 1.5;
  static const double captionHeightFa = 1.5;

  final TextStyle display;
  final TextStyle title;
  final TextStyle headline;
  final TextStyle body;
  final TextStyle label;
  final TextStyle caption;
  final TextStyle panelRow;
  final TextStyle panelRowCaption;

  RivuletTypeStyles lerp(RivuletTypeStyles other, double t) =>
      RivuletTypeStyles(
        display: TextStyle.lerp(display, other.display, t)!,
        title: TextStyle.lerp(title, other.title, t)!,
        headline: TextStyle.lerp(headline, other.headline, t)!,
        body: TextStyle.lerp(body, other.body, t)!,
        label: TextStyle.lerp(label, other.label, t)!,
        caption: TextStyle.lerp(caption, other.caption, t)!,
        panelRow: TextStyle.lerp(panelRow, other.panelRow, t)!,
        panelRowCaption: TextStyle.lerp(
          panelRowCaption,
          other.panelRowCaption,
          t,
        )!,
      );
}

/// 4 px grid constants and per-form-factor spacing (DESIGN_SPEC §4.3).
abstract final class RivuletSpacing {
  /// Desktop windows at least this wide (logical px) get the persistent
  /// sidebar instead of the menu pill; Part 07 p10.
  static const double sidebarMinWindow = 1100;
  static const double sidebarWidth = 220;

  /// Desktop page content never gets wider than this; extra window width is
  /// margin either side (Part 07 p11).
  static const double contentMaxWidth = 1800;

  /// Desktop vertical scrollbar thickness.
  static const double scrollbarThickness = 6;

  /// Key-name column in the shortcut sheet.
  static const double shortcutKeyColumn = 160;
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;
  static const double s64 = 64;

  /// Page horizontal gutter.
  static double gutter(FormFactor f) => switch (f) {
    FormFactor.phone => s16,
    FormFactor.desktop => s32,
    FormFactor.tv => s48,
  };

  /// Page gutter for this screen: on a phone in landscape it also clears the
  /// left/right safe inset (notch), never less than [gutter].
  static double gutterOf(BuildContext context) {
    final f = AdaptiveBehavior.formFactorOf(context);
    if (f != FormFactor.phone) return gutter(f);
    final p = MediaQuery.paddingOf(context);
    return math.max(gutter(f), math.max(p.left, p.right) + s16);
  }

  /// Gap between rows/sections.
  static double rowGap(FormFactor f) => f == FormFactor.phone ? s24 : s32;

  /// Gap between posters/cards in a row or grid.
  static double itemGap(FormFactor f) => f == FormFactor.phone ? s12 : s16;

  /// Gap from a section header to its row.
  static double headerGap(FormFactor f) => f == FormFactor.tv ? s16 : s12;

  /// Title-safe zone of the TV canvas (960 x 540): 5% of each edge, rounded
  /// up to the 4 px grid vertically. Every TV overlay stays inside it.
  static const double tvSafeX = 48;
  static const double tvSafeY = 28;
  static const EdgeInsets tvSafe = EdgeInsets.symmetric(
    horizontal: tvSafeX,
    vertical: tvSafeY,
  );

  /// Offset of the top controls (menu pill, search, back) below the safe top.
  static double controlTop(FormFactor f) =>
      f == FormFactor.phone ? s12 : (f == FormFactor.tv ? tvSafeY : s16);

  /// Page content top, measured from the safe top: control top + M control
  /// height + 16 (replaces the fixed 72/80/88 inset).
  static double contentTop(FormFactor f) =>
      controlTop(f) + RivuletControlSize.m.height(f) + s16;
}

/// Control height tiers (Part 07 p02). Heights per form factor; TV on the
/// 960-wide canvas. S chips, M buttons/fields, L hero actions, XL play/pause.
enum RivuletControlSize {
  s(40, 32, 44, 16, 16, 20),
  m(48, 40, 52, 20, 20, 24),
  l(56, 48, 64, 24, 24, 28),
  xl(64, 56, 74, 28, 28, 32);

  const RivuletControlSize(
    this._phone,
    this._desktop,
    this._tv,
    this._glyphPhone,
    this._glyphDesktop,
    this._glyphTv,
  );

  final double _phone;
  final double _desktop;
  final double _tv;
  final double _glyphPhone;
  final double _glyphDesktop;
  final double _glyphTv;

  double height(FormFactor f) => switch (f) {
    FormFactor.phone => _phone,
    FormFactor.desktop => _desktop,
    FormFactor.tv => _tv,
  };

  double glyph(FormFactor f) => switch (f) {
    FormFactor.phone => _glyphPhone,
    FormFactor.desktop => _glyphDesktop,
    FormFactor.tv => _glyphTv,
  };

  /// 0.4 x height on the 4 px grid (capsule optical balance).
  double horizontalPadding(FormFactor f) => (height(f) * 0.4 / 4).round() * 4;

  /// Icon-to-label gap.
  double iconGap(FormFactor f) => f == FormFactor.tv ? 12 : 8;
}

/// DESIGN_SPEC §4.4.
abstract final class RivuletRadius {
  static const double medium = 14;
  static const double large = 22;

  /// Badges.
  static const double xs = 4;

  /// Pills and circular buttons.
  static const double full = 999;
}

/// Every row of DESIGN_SPEC §4.5 for one form factor and window size.
@immutable
final class RivuletSizes {
  const RivuletSizes._({
    required this.formFactor,
    required this.size,
    required this.minHitTarget,
    required this.iconButton,
    required this.iconGlyph,
    required this.buttonHeight,
    required this.menuPillHeight,
    required this.posterWidth,
    required this.continueCardWidth,
    required this.heroHeight,
    required this.heroTextMaxWidth,
    required this.menuPanelWidth,
    required this.settingsContentMaxWidth,
    required this.settingsRowMinHeight,
    required this.dialogMaxWidth,
  });

  factory RivuletSizes.of(FormFactor formFactor, Size size) {
    final w = size.width;
    final h = size.height;
    final gutter = RivuletSpacing.gutter(formFactor);
    return switch (formFactor) {
      FormFactor.phone => RivuletSizes._(
        formFactor: formFactor,
        size: size,
        minHitTarget: 48,
        iconButton: RivuletControlSize.m.height(FormFactor.phone),
        iconGlyph: RivuletControlSize.m.glyph(FormFactor.phone),
        buttonHeight: RivuletControlSize.m.height(FormFactor.phone),
        menuPillHeight: RivuletControlSize.m.height(FormFactor.phone),
        posterWidth: 112,
        continueCardWidth: 232,
        heroHeight: h * 0.5,
        heroTextMaxWidth: w - 2 * gutter,
        menuPanelWidth: math.min(320, w * 0.85),
        settingsContentMaxWidth: w,
        settingsRowMinHeight: 56,
        dialogMaxWidth: w - 32,
      ),
      FormFactor.desktop => RivuletSizes._(
        formFactor: formFactor,
        size: size,
        minHitTarget: 40,
        iconButton: RivuletControlSize.m.height(FormFactor.desktop),
        iconGlyph: RivuletControlSize.m.glyph(FormFactor.desktop),
        buttonHeight: RivuletControlSize.m.height(FormFactor.desktop),
        menuPillHeight: RivuletControlSize.m.height(FormFactor.desktop),
        posterWidth: (w * 0.125).clamp(150, 230).toDouble(),
        continueCardWidth: (w * 0.21).clamp(260, 380).toDouble(),
        heroHeight: math.min(h * 0.7, w * 0.5),
        heroTextMaxWidth: 560,
        menuPanelWidth: 300,
        settingsContentMaxWidth: 720,
        settingsRowMinHeight: 52,
        dialogMaxWidth: 440,
      ),
      FormFactor.tv => RivuletSizes._(
        formFactor: formFactor,
        size: size,
        minHitTarget: null,
        iconButton: RivuletControlSize.m.height(FormFactor.tv),
        iconGlyph: RivuletControlSize.m.glyph(FormFactor.tv),
        buttonHeight: RivuletControlSize.m.height(FormFactor.tv),
        menuPillHeight: RivuletControlSize.m.height(FormFactor.tv),
        posterWidth: 148,
        continueCardWidth: 280,
        heroHeight: h * 0.72,
        heroTextMaxWidth: 520,
        menuPanelWidth: 340,
        settingsContentMaxWidth: 720,
        settingsRowMinHeight: 60,
        dialogMaxWidth: 520,
      ),
    };
  }

  /// Desktop hit target while the last input was touch (DESIGN_SPEC §4.5).
  static const double touchHitTarget = 48;

  final FormFactor formFactor;
  final Size size;

  /// Null on TV (focus, not hit targets).
  final double? minHitTarget;
  final double iconButton;
  final double iconGlyph;
  final double buttonHeight;
  final double menuPillHeight;
  final double posterWidth;
  final double continueCardWidth;

  /// Poster beside the title on a phone detail page.
  static const double phoneDetailPoster = 96;
  final double heroHeight;
  final double heroTextMaxWidth;
  final double menuPanelWidth;
  final double settingsContentMaxWidth;
  final double settingsRowMinHeight;
  final double dialogMaxWidth;

  /// Posters are 2:3.
  double get posterHeight => posterWidth * 1.5;

  /// 16:9 continue-watching card height.
  double get continueCardHeight => continueCardWidth * 9 / 16;

  /// `floor((width − 2·gutter + gap) / (cardWidth + gap))`, min 2, for a grid
  /// laid out in [width] (§4.5); [cardWidth] is the poster width unless the
  /// cards are another size.
  int columnsFor(double width, {double? cardWidth}) {
    final gutter = RivuletSpacing.gutter(formFactor);
    final gap = RivuletSpacing.itemGap(formFactor);
    final n = ((width - 2 * gutter + gap) / ((cardWidth ?? posterWidth) + gap))
        .floor();
    return math.max(2, n);
  }

  /// Card width that makes [columns] cards fill [width] between both gutters.
  double gridCardWidth(double width, int columns) {
    final gap = RivuletSpacing.itemGap(formFactor);
    final gutter = RivuletSpacing.gutter(formFactor);
    return (width - 2 * gutter - (columns - 1) * gap) / columns;
  }

  int get gridColumns => columnsFor(size.width);
}

// Owner detail logos retain their original brand artwork colors.
abstract final class RatingBrandPalette {
  static const imdb = Color(0xFFF5C518);
  static const imdbInk = Color(0xFF000000);
  static const tmdb = Color(0xFF0D253F);
  static const tmdbInk = Color(0xFF01B4E4);
  static const tomato = Color(0xFFFA320A);
  static const leaf = Color(0xFF3B9F2F);
  static const rotten = Color(0xFF6FC331);
  static const score = Color(0xFFFFFFFF);
}

Duration effectiveDuration(BuildContext context, Duration duration) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;

/// Scrolls [position] to [offset] over [duration]; a zero duration (reduced
/// motion) jumps, because `ScrollPosition.animateTo` asserts on one.
void scrollPositionTo(
  ScrollPosition position,
  double offset, {
  required Duration duration,
  required Curve curve,
}) {
  if (duration == Duration.zero) {
    position.jumpTo(offset);
  } else {
    position.animateTo(offset, duration: duration, curve: curve);
  }
}
