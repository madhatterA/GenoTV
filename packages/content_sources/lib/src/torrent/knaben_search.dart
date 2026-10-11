// Ported from PlayTorrioV3 lib/services/scraper/sites/knaben.dart,
// commit 39b736f. GPL-3.0; see root README.md (Credits) and LICENSE.
import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:html/parser.dart' as parser;

import '../content_source_failure.dart';
import '../provider_http.dart';
import 'release_text.dart' as text;
import 'title_filter.dart';
import 'torrent_result.dart';

const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36';

class KnabenSearch {
  KnabenSearch({required this.http, this.baseUrl = 'https://knaben.org'});

  final ProviderHttp http;
  final String baseUrl;
  final _titleParser = ParseTorrentTitle();

  Future<List<TorrentResult>> search(MediaItem item) async {
    var query = item.title.trim();
    if (item.kind == MediaKind.movie && item.year != null) {
      query += ' ${item.year}';
    } else if (item.kind == MediaKind.episode && item.seasonNumber != null) {
      query += ' s${item.seasonNumber.toString().padLeft(2, '0')}';
    }
    final url = Uri.parse(
      '$baseUrl/search/${Uri.encodeComponent(query)}/0/1/seeders',
    );
    // Non-200 and network errors throw from ProviderHttp (not returned as []).
    final body = await http.getText(url, headers: {'User-Agent': _userAgent});
    final document = parser.parse(body);
    if (document.querySelector('table') == null) {
      throw const ContentSourceFailure.invalidResponse(
        'Knaben page has no results table',
      );
    }
    final results = <TorrentResult>[];
    for (final row in document.querySelectorAll('table tbody tr')) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 6) continue;
      final name = row.querySelector('.text-wrap.w-100 > a')?.text.trim() ?? '';
      final magnet =
          row.querySelector('a[href^="magnet:"]')?.attributes['href'] ?? '';
      if (name.isEmpty || magnet.isEmpty) continue;
      if (!matchesRequest(_titleParser.parse(name), item)) continue;
      final seeders =
          int.tryParse(cells[4].text.trim().replaceAll(',', '')) ?? 0;
      try {
        results.add(
          TorrentResult.fromMagnet(
            magnet,
            releaseName: name,
            source: 'Knaben',
            sourceProvider: cells.length > 6 ? cells[6].text.trim() : null,
            sizeBytes: text.sizeBytes(cells[2].text.trim()),
            seeders: seeders,
            leechers: int.tryParse(cells[5].text.trim().replaceAll(',', '')),
            fileName:
                RegExp(
                  r'\.(?:mkv|mp4|avi|m4v|webm|mov)$',
                  caseSensitive: false,
                ).hasMatch(name)
                ? name
                : null,
          ),
        );
      } on FormatException {
        // Changed from PlayTorrio: only a magnet without a usable info hash is
        // dropped (PlayTorrio's `infoHash == null` skip); anything else surfaces.
        continue;
      }
    }
    return results;
  }
}
