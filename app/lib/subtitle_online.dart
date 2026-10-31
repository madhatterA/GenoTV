import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:content_sources/content_sources.dart';
import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:ui/ui.dart' show UiSubtitleResult, UiSubtitleSearch;

import 'subtitle_import.dart';

/// Player glue for online subtitles (Part 03 p04): search for the playing
/// title, download + unzip + stage the chosen one, and remember it per title.
class OnlineSubtitles {
  OnlineSubtitles({
    required this.search,
    required this.accounts,
    required this.choices,
    required this.logger,
  });

  final SubtitleSearch search;
  final SubtitleAccounts accounts;

  /// JSON map title-key -> {name, text}. ponytail: whole subtitle text is kept
  /// inline (~100 KB each); move to a cache dir if many titles pile up.
  final File choices;
  final AppLogger logger;

  final Map<String, SubtitleResult> _found = {};

  static const _serviceNames = {
    SubtitleAccounts.subdl: 'SubDL',
    SubtitleAccounts.subsource: 'SubSource',
    SubtitleAccounts.openSubtitles: 'OpenSubtitles',
  };

  static String _key(MediaItem m) =>
      '${m.imdbId ?? m.title}|${m.seasonNumber ?? ''}|${m.episodeNumber ?? ''}';

  Future<UiSubtitleSearch> find(MediaItem media, {String fileName = ''}) async {
    final out = await search.search(
      SubtitleQuery(
        imdbId: media.imdbId,
        tmdbId: media.tmdbId,
        title: media.title,
        year: media.year,
        season: media.seasonNumber,
        episode: media.episodeNumber,
        fileName: fileName,
      ),
    );
    // Every service failed (and at least one was tried): surface the failure.
    if (out.results.isEmpty && out.failures.isNotEmpty) {
      throw out.failures.values.first;
    }
    _found.clear();
    final results = <UiSubtitleResult>[];
    for (final r in out.results) {
      final id = '${r.service}-${r.ref}';
      _found[id] = r;
      results.add(
        UiSubtitleResult(
          id: r.ref,
          service: r.service,
          language: r.language,
          release: r.release,
          uploader: r.uploader,
          hearingImpaired: r.hearingImpaired,
        ),
      );
    }
    return UiSubtitleSearch(results, [
      for (final id in out.notSignedIn) _serviceNames[id] ?? id,
    ]);
  }

  /// Downloads, unzips (the right episode), stages and remembers the choice.
  Future<List<({String name, Uri uri})>> fetch(
    UiSubtitleResult picked,
    MediaItem media,
  ) async {
    final r = _found['${picked.service}-${picked.id}'];
    if (r == null) throw const ContentSourceFailure.notFound();
    final file = await search.download(r);
    final entry = pickEntry(
      _entries(file),
      media.seasonNumber,
      media.episodeNumber,
    );
    final staged = await stageSubtitles([entry]);
    // Remember the decoded text the player actually loaded.
    final text = await File.fromUri(staged.first.uri).readAsString();
    final saved = await _read();
    saved[_key(media)] = {'name': entry.name, 'text': text};
    await choices.parent.create(recursive: true);
    await choices.writeAsString(jsonEncode(saved), flush: true);
    return staged;
  }

  /// The subtitle chosen earlier for this title, staged again; empty if none.
  Future<List<({String name, Uri uri})>> remembered(MediaItem media) async {
    final saved = (await _read())[_key(media)];
    if (saved is! Map) return const [];
    return stageSubtitles([
      (
        name: '${saved['name']}',
        bytes: Uint8List.fromList(utf8.encode('${saved['text']}')),
      ),
    ]);
  }

  Future<Map<String, Object?>> _read() async {
    try {
      final json = jsonDecode(await choices.readAsString());
      if (json is Map) return Map<String, Object?>.of(json.cast());
    } on Object {
      // Missing or damaged file: nothing remembered yet.
    }
    return {};
  }

  static List<SubtitleEntry> _entries(({String name, Uint8List bytes}) file) {
    final isZip =
        file.bytes.length > 3 && file.bytes[0] == 0x50 && file.bytes[1] == 0x4b;
    return isZip
        ? readSubtitleZip(file.bytes)
        : [(name: file.name, bytes: file.bytes)];
  }

  /// The entry for [season]/[episode] (S01E02, 1x02, E02); the first entry when
  /// nothing matches or the title is a movie.
  static SubtitleEntry pickEntry(
    List<SubtitleEntry> entries,
    int? season,
    int? episode,
  ) {
    if (season == null || episode == null || entries.length == 1)
      return entries.first;
    final s = '$season', e = '$episode';
    final patterns = [
      RegExp('s0*$s[ ._-]?e0*$e(?!\\d)', caseSensitive: false),
      RegExp('(?<!\\d)0*${s}x0*$e(?!\\d)', caseSensitive: false),
      RegExp('(?<![a-z\\d])e0*$e(?!\\d)', caseSensitive: false),
    ];
    for (final p in patterns) {
      final hit = entries.where((x) => p.hasMatch(x.name));
      if (hit.isNotEmpty) return hit.first;
    }
    return entries.first;
  }
}
