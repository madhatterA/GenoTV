import '../l10n_gen/app_strings.dart';

import 'package:flutter/widgets.dart';

/// One entry in the menu panel (DESIGN_SPEC §7.1), in order.
@immutable
final class AppDestination {
  const AppDestination({
    required this.id,
    this.label = '',
    this.labelOf,
    required this.icon,
    this.activeIcon,
    this.iconWidget,
    required this.builder,
  });

  /// Stable identity. Used as the `Navigator` restoration scope id and as
  /// the widget key for each destination's offstage content, so switching
  /// tabs never recreates a page.
  final String id;

  /// Fixed text; used when [labelOf] is null.
  final String label;

  /// Localized text, resolved where an [AppStrings] is at hand.
  final String Function(AppStrings strings)? labelOf;

  /// The text to draw for this destination in the current language.
  String labelIn(BuildContext context) =>
      labelOf?.call(AppStrings.of(context)) ?? label;

  /// Regular-weight glyph, shown while the destination is not current.
  final IconData icon;

  /// Fill-weight glyph shown for the current destination (DESIGN_SPEC
  /// §4.6); falls back to [icon].
  final IconData? activeIcon;

  /// Optional glyph drawn with the ambient IconTheme, in every state.
  final Widget? iconWidget;

  /// Builds this destination's root page. `AppShell` wraps it in its own
  /// `Navigator`, so pushes from inside this builder are local to the tab.
  final WidgetBuilder builder;
}

class AppDestinationIcon extends StatelessWidget {
  const AppDestinationIcon({
    required this.destination,
    this.color,
    this.size,
    this.current = false,
    super.key,
  });
  final AppDestination destination;
  final Color? color;
  final double? size;

  /// Draws the Fill glyph.
  final bool current;

  @override
  Widget build(BuildContext context) => IconTheme.merge(
    data: IconThemeData(color: color, size: size),
    child:
        destination.iconWidget ??
        Icon(
          current
              ? destination.activeIcon ?? destination.icon
              : destination.icon,
        ),
  );
}
