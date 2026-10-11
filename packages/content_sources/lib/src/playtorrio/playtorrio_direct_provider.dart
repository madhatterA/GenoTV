import 'dart:async';

import 'package:contracts/contracts.dart' hide StreamSource;
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:http/http.dart' as http;
import 'package:core/core.dart';

import '../content_source_failure.dart';
import '../stream_values.dart';
import 'models/stream_model.dart';
import '../routed_http_client.dart';
import 'pt_runtime.dart';
import 'sites/a111477.dart';
import 'sites/bcine.dart';
import 'sites/cinejoy.dart';
import 'sites/cinesrc.dart';
import 'sites/cinesu.dart';
import 'sites/downloadeverything.dart';
import 'sites/dulo.dart';
import 'sites/flaxmovies.dart';
import 'sites/flystream.dart';
import 'sites/fourkhdhub.dart';
import 'sites/frame.dart';
import 'sites/fsharetv.dart';
import 'sites/fsonic.dart';
import 'sites/fsonline.dart';
import 'sites/hexa.dart';
import 'sites/hindmoviez.dart';
import 'sites/kisskh.dart';
import 'sites/lmscript.dart';
import 'sites/lookmovie.dart';
import 'sites/mapple.dart';
import 'sites/megasource.dart';
import 'sites/meowtv.dart';
import 'sites/movienight.dart';
import 'sites/movy.dart';
import 'sites/multiembed.dart';
import 'sites/nova.dart';
import 'sites/peestream.dart';
import 'sites/purstream.dart';
import 'sites/rivestream.dart';
import 'sites/vadapav.dart';
import 'sites/vidapi.dart';
import 'sites/vidcore.dart';
import 'sites/videasy.dart';
import 'sites/vidfast.dart';
import 'sites/vidgod.dart';
import 'sites/vidlink.dart';
import 'sites/vidrock.dart';
import 'sites/vidsrc.dart';
import 'sites/vidup.dart';
import 'sites/vidvault.dart';
import 'sites/vidzee.dart';
import 'sites/vixsrc.dart';
import 'sites/vuflix.dart';
import 'sites/xdownloader.dart';
import 'sites/xpass.dart';
import 'sites/zxcstream.dart';
import 'stream_scraper.dart';

/// PlayTorrio V3's built-in direct (HTTP) scrapers, copied from upstream
/// (GPL-3.0, owner 2026-10-10), run through its own ScraperManager.
class PlaytorrioDirectProvider implements SourceProvider {
  PlaytorrioDirectProvider({required this.logger}) {
    ptLogger = logger;
    // Same scrapers, same order as PlayTorrio's _registerBuiltInScrapers,
    // minus Knaben/TorrentGalaxy (torrents; the Torrents provider has them).
    for (final scraper in <StreamScraper>[
      A111477Scraper(),
      VadapavScraper(),
      FourKHDHubScraper(),
      XDownloaderScraper(),
      VideasyScraper(),
      VidSrcScraper(),
      MultiEmbedScraper(),
      VidCoreScraper(),
      FlyStreamScraper(),
      MovieNightScraper(),
      DownloadEverythingScraper(),
      MovyScraper(),
      VuflixScraper(),
      RiveStreamScraper(),
      CinejoyScraper(),
      DuloScraper(),
      VidUpScraper(),
      FlaxMoviesScraper(),
      VidGodScraper(),
      VidFastScraper(),
      PeeStreamScraper(),
      LookMovieScraper(),
      HexaScraper(),
      BcineScraper(),
      MappleScraper(),
      NovaScraper(),
      MegaSourceScraper(),
      PurstreamScraper(),
      VidApiScraper(),
      VidRockScraper(),
      VidVaultScraper(),
      VidZeeScraper(),
      CineSrcScraper(),
      CineSuScraper(),
      FrameScraper(),
      FshareTvScraper(),
      FSonicScraper(),
      FSOnlineScraper(),
      KissKhScraper(),
      LMScriptScraper(),
      MeowTvScraper(),
      VidLinkScraper(),
      VixSrcScraper(),
      XPassScraper(),
      ZxcStreamScraper(),
      HindMoviezScraper(),
    ]) {
      ScraperManager.instance.registerScraper(scraper);
    }
  }

  final AppLogger logger;

  /// Fraction of sites that have answered for the running resolve, 0..1.
  ValueListenable<double> get progress => _progress;
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);
  Completer<void>? _cancelled;

  /// Stops every running scraper; the pending [resolve] fails with
  /// `provider.unavailable` (nobody is waiting for it any more).
  void cancel() {
    ScraperManager.instance.cancelActiveScrapes();
    if (_cancelled?.isCompleted == false) _cancelled!.complete();
  }

  @override
  String get id => 'playtorrio_direct';
  @override
  String get displayName => 'Playtorrio Direct';
  @override
  Future<MediaPage> browse(BrowseQuery query) async =>
      MediaPage(items: [], total: 0, hasMore: false);
  @override
  Future<MediaPage> search(String query, {int limit = 50}) async =>
      MediaPage(items: [], total: 0, hasMore: false);

  @override
  Future<List<SourceSpec>> resolve(MediaItem item) async {
    final isEpisode = item.kind == MediaKind.episode;
    if (isEpisode &&
        (item.seasonNumber == null || item.episodeNumber == null)) {
      throw const ContentSourceFailure.notFound('Choose an episode first.');
    }
    _progress.value = 0;
    final cancelled = _cancelled = Completer<void>();
    // Every scraper builds its http.Client inside the scrape, so this one
    // zone gives all of them the direct-first / backup-proxy routing.
    final scrape = http.runWithClient(
      () => ScraperManager.instance
          .scrapeAll(
            type: isEpisode ? 'series' : 'movie',
            title: item.title,
            year: item.year,
            season: item.seasonNumber,
            episode: item.episodeNumber,
            imdbId: item.imdbId,
            onProgress: (done, total) => _progress.value = done / total,
          )
          .toList(),
      RoutedHttpClient.new,
    );
    final sources = await Future.any(<Future<List<StreamSource>?>>[
      scrape,
      cancelled.future.then((_) => null),
    ]);
    if (sources == null) {
      logger.info('Resolve $id ${item.id}: cancelled');
      throw const ContentSourceFailure.unavailable('cancelled');
    }
    final specs = orderStreams(sources.map(_spec).whereType<SourceSpec>());
    if (specs.isEmpty) {
      logger.warn('Resolve $id ${item.id}: provider.not_found');
      throw const ContentSourceFailure.notFound();
    }
    logger.info('Resolved $id ${item.id}: ${specs.length} streams');
    return specs;
  }

  SourceSpec? _spec(StreamSource source) {
    if (!source.isHttpDirect) return null;
    final title = source.title ?? source.name ?? '';
    // PlayTorrio marks warnings (e.g. 111477's rate-limit notice) as fake
    // sources whose title starts with ⛔; they are not streams.
    if (title.startsWith('⛔')) return null;
    final uri = Uri.tryParse(source.url!);
    if (uri == null || !uri.scheme.startsWith('http')) return null;
    final file = uri.pathSegments.lastOrNull ?? '';
    final isFile = RegExp(
      r'\.(mp4|mkv|avi|webm|mov)$',
      caseSensitive: false,
    ).hasMatch(file);
    return SourceSpec(
      kind: uri.path.toLowerCase().endsWith('.m3u8')
          ? SourceKind.hlsUrl
          : SourceKind.httpUrl,
      uri: uri,
      headers: source.headers ?? const {},
      quality:
          parseQuality(source.quality) ??
          parseQuality(title) ??
          parseQuality(source.description),
      expectedBytes: source.sizeBytes?.round(),
      // Direct files show their own name; HLS links have none, so the
      // stream's title stands in for it.
      fileHint: isFile ? Uri.decodeComponent(file) : title,
      // `Site:` line: the play-source row shows it as the stream's name.
      label: [
        'Site: ${source.providerName ?? source.providerId ?? ''}',
        title,
      ].where((x) => x.isNotEmpty).join('\n'),
    );
  }

  @override
  Future<void> dispose() async => ScraperManager.instance.cancelActiveScrapes();
}
