import 'package:flutter/widgets.dart';

import '../l10n_gen/app_strings.dart';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';

import 'title_query.dart';

class HomeRow {
  const HomeRow({
    this.title = '',
    this.titleOf,
    required this.items,
    this.query,
  });

  final String title;
  final String Function(AppStrings)? titleOf;
  String titleIn(BuildContext context) =>
      titleOf?.call(AppStrings.of(context)) ?? title;
  final List<MediaItem> items;
  final TitleQuery? query;
}

/// Overall home-surface load state. Mirrors the four states the Phase's
/// Proof section names (`browse_home_test.dart` goldens): loading, content,
/// empty and error. `HomeScreen` renders exactly one of these at a time.
enum HomeLoadState { loading, content, empty, error }

/// Hero carousel capacity — `PlexHomeViewController.swift`'s curated hero
/// list is capped at 9 stable items; more than that reads as clutter, not a
/// paging control (decisions.md, Pass 8/Phase 01 Decisions table).
const int heroItemCap = 9;

class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
    required List<HomeRow> rows,
    this.loadState = HomeLoadState.content,
    this.failure,
    this.firstDeferredSectionReady = false,
    this.secondDeferredSectionReady = false,
    this.heroArtwork = const <String, Uri>{},
  }) : rows = List<HomeRow>.unmodifiable(
         // Each row's item list is copied growable so `upgradeItem` can
         // replace an entry in place (a later higher-quality hero result)
         // without recreating the row or its `FocusableCard` identities.
         rows.map(
           (row) => HomeRow(
             title: row.title,
             titleOf: row.titleOf,
             items: List<MediaItem>.of(row.items),
             query: row.query,
           ),
         ),
       );

  List<HomeRow> rows;

  /// Wide backdrop pictures by item id, used by the hero in place of the
  /// poster the shelves show.
  final Map<String, Uri> heroArtwork;
  HomeLoadState loadState;
  AppFailure? failure;
  bool firstDeferredSectionReady;
  bool secondDeferredSectionReady;

  MediaItem? _focusedItem;

  /// Curated hero candidates: the first row, capped at [heroItemCap]. A
  /// stable list — its identity/content doesn't change on focus changes,
  /// only on an explicit [upgradeItem] call, so shelves and hero focus
  /// nodes are never rebuilt just because the active item changed.
  List<MediaItem> get heroItems {
    if (rows.isEmpty) return const <MediaItem>[];
    final items = rows.first.items;
    return items.length <= heroItemCap ? items : items.sublist(0, heroItemCap);
  }

  /// The active hero item: whatever is focused, or the first hero
  /// candidate as a default so the hero never renders with no artwork/title
  /// before anything has been focused (e.g. on a phone layout with no
  /// autofocused row).
  MediaItem? get hero =>
      _focusedItem ?? (heroItems.isEmpty ? null : heroItems.first);

  void focus(MediaItem item) {
    if (_focusedItem == item) return;
    _focusedItem = item;
    notifyListeners();
  }

  /// Replaces an item already present in some row (matched by id) with a
  /// later, higher-quality result — e.g. an initial hero result upgraded
  /// once full metadata/artwork resolves. Does not recreate the row list or
  /// any other item; if the upgraded item is the current hero, the hero
  /// reference also upgrades.
  void upgradeItem(MediaItem updated) {
    for (final row in rows) {
      final index = row.items.indexWhere((item) => item.id == updated.id);
      if (index == -1) continue;
      row.items[index] = updated;
      if (_focusedItem?.id == updated.id) _focusedItem = updated;
      notifyListeners();
      return;
    }
  }

  /// Swaps in refreshed rows (e.g. Liked/Watched after returning from a
  /// page) on the live model, so the screen updates in place — no reload.
  void replaceRows(List<HomeRow> updated) {
    rows = List<HomeRow>.unmodifiable(
      updated.map(
        (row) => HomeRow(
          title: row.title,
          titleOf: row.titleOf,
          items: List<MediaItem>.of(row.items),
          query: row.query,
        ),
      ),
    );
    notifyListeners();
  }

  void markFirstDeferredSectionReady() {
    if (firstDeferredSectionReady) return;
    firstDeferredSectionReady = true;
    notifyListeners();
  }

  void markSecondDeferredSectionReady() {
    if (secondDeferredSectionReady) return;
    secondDeferredSectionReady = true;
    notifyListeners();
  }
}
