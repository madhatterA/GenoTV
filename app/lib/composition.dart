import 'dart:async';
import 'dart:io';

import 'package:content_sources/content_sources.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:persistence/persistence.dart';
import 'package:platform_services/platform_services.dart';
import 'package:playback/playback.dart';
import 'package:transport/transport.dart';
import 'package:ui/ui.dart' hide PlatformCapabilities;
import 'package:ui/ui.dart' as ui show PlatformCapabilities;

import 'cast_bridge.dart';
import 'audio_device_keep_alive.dart';
import 'catalogue_views.dart';
import 'provider_accounts.dart';
import 'source_cache.dart';
import 'source_prefetch.dart';
import 'fixture_provider.dart';
import 'platform_policy.dart';
import 'play_link.dart';
import 'play_flow.dart';
import 'player_settings.dart';
import 'transport_options.dart';
import 'playback_insight.dart';
import 'playback_session.dart';
import 'ui_bindings.dart';

/// The single Part 07 composition root. Playback is created per session by
/// [createPlaybackController], never at app startup.
final class AppComposition {
  AppComposition._({
    required this.logger,
    required this.logDirectory,
    required this.paths,
    required this.settings,
    required this.settingsStore,
    required this.capabilities,
    required this.isTv,
    required this.displayModes,
    required this.audio,
    required this.lifecycle,
    required this.window,
    required this.mediaSession,
    required this.streamSource,
    required this.linkResolver,
    required this.progressRepository,
    required this.favouritesRepository,
    required this.fixtureProvider,
    required this.providerHttp,
    required this.tmdbCatalogue,
    required this.thirtyNama,
    required this.digiMoviez,
    required this.cCloud,
    required this.playtorrioDirect,
    required this.torrents,
    required this.closeDatabase,
  });

  final AppLogger logger;

  /// Folder holding the rotating `app.log` files.
  final String logDirectory;
  final AppPaths paths;
  final AppSettings settings;
  final JsonSettingsStore settingsStore;
  final PlatformCapabilitiesService capabilities;
  final bool isTv;
  final DisplayModeServiceImpl displayModes;
  final AudioOutputServiceImpl audio;
  final PlaybackLifecycleService lifecycle;
  final WindowService window;
  final MediaSessionService mediaSession;
  final StreamSourceImpl streamSource;
  final LinkResolver linkResolver;
  late final RecentLinks recentLinks = RecentLinks(settingsStore);
  final ProgressRepository progressRepository;
  final FavouritesRepository favouritesRepository;
  final FixtureProvider fixtureProvider;
  final ProviderHttp providerHttp;
  final TmdbCatalogue tmdbCatalogue;
  final ThirtyNamaProvider thirtyNama;
  final DigiMoviezProvider digiMoviez;
  final CCloudProvider cCloud;
  final PlaytorrioDirectProvider playtorrioDirect;
  final TorrentSearchProvider torrents;
  final Future<void> Function() closeDatabase;

  /// Provider list for the play flow, in display order. MovieJavan has no
  /// `SourceProvider` yet — ch02-p04 is parked (ESCALATIONS.md) — so it
  /// renders as a permanently `failed` first row instead of a stub provider
  /// (CLAUDE.md anti-degradation: no dummy implementation stands in).
  List<PlayProviderEntry> get playProviders => <PlayProviderEntry>[
    const PlayProviderEntry(
      id: 'moviejavan',
      name: 'MovieJavan',
      unavailableMessage: 'MovieJavan streams are not added yet.',
    ),
    PlayProviderEntry(
      id: 'thirtynama',
      name: '30nama',
      provider: _byProtocol(thirtyNama),
    ),
    PlayProviderEntry(
      id: 'digimoviez',
      name: 'DigiMoviez',
      provider: _byProtocol(digiMoviez),
    ),
    PlayProviderEntry(
      id: 'ccloud',
      name: 'CCloud',
      provider: _byProtocol(cCloud),
    ),
    PlayProviderEntry(
      id: 'playtorrio_direct',
      name: 'Playtorrio Direct',
      provider: _byProtocol(playtorrioDirect),
      progress: playtorrioDirect.progress,
      cancel: playtorrioDirect.cancel,
    ),
    PlayProviderEntry(
      id: 'torrents',
      name: 'Torrents',
      provider: _byProtocol(torrents),
    ),
  ];

  SourceProvider _byProtocol(SourceProvider inner) =>
      ProtocolOrderedProvider(switch (_sourceCache) {
        final cache? => CachedSourceProvider(inner, cache),
        null => inner,
      }, () => settings.values.read<String>(settingById('streaming.protocol')));

  /// Saved stream lists (7 days, or until Refresh); set once in [create].
  SourceCache? _sourceCache;

  static Future<AppComposition> create({
    // Test-only overrides (ch04-p03's integration test injects loopback
    // fixture servers/files instead of the real TMDB/30nama/DigiMoviez
    // endpoints); production callers never pass these.
    Uri? omdbBaseUrl,
    Uri? tmdbBaseUrl,
    Uri? thirtyNamaSearchUrl,
    Uri? thirtyNamaActionUrl,
    File? thirtyNamaSessionFile,
    Uri? digiMoviezSiteRoot,
    Uri? digiMoviezApiRoot,
    File? digiMoviezSessionFile,
  }) async {
    final fileLog = RotatingFileLogSink();
    final logger = ConsoleLogger(
      sink: (record) {
        ConsoleLogger.developerSink(record);
        fileLog.write(record);
      },
    );
    final paths = AppPaths(logger: logger);
    final support = await paths.support;
    final logs = await paths.logs;
    final settingsStore = JsonSettingsStore(
      file: File('${support.path}${Platform.pathSeparator}settings.json'),
      logger: logger,
    );
    await settingsStore.load();
    final settings = AppSettings(settingsStore);
    fileLog.attach(logs, verbose: () => settings.verboseLogging);
    raiseOpenFileLimit(logger);
    final database = await openDatabase(paths: paths);
    final transportState = createTransportStateRepository(database, logger);
    final progressRepository = createProgressRepository(database, logger);
    final favouritesRepository = createFavouritesRepository(database, logger);
    final platformChannel = MethodPlatformChannel();
    final capabilities = PlatformCapabilitiesService(
      channel: platformChannel,
      logger: logger,
      passthroughDeviceId: Platform.isWindows
          ? () => settings.values.read<String>(
              settingById('audio.passthroughDevice'),
            )
          : null,
      outputDeviceId: Platform.isWindows
          ? () =>
                settings.values.read<String>(settingById('audio.outputDevice'))
          : null,
    );
    // Native Android detects TV once; the existing report carries the signal
    // without adding a shared contract (decisions.md Android TV detection ruling).
    final isTv = (await capabilities.probe()).diagnostics['isTv'] == 'true';
    final displayModes = DisplayModeServiceImpl(channel: platformChannel);
    late final AudioOutputServiceImpl audio;
    audio = AudioOutputServiceImpl(
      channel: platformChannel,
      planOverrides: () => audioPlanOverridesFor(
        settings.values,
        maxChannels: audio.maxOutputChannels,
      ),
      outputDeviceId: () =>
          settings.values.read<String>(settingById('audio.outputDevice')),
      passthroughDevice: Platform.isWindows
          ? () => settings.values.read<String>(
              settingById('audio.passthroughDevice'),
            )
          : null,
      exclusiveAudio: Platform.isWindows
          ? () => settings.values.read<bool>(settingById('audio.exclusiveMode'))
          : null,
    );
    final lifecycle = PlaybackLifecycleService(channel: platformChannel);
    final window = WindowService(channel: platformChannel);
    final mediaSession = MediaSessionService(channel: platformChannel);
    final mediaCache = await paths.mediaCache;
    final streamSource = StreamSourceImpl(
      logger: logger,
      cacheDir: mediaCache,
      state: transportState,
    );
    final fixtureProvider = await FixtureProvider.create(
      fixtureDirectory: mediaCache,
    );
    final providerHttp = ProviderHttp();
    final tmdbCatalogue = TmdbCatalogue(
      client: TmdbClient(http: providerHttp, baseUrl: tmdbBaseUrl),
      omdb: OmdbRatings(
        http: providerHttp,
        logger: logger,
        baseUrl: omdbBaseUrl,
      ),
    );
    final thirtyNama = ThirtyNamaProvider(
      http: providerHttp,
      logger: logger,
      sessionFile: thirtyNamaSessionFile,
      searchUrl: thirtyNamaSearchUrl,
      actionUrl: thirtyNamaActionUrl,
    );
    final digiMoviez = DigiMoviezProvider(
      http: providerHttp,
      logger: logger,
      sessionFile: digiMoviezSessionFile,
      siteRoot: digiMoviezSiteRoot,
      apiRoot: digiMoviezApiRoot,
    );
    final cCloud = CCloudProvider(http: providerHttp, logger: logger);
    final playtorrioDirect = PlaytorrioDirectProvider(logger: logger);
    final torrents = TorrentSearchProvider(
      searches: [
        KnabenSearch(http: providerHttp).search,
        TorrentGalaxySearch(http: providerHttp, logger: logger).search,
      ],
      logger: logger,
    );
    final app = AppComposition._(
      logger: logger,
      logDirectory: logs.path,
      paths: paths,
      settings: settings,
      settingsStore: settingsStore,
      capabilities: capabilities,
      isTv: isTv,
      displayModes: displayModes,
      audio: audio,
      lifecycle: lifecycle,
      window: window,
      mediaSession: mediaSession,
      streamSource: streamSource,
      linkResolver: LinkResolver(
        torrentDir: Directory(
          '${support.path}${Platform.pathSeparator}link-torrents',
        ),
      ),
      progressRepository: progressRepository,
      favouritesRepository: favouritesRepository,
      fixtureProvider: fixtureProvider,
      providerHttp: providerHttp,
      tmdbCatalogue: tmdbCatalogue,
      thirtyNama: thirtyNama,
      digiMoviez: digiMoviez,
      cCloud: cCloud,
      playtorrioDirect: playtorrioDirect,
      torrents: torrents,
      closeDatabase: database.close,
    );
    await app._followDisplays();
    moviePageHooks = (open: app._movieOpened, close: app._movieClosed);
    app._sourceCache = SourceCache(
      Directory('${support.path}${Platform.pathSeparator}source-cache'),
      logger,
    );
    unawaited(
      app._sourceCache!.prune().catchError(
        (Object error, StackTrace stack) => logger.warn(
          'source cache prune failed',
          error: error,
          stack: stack,
        ),
      ),
    );
    return app.._followFullscreen();
  }

  StreamSubscription<SettingDef>? _fullscreenSubscription;

  /// The Fullscreen mode setting drives the window: the saved value at start,
  /// then every change (live).
  void _followFullscreen() {
    final def = settingById('display.fullscreenMode');
    void apply() => unawaited(
      window
          .setFullscreen(fullscreenOf(settings.values))
          .catchError(
            (Object error, StackTrace stack) => logger.error(
              'setting fullscreen failed',
              error: error,
              stack: stack,
            ),
          ),
    );
    if (fullscreenOf(settings.values)) apply();
    _fullscreenSubscription = settings.values.changes
        .where((changed) => changed.id == def.id)
        .listen((_) => apply());
  }

  late final displayScreens = DisplayScreenService(channel: lifecycle.channel);
  StreamSubscription<DisplayScreens>? _displaySubscription;

  Future<void> _followDisplays() async {
    if (!Platform.isIOS && !Platform.isWindows && !Platform.isMacOS) return;
    final def = settingById('display.monitor');
    Future<void> save(DisplayScreens screens) async {
      if (settings.values.read<String>(def) != screens.selected) {
        await settings.values.write(def, screens.selected);
      }
    }

    await save(await displayScreens.select(settings.values.read<String>(def)));
    _displaySubscription = displayScreens.changes.listen(
      (screens) {
        // A saved screen that vanished falls back to the native selection.
        final saved = settings.values.read<String>(def);
        if (saved.isEmpty || screens.choices.containsKey(saved)) return;
        unawaited(
          save(screens).catchError(
            (Object error, StackTrace stack) => logger.error(
              'saving screen fallback failed',
              error: error,
              stack: stack,
            ),
          ),
        );
      },
      onError: (Object error, StackTrace stack) => logger.error(
        'screen notification failed',
        error: error,
        stack: stack,
      ),
    );
  }

  late final _audioDeviceKeepAlive = AudioDeviceKeepAlive(
    settings: settings.values,
    hdrPolicy: () => hdrPolicyOf(settings.values),
    create: (policy) =>
        createPlaybackControllerForLogger(logger, hdrPolicy: policy),
    logger: logger,
  );

  PlaybackController createPlaybackController() =>
      _audioDeviceKeepAlive.acquire();

  /// The episode after the current one in [episodes] (the list the detail
  /// screen loaded), resolved on the provider the viewer picked: the stream
  /// of the same quality, else the first. Null at the last episode.
  static Future<NextEpisode?> Function(MediaItem, SourceSpec) nextEpisodeFrom(
    List<MediaItem> episodes,
    PlayProviderEntry entry,
  ) => (current, source) async {
    final index = episodes.indexWhere((e) => e.id == current.id);
    final provider = entry.provider;
    if (index < 0 || index + 1 >= episodes.length || provider == null) {
      return null;
    }
    final next = episodes[index + 1];
    final streams = await provider.resolve(next);
    if (streams.isEmpty) return null;
    final chosen =
        streams.where((s) => s.quality == source.quality).firstOrNull ??
        streams.first;
    return (media: next, source: chosen);
  };

  final PlaybackInsight insight = PlaybackInsight();

  PlaybackSession createPlaybackSession({
    required MediaItem media,
    required SourceSpec source,
    Future<NextEpisode?> Function(MediaItem, SourceSpec)? nextSource,
  }) {
    final display = displayMatchingOf(settings.values);
    final policy = PlatformPolicy(
      capabilities: capabilities,
      displayModes: displayModes,
      audio: audio,
      events: lifecycle.events,
      mediaCommands: mediaSession.commands,
      acquireKeepAwake: () async {
        final lease = await lifecycle.acquireKeepAwake();
        return lease.release;
      },
      clearMediaSession: mediaSession.clear,
      diagnostics: DiagnosticsCollector(
        os: Platform.operatingSystem,
        appVersion: '1.0.0',
      ),
      displayModeMatchingEnabled: display.enabled,
      displayOptions: display.options,
      // Automatic (Part 08): negotiate passthrough wherever the platform
      // reports support.
      passthroughEnabled: true,
    );
    return PlaybackSession(
      media: media,
      source: source,
      streamSource: streamSource,
      progress: progressRepository,
      controllerFactory: createPlaybackController,
      releaseController: _audioDeviceKeepAlive.release,
      policy: policy,
      settings: settings,
      nextSource: nextSource,
      logger: logger,
      insight: insight,
    );
  }

  Widget buildApp() => StreamBuilder<SettingDef>(
    stream: settings.values.changes.where((d) => d.id == appLanguageSetting.id),
    builder: (_, _) => _app(),
  );

  Widget _app() => MaterialApp(
    onGenerateTitle: (context) => AppStrings.of(context).app_title,
    debugShowCheckedModeBanner: false,
    locale: localeForLanguage(settings.language),
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: AppStrings.localizationsDelegates,
    builder: (_, child) => keepLayoutLtr(
      BackdropGroup(
        child: AdaptiveBehavior(
          capabilities: isTv
              ? const ui.PlatformCapabilities.directionalPad()
              : const ui.PlatformCapabilities(),
          child: FavouritesScope(
            repository: favouritesRepository,
            child: NavigatorBackShortcuts(child: child!),
          ),
        ),
      ),
    ),
    theme: AppTheme.dark(tv: isTv),
    themeMode: ThemeMode.dark,
    home: AppShell(
      activeId: 'home',
      destinations: <AppDestination>[
        ...tmdbDestinations(
          catalogue: tmdbCatalogue,
          favourites: favouritesRepository,
          progress: progressRepository,
          onItemTap: _openDetail,
          logger: logger,
        ),
        AppDestination(
          id: 'play-link',
          label: lookupAppStrings(const Locale('en')).common_playLink,
          labelOf: (s) => s.common_playLink,
          icon: PhosphorIconsRegular.link,
          activeIcon: PhosphorIconsFill.link,
          builder: (context) => PlayLinkPage(
            recents: recentLinks,
            onPlay: (link) => _playLink(context, link),
            pickTorrent: () =>
                pickTorrentFile(label: AppStrings.of(context).play_torrent),
          ),
        ),
        AppDestination(
          id: 'settings',
          label: lookupAppStrings(const Locale('en')).common_settings,
          labelOf: (s) => s.common_settings,
          icon: PhosphorIconsRegular.gear,
          activeIcon: PhosphorIconsFill.gear,
          builder: (_) => SettingsDestination(
            settings: settings,
            probe: capabilities.probe,
            audioDevices: audio.devices,
            displayScreens:
                Platform.isIOS || Platform.isWindows || Platform.isMacOS
                ? displayScreens
                : null,
            clearCache: streamSource.clearCache,
            providersPage: (_) => providersPage(
              thirtyNama: thirtyNama,
              digiMoviez: digiMoviez,
              movieJavan: MovieJavanAccount(http: providerHttp, logger: logger),
              logger: logger,
            ),
            insight: insight,
            logger: logger,
            logDirectory: logDirectory,
          ),
        ),
      ],
    ),
  );

  /// The open movie page's prefetch (one at a time: a newer movie page
  /// replaces it, closing that page stops it).
  SourcePrefetch? _prefetch;

  void _movieOpened(MediaItem movie) {
    _prefetch?.stop();
    _prefetch = SourcePrefetch(movie, playProviders);
  }

  void _movieClosed(MediaItem movie) {
    if (_prefetch?.media.id != movie.id) return;
    _prefetch!.stop();
    _prefetch = null;
  }

  Future<void> _openDetail(BuildContext context, MediaItem item) =>
      openTmdbDetail(
        context,
        catalogue: tmdbCatalogue,
        item: item,
        onPlayMovie: _openPlayFlow,
        onPlayEpisode: _openPlayFlow,
        progress: progressRepository,
      );

  /// Plays a pasted or imported link and records it in Recent. Returns the
  /// message to show under the input when the link is not playable.
  Future<String?> _playLink(BuildContext context, String link) async {
    final ({SourceSpec spec, String? title}) prepared;
    try {
      prepared = await prepareLink(
        link,
        resolver: linkResolver,
        strings: AppStrings.of(context),
        recents: recentLinks,
        logger: logger,
      );
    } on PlayLinkFailure catch (failure) {
      return failure.message;
    }
    if (!context.mounted) return null;
    unawaited(
      _openPlayer(
        context,
        PlayerRoute(
          MediaItem(
            id: 'link:$link',
            title: prepared.title ?? link,
            kind: MediaKind.other,
          ),
          prepared.spec,
        ),
      ),
    );
    return null;
  }

  /// Pushes the play-flow screen (provider list -> stream list), then on a
  /// chosen [SourceSpec] pops it and opens the player with [media] passed
  /// directly (no provider lookup — see [PlayerRoute]'s doc comment).
  Future<void> _openPlayFlow(
    BuildContext context,
    MediaItem media, [
    List<MediaItem> episodes = const <MediaItem>[],
  ]) {
    // The link typed in "Insert link…"; it plays as [media], so progress is
    // saved against the title.
    SourceSpec? linkSpec;
    Widget buildFlow(BuildContext flowContext) => PlayFlowRoute(
      media: media,
      providers: playProviders,
      prefetch: _prefetch,
      forgetSaved: _sourceCache?.forget,
      logger: logger,
      onBack: () => Navigator.of(flowContext).pop(),
      onStreamSelected: (spec, entry) {
        Navigator.of(flowContext).pop();
        unawaited(
          _openPlayer(
            context,
            PlayerRoute(media, spec, providerName: entry.name),
            nextSource: nextEpisodeFrom(episodes, entry),
          ),
        );
      },
      pickTorrent: () =>
          pickTorrentFile(label: AppStrings.of(context).play_torrent),
      onPlayLink: (link) async {
        try {
          linkSpec = (await prepareLink(
            link,
            resolver: linkResolver,
            strings: AppStrings.of(context),
            recents: recentLinks,
            logger: logger,
            title: media.title,
          )).spec;
        } on PlayLinkFailure catch (failure) {
          return failure.message;
        }
        return null;
      },
      onLinkAccepted: () {
        Navigator.of(flowContext).pop();
        unawaited(_openPlayer(context, PlayerRoute(media, linkSpec!)));
      },
    );
    if (AdaptiveBehavior.of(context).formFactor == FormFactor.phone) {
      return showAppSheet<void>(context, buildFlow);
    }
    return Navigator.of(context, rootNavigator: true).push<void>(
      AppPageRoute<void>(fullscreenDialog: true, builder: buildFlow),
    );
  }

  /// Opens the player as a full-screen dialog on the root Navigator, above
  /// the shell — the same placement the old named `player` route gave it.
  Future<void> _openPlayer(
    BuildContext context,
    PlayerRoute route, {
    Future<NextEpisode?> Function(MediaItem, SourceSpec)? nextSource,
  }) => Navigator.of(context, rootNavigator: true).push<void>(
    AppPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => ComposedPlayerRoute(
        route: route,
        createSession: (media, source) => createPlaybackSession(
          media: media,
          source: source,
          nextSource: nextSource,
        ),
        createVideoSurface: createVideoSurface,
        logger: logger,
        defaultSubtitleScale: subtitleSizes[settings.defaultSubtitleSize]!,
        mediaSession: mediaSession,
        createCast: (session) => CastBridge(
          failedToCast: AppStrings.of(context).cast_failedToCast,
          service: createCastService(),
          controller: session.controller!,
          url: session.handle!.playbackUri,
          title: session.media.title,
          logger: logger.scoped('cast'),
          createAirPlay: platformAirPlay,
        ),
      ),
    ),
  );

  Future<void> dispose() async {
    await _audioDeviceKeepAlive.dispose();
    await _fullscreenSubscription?.cancel();
    await _displaySubscription?.cancel();
    await streamSource.dispose();
    await mediaSession.dispose();
    await lifecycle.dispose();
    audio.dispose();
    await capabilities.dispose();
    await displayModes.dispose();
    await fixtureProvider.dispose();
    await thirtyNama.dispose();
    await digiMoviez.dispose();
    await cCloud.dispose();
    await playtorrioDirect.dispose();
    await torrents.dispose();
    await tmdbCatalogue.dispose();
    providerHttp.close();
    await settingsStore.dispose();
    await closeDatabase();
  }
}

PlaybackController createPlaybackControllerForLogger(
  AppLogger logger, {
  HdrPolicy hdrPolicy = HdrPolicy.auto,
}) => createPlaybackController(logger: logger, hdrPolicy: hdrPolicy);

final class FixtureCatalogueView extends StatefulWidget {
  const FixtureCatalogueView({
    required this.provider,
    this.library = false,
    this.openPlayer,
    super.key,
  });

  final FixtureProvider provider;
  final bool library;

  /// Pushes the player route. `null` in tests that only exercise the
  /// catalogue (e.g. `composition_test.dart`'s home/library rendering).
  final Future<void> Function(BuildContext context, PlayerRoute route)?
  openPlayer;

  @override
  State<FixtureCatalogueView> createState() => _FixtureCatalogueViewState();
}

final class _FixtureCatalogueViewState extends State<FixtureCatalogueView> {
  late final Future<MediaPage> _page = widget.provider.browse(
    const BrowseQuery(limit: 20),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<MediaPage>(
    future: _page,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const LoadingView(fullScreen: true);
      }
      if (snapshot.hasError) {
        return ErrorView(
          failure: UnexpectedFailure(
            cause: snapshot.error,
            stack: snapshot.stackTrace,
          ),
          fullScreen: true,
        );
      }
      final items = snapshot.data?.items ?? const <MediaItem>[];
      if (widget.library) {
        return LibraryScreen(
          items: items,
          scope: BrowseScope.movies,
          onItemTap: (item) => unawaited(_open(item, context)),
        );
      }
      return HomeScreen(
        viewModel: HomeViewModel(
          rows: <HomeRow>[HomeRow(title: 'Fixture catalogue', items: items)],
        ),
        onItemTap: (item) => unawaited(_open(item, context)),
      );
    },
  );

  Future<void> _open(MediaItem item, BuildContext context) async {
    final sources = await widget.provider.resolve(item);
    if (!context.mounted || sources.isEmpty) return;
    final openPlayer = widget.openPlayer;
    if (openPlayer == null) return;
    await openPlayer(
      context,
      PlayerRoute(
        item,
        sources.first,
        markers: item.id == 'fixture-movie'
            ? const <UiMarker>[
                UiMarker(
                  id: 'fixture-intro',
                  kind: UiMarkerKind.intro,
                  start: Duration.zero,
                  end: Duration(seconds: 12),
                ),
                UiMarker(
                  id: 'fixture-credits',
                  kind: UiMarkerKind.credits,
                  start: Duration(seconds: 190),
                  end: Duration(seconds: 209),
                ),
              ]
            : const <UiMarker>[],
      ),
    );
  }
}
