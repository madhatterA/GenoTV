import 'dart:convert';
import 'dart:io';

import 'package:contracts/contracts.dart';

import 'content_source_failure.dart';

/// Title text with case, punctuation, a leading "the", roman numerals
/// (2nd word on) and Persian/Arabic letter and digit variants folded away.
String normTitle(String title) {
  var t = title
      .toLowerCase()
      .replaceAll('‌', '')
      .replaceAll('ي', 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll('&', ' and ');
  const digits = '۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩';
  t = t.replaceAllMapped(
    RegExp('[$digits]'),
    (m) => '${digits.indexOf(m[0]!) % 10}',
  );
  final words = t
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isNotEmpty && words.first == 'the') words.removeAt(0);
  const roman = {
    'ii': '2',
    'iii': '3',
    'iv': '4',
    'v': '5',
    'vi': '6',
    'vii': '7',
    'viii': '8',
    'ix': '9',
    'x': '10',
  };
  return [
    for (final (i, w) in words.indexed)
      if (i > 0 && roman.containsKey(w)) roman[w]! else w,
  ].join();
}

/// [normTitle] of the title without a subtitle ("X: Y", "X - Y") and without
/// trailing season / part markers.
String normStripped(String title) => normTitle(
  title
      .split(RegExp(r'\s[-–]\s|:'))
      .first
      .replaceAll(
        RegExp(
          r'\s(season|part|chapter|فصل|قسمت|پارت)\s*\d+\s*$',
          caseSensitive: false,
        ),
        '',
      ),
);

double _dice(String a, String b) {
  if (a == b) return 1;
  if (a.length < 2 || b.length < 2) return 0;
  final grams = <String, int>{};
  for (var i = 0; i < a.length - 1; i++) {
    grams.update(a.substring(i, i + 2), (n) => n + 1, ifAbsent: () => 1);
  }
  var common = 0;
  for (var i = 0; i < b.length - 1; i++) {
    final g = b.substring(i, i + 2);
    if ((grams[g] ?? 0) > 0) {
      grams[g] = grams[g]! - 1;
      common++;
    }
  }
  return 2 * common / (a.length + b.length - 2);
}

/// Fixed fuzzy threshold: wrong matches are worse than none.
const fuzzyThreshold = 0.92;

class TitleMatch {
  const TitleMatch(this.item, this.method);
  final MediaItem item;
  final String method;
}

final _persian = RegExp(r'[؀-ۿ]');

/// The one [candidates] entry that is [item], or null. Methods run in order
/// (IMDb id, title+year, Persian title+year, stripped title+year, year +-1,
/// fuzzy) and the first that yields exactly one candidate wins; two
/// candidates at one step is ambiguous and ends in no match. Candidates of
/// another kind never match, and a missing year never matches by title.
TitleMatch? matchTitle(MediaItem item, Iterable<MediaItem> candidates) {
  final pool = {
    for (final c in candidates)
      if (c.kind == item.kind && c.id != item.id) c.id: c,
  }.values.toList();
  final n = normTitle(item.title), s = normStripped(item.title);
  final y = item.year;
  final persian = _persian.hasMatch(item.title);
  final steps = <(String, bool Function(MediaItem))>[
    (
      'imdb',
      (c) =>
          item.imdbId != null &&
          c.imdbId?.toLowerCase() == item.imdbId!.toLowerCase(),
    ),
    if (y != null) ...[
      (
        persian ? 'persian+year' : 'title+year',
        (c) => c.year == y && normTitle(c.title) == n,
      ),
      ('stripped+year', (c) => c.year == y && normStripped(c.title) == s),
      (
        'year+-1',
        (c) =>
            c.year != null &&
            (c.year! - y).abs() == 1 &&
            normTitle(c.title) == n,
      ),
      (
        'fuzzy',
        (c) => c.year == y && _dice(normTitle(c.title), n) >= fuzzyThreshold,
      ),
    ],
  ];
  for (final (name, test) in steps) {
    final hits = pool.where(test).toList();
    if (hits.length == 1) return TitleMatch(hits.single, name);
    if (hits.length > 1) return null;
  }
  return null;
}

/// Lets a provider that cannot read another catalogue's titles still serve
/// them (Part 06 p04, best effort). For a `moviejavan:` / `ccloud:` title that
/// is not [inner]'s own:
/// - [catalogue] true: the same title is searched on [inner] and played from
///   there;
/// - else the IMDb id is filled in through [imdbOf] so IMDb-based providers
///   work.
/// Any failure to match leaves the call as it was. Confirmed matches are kept
/// in [cache] (title id -> provider title id) and tried first next time.
class CrossMatchProvider implements SourceProvider {
  CrossMatchProvider({
    required this.inner,
    required this.cache,
    this.catalogue = false,
    this.imdbOf,
  });

  final SourceProvider inner;
  final File cache;
  final bool catalogue;
  final Future<String?> Function(MediaItem)? imdbOf;

  @override
  String get id => inner.id;
  @override
  String get displayName => inner.displayName;
  @override
  Future<MediaPage> browse(BrowseQuery query) => inner.browse(query);
  @override
  Future<MediaPage> search(String query, {int limit = 50}) =>
      inner.search(query, limit: limit);

  @override
  Future<List<SourceSpec>> resolve(MediaItem item) async {
    final foreign =
        (item.id.startsWith('moviejavan:') || item.id.startsWith('ccloud:')) &&
        !item.id.startsWith('${inner.id}:');
    if (!foreign) return inner.resolve(item);
    return inner.resolve(await _map(item) ?? item);
  }

  Future<MediaItem?> _map(MediaItem item) async {
    try {
      if (!catalogue) {
        if (item.imdbId != null) return null;
        final imdb = await imdbOf?.call(item);
        return imdb == null ? null : _with(item, item.id, imdb);
      }
      final base = item.id.split(':').take(3).join(':');
      final key = '$base>${inner.id}';
      final saved = (await _read())[key];
      if (saved != null) {
        final hit = _with(item, _episodeId(saved, item));
        try {
          await inner.resolve(hit);
          return hit;
        } on ContentSourceFailure {
          // Stale cache entry: search again below.
        }
      }
      final found = matchTitle(item, (await inner.search(item.title)).items);
      if (found == null) return null;
      await _write(key, found.item.id);
      return _with(item, _episodeId(found.item.id, item));
    } on Object {
      // Best effort only: the title still plays from its own provider.
      return null;
    }
  }

  static String _episodeId(String id, MediaItem item) =>
      item.seasonNumber == null
      ? id
      : '$id:s${item.seasonNumber}e${item.episodeNumber}';

  MediaItem _with(MediaItem i, String id, [String? imdb]) => MediaItem(
    id: id,
    title: i.title,
    kind: i.kind,
    duration: i.duration,
    artwork: i.artwork,
    subtitle: i.subtitle,
    imdbId: imdb ?? i.imdbId,
    tmdbId: i.tmdbId,
    year: i.year,
    seasonNumber: i.seasonNumber,
    episodeNumber: i.episodeNumber,
    originalLanguage: i.originalLanguage,
  );

  Future<Map<String, String>> _read() async {
    try {
      return (jsonDecode(await cache.readAsString()) as Map).cast();
    } on Object {
      return {};
    }
  }

  Future<void> _write(String key, String value) async {
    final all = await _read()
      ..[key] = value;
    await cache.writeAsString(jsonEncode(all));
  }

  @override
  Future<void> dispose() => inner.dispose();
}
