import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/foundation.dart';

/// One search request. `search_view_model.dart`'s `SearchFunction` typedef
/// is reused so callers already wired to it (e.g. `SearchScreen`) do not
/// need a second function shape.
typedef LibrarySearchFunction = Future<List<MediaItem>> Function(String query);

/// A results group keyed by [MediaKind] — `PlexHomeViewController.swift`'s
/// search flow sections its hub results by kind (Movies / Shows / Episodes).
/// The key is the [kind] itself (stable across rebuilds/re-sorts), never a
/// list index, so headers/dividers built from it never move under a
/// concurrent update — `phase-03` step 4: "a new query must not briefly show
/// the old query's group title."
@immutable
class SearchResultGroup {
  const SearchResultGroup({required this.kind, required this.items});

  final MediaKind kind;
  final List<MediaItem> items;

  String get title => switch (kind) {
    MediaKind.movie => 'Movies',
    MediaKind.episode => 'Episodes',
    MediaKind.other => 'Other',
  };
}

enum LibrarySearchStatus { prompt, recents, loading, results, noResults, error }

/// Race-safe, threshold/debounced search over a library, matching
/// `SearchCells`/`PlexHomeViewController`'s recent-search UX (Decisions
/// table in `phase-03-library-search.md`):
///
/// - Below 2 trimmed characters: no request; show the prompt state, or up
///   to 10 deduplicated recents if any exist.
/// - At/above 2 characters: 350ms after the last keystroke, issue a search
///   tagged with a monotonically increasing request token. A result (or
///   error) is only applied if its token is still the latest AND the
///   normalized query it was issued for still matches the current input —
///   together these reject both an out-of-order completion (A→B, A lands
///   last) and a stale error arriving after a newer request.
/// - Activating a recent term runs immediately (no debounce) with a fresh
///   token.
/// - Retry re-issues the current query with a fresh token.
class LibrarySearchController extends ChangeNotifier {
  LibrarySearchController({
    required this.search,
    Duration debounce = const Duration(milliseconds: 350),
    this._recentCapacity = 10,
  }) : _debounceDuration = debounce;

  final LibrarySearchFunction search;
  final Duration _debounceDuration;
  final int _recentCapacity;

  Timer? _debounceTimer;
  int _token = 0;

  String _query = '';
  LibrarySearchStatus _status = LibrarySearchStatus.prompt;
  List<SearchResultGroup> _groups = const <SearchResultGroup>[];
  Object? _error;
  final List<String> _recents = <String>[];

  String get query => _query;
  LibrarySearchStatus get status => _status;
  List<SearchResultGroup> get groups =>
      List<SearchResultGroup>.unmodifiable(_groups);
  Object? get error => _error;
  List<String> get recents => List<String>.unmodifiable(_recents);

  /// Total result count across all groups — for callers that only need a
  /// flat count/list without caring about section boundaries.
  List<MediaItem> get flatResults =>
      _groups.expand((group) => group.items).toList(growable: false);

  void updateQuery(String value) {
    _query = value;
    _debounceTimer?.cancel();
    final normalized = _normalize(value);
    if (normalized.length < 2) {
      _token++; // invalidate any in-flight request
      _groups = const <SearchResultGroup>[];
      _error = null;
      _status = _recents.isEmpty
          ? LibrarySearchStatus.prompt
          : LibrarySearchStatus.recents;
      notifyListeners();
      return;
    }
    _status = LibrarySearchStatus.loading;
    _error = null;
    notifyListeners();
    final requestToken = ++_token;
    _debounceTimer = Timer(_debounceDuration, () {
      unawaited(_run(normalized, requestToken));
    });
  }

  /// Activates a recent term: populates [query] and runs immediately with
  /// no debounce (`phase-03` step 5).
  void activateRecent(String term) {
    _debounceTimer?.cancel();
    _query = term;
    final normalized = _normalize(term);
    if (normalized.length < 2) return;
    _status = LibrarySearchStatus.loading;
    _error = null;
    notifyListeners();
    unawaited(_run(normalized, ++_token));
  }

  /// Re-issues the current query with a fresh token.
  void retry() {
    final normalized = _normalize(_query);
    if (normalized.length < 2) return;
    _debounceTimer?.cancel();
    _status = LibrarySearchStatus.loading;
    _error = null;
    notifyListeners();
    unawaited(_run(normalized, ++_token));
  }

  Future<void> _run(String normalized, int requestToken) async {
    try {
      final results = await search(normalized);
      if (!_isCurrent(requestToken, normalized)) return;
      _applyResults(normalized, results);
    } catch (error) {
      if (!_isCurrent(requestToken, normalized)) return;
      _error = error;
      _status = LibrarySearchStatus.error;
      notifyListeners();
    }
  }

  bool _isCurrent(int requestToken, String normalized) =>
      requestToken == _token && normalized == _normalize(_query);

  void _applyResults(String normalized, List<MediaItem> results) {
    _remember(normalized);
    if (results.isEmpty) {
      _groups = const <SearchResultGroup>[];
      _status = LibrarySearchStatus.noResults;
      notifyListeners();
      return;
    }
    final byKind = <MediaKind, List<MediaItem>>{};
    for (final item in results) {
      (byKind[item.kind] ??= <MediaItem>[]).add(item);
    }
    // Stable kind order so a group's position never depends on which items
    // happened to arrive first.
    const order = <MediaKind>[
      MediaKind.movie,
      MediaKind.episode,
      MediaKind.other,
    ];
    _groups = <SearchResultGroup>[
      for (final kind in order)
        if (byKind[kind] case final items?)
          SearchResultGroup(kind: kind, items: items),
    ];
    _status = LibrarySearchStatus.results;
    notifyListeners();
  }

  void _remember(String normalized) {
    _recents.remove(normalized);
    _recents.insert(0, normalized);
    if (_recents.length > _recentCapacity) {
      _recents.removeRange(_recentCapacity, _recents.length);
    }
  }

  String _normalize(String value) => value.trim().toLowerCase();

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
