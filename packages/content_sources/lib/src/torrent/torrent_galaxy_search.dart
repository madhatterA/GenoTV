// Ported from PlayTorrioV3 lib/services/scraper/sites/torrent_galaxy.dart,
// commit 39b736f. GPL-3.0; see root README.md (Credits) and LICENSE.
import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;

import '../content_source_failure.dart';
import '../provider_http.dart';
import 'release_text.dart' as text;
import 'title_filter.dart';
import 'torrent_result.dart';

const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36';

class TorrentGalaxySearch {
  TorrentGalaxySearch({
    required this.http,
    required this.logger,
    this.baseUrl = 'https://torrentgalaxy.info',
  });

  final ProviderHttp http;
  final AppLogger logger;
  final String baseUrl;
  final _titleParser = ParseTorrentTitle();

  Future<List<TorrentResult>> search(MediaItem item) async {
    var query = item.title.trim();
    if (item.kind == MediaKind.movie && item.year != null) {
      query += ' ${item.year}';
    } else if (item.kind == MediaKind.episode && item.seasonNumber != null) {
      query += ' s${item.seasonNumber.toString().padLeft(2, '0')}';
    }
    // Non-200 and network errors throw from ProviderHttp (not returned as []).
    final body = await http.getText(
      Uri.parse('$baseUrl/get-posts/keywords:${Uri.encodeComponent(query)}'),
      headers: {'User-Agent': _userAgent},
    );
    final document = parser.parse(body);
    if (document.querySelector('.tgxtable') == null) {
      throw const ContentSourceFailure.invalidResponse(
        'TorrentGalaxy page has no results table',
      );
    }
    final details = <Future<TorrentResult?>>[];
    for (final row in document.querySelectorAll('.tgxtable .tgxtablerow')) {
      final link = row.querySelector('.tgxtablecell.clickable-row a[title]');
      final name = link?.attributes['title']?.trim() ?? '';
      final path = link?.attributes['href'] ?? '';
      if (name.isEmpty || path.isEmpty) continue;
      if (!matchesRequest(_titleParser.parse(name), item)) continue;
      final size = row.querySelector('.badge-secondary')?.text.trim() ?? '';
      final seeds = _seeders(row);
      final leechers = int.tryParse(
        row.querySelector('font[color="#ff0000"] b')?.text.trim() ?? '',
      );
      details.add(
        _detail(Uri.parse('$baseUrl$path'), name, size, seeds, leechers, item),
      );
    }
    final results = await Future.wait(details);
    final found = results.whereType<TorrentResult>().toList();
    if (details.isNotEmpty && found.isEmpty) {
      throw const ContentSourceFailure.unavailable(
        'Every TorrentGalaxy detail page failed',
      );
    }
    return found;
  }

  int _seeders(Element row) {
    final fonts = row.querySelectorAll('font[color="green"] b');
    return fonts.isEmpty ? 0 : int.tryParse(fonts.first.text.trim()) ?? 0;
  }

  Future<TorrentResult?> _detail(
    Uri url,
    String name,
    String size,
    int seeders,
    int? leechers,
    MediaItem item,
  ) async {
    try {
      final body = await http.getText(url, headers: {'User-Agent': _userAgent});
      final document = parser.parse(body);
      final magnet = document
          .querySelector('a[href^="magnet:"]')
          ?.attributes['href'];
      if (magnet == null || magnet.isEmpty) {
        // Changed from PlayTorrio: a detail page without a magnet is logged, not silent.
        logger.warn('TorrentGalaxy detail $url has no magnet link');
        return null;
      }
      return TorrentResult.fromMagnet(
        magnet,
        releaseName: name,
        source: 'TorrentGalaxy',
        sizeBytes: text.sizeBytes(size),
        seeders: seeders,
        leechers: leechers,
        fileName: document
            .querySelectorAll('#k1 .table_col1')
            .map((cell) => cell.text.trim())
            .where(
              (name) => RegExp(
                r'\.(?:mkv|mp4|avi|m4v|webm|mov)$',
                caseSensitive: false,
              ).hasMatch(name),
            )
            .where((name) => matchesRequest(_titleParser.parse(name), item))
            .firstOrNull,
      );
    } on Object catch (error, stack) {
      logger.warn(
        'TorrentGalaxy detail $url failed',
        error: error,
        stack: stack,
      );
      return null;
    }
  }
}
