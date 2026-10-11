import 'package:flutter/widgets.dart';

/// One page's primary element (DESIGN_SPEC §6.4 rule 9): the node the shell
/// focuses when the page is entered from the keyboard or a remote.
class PageEntry {
  FocusNode? node;

  /// Receives a printable character typed while focus is outside any text
  /// field (a Search page moves it into its field, DESIGN_SPEC §6.5).
  ValueChanged<String>? typeAhead;

  /// Clears [node] if it is still the registered one.
  void release(FocusNode other) {
    if (node == other) node = null;
  }
}

/// Provided by `AppPageRoute` around every page. A page registers its primary
/// [FocusNode] with [register]; the shell reads it back from the route.
class PageEntryFocus extends InheritedWidget {
  const PageEntryFocus({required this.entry, required super.child, super.key});

  final PageEntry entry;

  /// Call from `initState` (no dependency is created); keep the returned
  /// entry and [PageEntry.release] the node from `dispose`.
  static PageEntry? register(BuildContext context, FocusNode node) {
    final entry = context
        .getInheritedWidgetOfExactType<PageEntryFocus>()
        ?.entry;
    entry?.node = node;
    return entry;
  }

  @override
  bool updateShouldNotify(PageEntryFocus oldWidget) => false;
}
