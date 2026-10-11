import 'dart:async';

import 'pt_runtime.dart';
import 'models/stream_model.dart';

abstract class StreamScraper {
  String get name;
  String get providerId =>
      runtimeType.toString().replaceAll('Scraper', '').toLowerCase();
  String get providerName => runtimeType.toString().replaceAll('Scraper', '');

  /// Yields sources progressively one-by-one as they are resolved.
  Stream<StreamSource> scrapeStream({
    required String type,
    required String title,
    int? year,
    int? season,
    int? episode,
    String? imdbId,
  }) async* {
    final list = await scrape(
      type: type,
      title: title,
      year: year,
      season: season,
      episode: episode,
      imdbId: imdbId,
    );
    for (final s in list) {
      yield s;
    }
  }

  /// Bulk scrape fallback.
  Future<List<StreamSource>> scrape({
    required String type,
    required String title,
    int? year,
    int? season,
    int? episode,
    String? imdbId,
  }) async {
    return [];
  }
}

class ScraperManager {
  ScraperManager._internal();
  static final ScraperManager instance = ScraperManager._internal();

  final List<StreamScraper> _scrapers = [];
  final List<StreamSubscription> _activeSubscriptions = [];
  bool get hasScrapers => _scrapers.isNotEmpty;

  void registerScraper(StreamScraper scraper) {
    if (!_scrapers.any((s) => s.runtimeType == scraper.runtimeType)) {
      _scrapers.add(scraper);
    }
  }

  void unregisterTorrentScrapers() {
    _scrapers.removeWhere((s) => s.name == 'PlayTorrio');
  }

  /// Cancels all ongoing scraper executions immediately.
  void cancelActiveScrapes() {
    if (_activeSubscriptions.isNotEmpty) {
      debugPrint(
        '[ScraperManager] Cancelling ${_activeSubscriptions.length} active scrapers...',
      );
      final subs = List<StreamSubscription>.from(_activeSubscriptions);
      _activeSubscriptions.clear();
      for (final sub in subs) {
        sub.cancel();
      }
    }
  }

  Stream<StreamSource> scrapeAll({
    required String type,
    required String title,
    int? year,
    int? season,
    int? episode,
    String? imdbId,
    // Added for Playtorrio Direct's progress bar: (scrapers done, total).
    void Function(int done, int total)? onProgress,
  }) {
    final controller = StreamController<StreamSource>();

    // PlayTorrio's custom provider order/enable screen and P2P switch are
    // not part of this app: its default mode (every registered scraper) and
    // no torrent sources, which the Torrents provider already covers.
    const p2pAllowed = false;
    const isCustom = false;
    final activeScrapers = List<StreamScraper>.of(_scrapers);

    if (activeScrapers.isEmpty) {
      controller.close();
      return controller.stream;
    }

    debugPrint(
      '[ScraperManager] Scraping across ${activeScrapers.length} active scrapers (${activeScrapers.map((s) => s.runtimeType).join(", ")}) for "$title" (P2P enabled: $p2pAllowed, Custom mode: $isCustom)...',
    );

    int pendingScrapers = activeScrapers.length;
    final seenHashes = <String>{};
    final seenUrls = <String>{};
    final List<StreamSubscription> currentRunSubs = [];

    void checkClose() {
      if (pendingScrapers <= 0 && !controller.isClosed) {
        controller.close();
      }
    }

    controller.onCancel = () {
      for (final s in currentRunSubs) {
        s.cancel();
      }
      _activeSubscriptions.removeWhere((s) => currentRunSubs.contains(s));
      currentRunSubs.clear();
    };

    for (final scraper in activeScrapers) {
      final sub = scraper
          .scrapeStream(
            type: type,
            title: title,
            year: year,
            season: season,
            episode: episode,
            imdbId: imdbId,
          )
          .listen(
            (rawSource) {
              if (controller.isClosed) return;

              final source =
                  (rawSource.providerId == null ||
                      rawSource.providerId!.isEmpty)
                  ? rawSource.copyWith(
                      providerId: scraper.providerId,
                      providerName: scraper.providerName,
                    )
                  : rawSource;

              // If P2P is disabled, strictly discard any torrent source
              if (!p2pAllowed &&
                  (source.addonName == 'PlayTorrio' ||
                      (source.infoHash != null &&
                          source.infoHash!.isNotEmpty))) {
                return;
              }

              // Torrent sources pass directly with deduplication
              if (source.infoHash != null && source.infoHash!.isNotEmpty) {
                final hashLower = source.infoHash!.toLowerCase();
                if (seenHashes.contains(hashLower)) return;
                seenHashes.add(hashLower);
                controller.add(source);
                return;
              }

              final rawUrl = source.url ?? source.externalUrl;
              if (rawUrl != null && rawUrl.startsWith('http')) {
                if (seenUrls.contains(rawUrl)) return;
                seenUrls.add(rawUrl);
                // Emit immediately as streams are found so the UI displays them progressively!
                controller.add(source);
              } else {
                controller.add(source);
              }
            },
            onError: (Object e) =>
                debugPrint('${scraper.providerName} failed: $e'),
            onDone: () {
              pendingScrapers--;
              onProgress?.call(
                activeScrapers.length - pendingScrapers,
                activeScrapers.length,
              );
              checkClose();
            },
          );
      currentRunSubs.add(sub);
      _activeSubscriptions.add(sub);
    }

    return controller.stream;
  }
}
