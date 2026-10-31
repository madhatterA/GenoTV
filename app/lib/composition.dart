import 'dart:async';
import 'dart:io';

import 'storage_mirror.dart';

import 'package:content_sources/content_sources.dart';
import 'package:cast/dart_cast.dart' show CastService, CastDevice;
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
import 'subtitle_online.dart';
import 'source_cache.dart';
import 'source_prefetch.dart';
import 'platform_policy.dart';
import 'play_link.dart';
import 'play_flow.dart';
import 'player_settings.dart';
import 'android_log_sink.dart';
import 'transport_options.dart';
import 'playback_insight.dart';
import 'playback_session.dart';
import 'tv_input_log.dart';
import 'ui_bindings.dart';

/// The single Part 07 composition root. Playback is created per session by
/// [createPlaybackController], never at app startup.
/// tvOS has no document picker (no file_selector implementation); the import entry is replaced by a message.
/// Apple TV: Menu leaves the app at Home and the remote has a touch surface.
final bool isAppleTv = Platform.operatingSystem == 'tvos';
final bool _canPickFiles = Platform.operatingSystem != 'tvos';

final class AppComposition {
  AppComposition._({
    required this.logger,
    required this.logDirectory,
    required this.paths,
    required this.settings,
    required this.settingsStore,
    required this.domains,
    required this.tmdbKey,
    required this.capabilities,
    required this.isTv,
    required this.displayModes,
    required this.audio,
    required this.lifecycle,
    required this.window,
    required this.brightness,
    required this.mediaSession,
    required this._createStreamSource,
    required this.linkResolver,
    required this.progressRepository,
    required this.favouritesRepository,
    required this.providerHttp,
    required this.tmdbCatalogue,
    required this.movieJavanStreams,
    required this.thirtyNama,
    required this.digiMoviez,
    required this.cCloud,
    required this.playtorrioDirect,
    required this.torrents,
    required this.closeDatabase,
    this.crashLog,
  });

  final AppLogger logger;

  /// Folder holding the rotating `app.log` files.
  final String logDirectory;
  final CrashLog? crashLog;
  final AppPaths paths;
  final AppSettings settings;
  final JsonSettingsStore settingsStore;
  final DomainSettings domains;

  /// The user's own TMDB key (Settings > Title API); null value = built-in.
  final TmdbApiKey tmdbKey;
  final PlatformCapabilitiesService capabilities;
  final bool isTv;

  /// TV layout switch: the platform probe's `isTv` diagnostic, on every OS.
  static bool isTvFrom(Map<String, String> diagnostics) =>
      diagnostics['isTv'] == 'true';
  final DisplayModeServiceImpl displayModes;
  final AudioOutputServiceImpl audio;
  final PlaybackLifecycleService lifecycle;
  final WindowService window;
  final BrightnessService brightness;
  final MediaSessionService mediaSession;
  final StreamSourceImpl Function() _createStreamSource;
  StreamSourceImpl? _streamSource;
  StreamSourceImpl get streamSource => _streamSource ??= _createStreamSource();
  final LinkResolver linkResolver;
  late final RecentLinks recentLinks = RecentLinks(settingsStore);
  final ProgressRepository progressRepository;

  /// Tells Home that playback saved a position, so it re-reads its library rows.
  final LibraryChanges libraryChanges = LibraryChanges();
  final FavouritesRepository favouritesRepository;
  final ProviderHttp providerHttp;
  final FallbackTmdbCatalogue tmdbCatalogue;
  final ThirtyNamaProvider thirtyNama;
  final DigiMoviezProvider digiMoviez;
  final CCloudProvider cCloud;
  final PlaytorrioDirectProvider playtorrioDirect;
  final TorrentSearchProvider torrents;
  final Future<void> Function() closeDatabase;

  /// Provider list for the play flow, in display order.
  List<PlayProviderEntry> get playProviders => <PlayProviderEntry>[
    PlayProviderEntry(
      id: 'moviejavan',
      name: 'MovieJavan',
      provider: _byProtocol(_matched(movieJavanStreams, catalogue: true)),
    ),
    PlayProviderEntry(
      id: 'thirtynama',
      name: '30nama',
      provider: _byProtocol(_matched(thirtyNama)),
    ),
    PlayProviderEntry(
      id: 'digimoviez',
      name: 'DigiMoviez',
      provider: _byProtocol(_matched(digiMoviez)),
    ),
    PlayProviderEntry(
      id: 'ccloud',
      name: 'CCloud',
      provider: _byProtocol(_matched(cCloud, catalogue: true)),
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

  /// Part 06 p04: titles from the other Iranian catalogue play here too when
  /// the same title can be found (best effort; see [CrossMatchProvider]).
  SourceProvider _matched(SourceProvider inner, {bool catalogue = false}) =>
      CrossMatchProvider(
        inner: inner,
        cache: File(_crossMatchFile),
        catalogue: catalogue,
        imdbOf: _imdbOf,
      );

  String _crossMatchFile = '';

  /// IMDb id of a MovieJavan / CCloud title, from MovieJavan's own record.
  Future<String?> _imdbOf(MediaItem item) async {
    var ref = item.id;
    if (!ref.startsWith('moviejavan:')) {
      final found = matchTitle(
        item,
        (await movieJavanStreams.search(item.title)).items,
      );
      if (found == null) return null;
      ref = found.item.id;
    }
    final text = (await movieJavanStreams.detailOf(ref))['imdbid']?.toString();
    return text == null || !text.startsWith('tt') ? null : text;
  }

  SourceProvider _byProtocol(SourceProvider inner) =>
      ProtocolOrderedProvider(switch (_sourceCache) {
        final cache? => CachedSourceProvider(inner, cache),
        null => inner,
      }, () => settings.values.read<String>(settingById('streaming.protocol')));

  /// Saved stream lists (7 days, or until Refresh); set once in [create].
  SourceCache? _sourceCache;

  bool _disposed = false;
  bool _idleScheduled = false;
  Future<void> Function()? _idleWork;
  Future<void>? _idleReady;
  CastService? _idleCast;
  StreamSubscription<List<CastDevice>>? _idleCastDiscovery;
  (Object, StackTrace)? _castDiscoveryFailure;
  late final Future<void> _displayReady = _followDisplays();
  late final MovieJavanAccount movieJavan = MovieJavanAccount(
    http: providerHttp,
    logger: logger,
  );
  late final SubtitleAccounts subtitleAccounts = SubtitleAccounts(
    http: providerHttp,
    logger: logger,
  );
  late final OnlineSubtitles onlineSubtitles = OnlineSubtitles(
    search: SubtitleSearch(
      accounts: subtitleAccounts,
      http: providerHttp,
      logger: logger,
    ),
    accounts: subtitleAccounts,
    choices: File('${Platform.environment['HOME']}/.subtitle-choices.json'),
    logger: logger,
  );
  final MovieJavanProvider movieJavanStreams;
  late final Future<void> providerRestoration = restoreProviderAccounts(
    thirtyNama: thirtyNama,
    digiMoviez: digiMoviez,
    movieJavan: movieJavan,
  );

  void startAfterFirstFrame() {
    if (_idleScheduled) return;
    _idleScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _idleReady = Future(() async {
        if (_disposed) return;
        for (final weight in [
          FontWeight.w400,
          FontWeight.w500,
          FontWeight.w600,
          FontWeight.w700,
        ]) {
          final painter = TextPainter(
            text: TextSpan(
              text: 'ابپتثجچحخدذرزژسشصضطظعغفقکگلمنوهی ۰۱۲۳۴۵۶۷۸۹',
              style: TextStyle(
                fontFamily: 'Vazirmatn',
                package: 'ui',
                fontWeight: weight,
              ),
            ),
            textDirection: TextDirection.rtl,
          );
          try {
            painter.layout();
          } finally {
            painter.dispose();
          }
        }
        // Observe warm-up failures without consuming the Future awaited by UI.
        unawaited(
          providerRestoration.catchError((Object error, StackTrace stack) {
            logger.error('provider restore failed', error: error, stack: stack);
          }),
        );
        streamSource;
        _idleCast = createCastService();
        _idleCastDiscovery = _idleCast!.startDiscovery().listen(
          (_) {},
          onError: (Object error, StackTrace stack) {
            _castDiscoveryFailure = (error, stack);
            logger.error('cast discovery failed', error: error, stack: stack);
          },
        );
        await _idleWork?.call();
      });
      unawaited(
        _idleReady!.catchError((Object error, StackTrace stack) {
          logger.error('startup idle work failed', error: error, stack: stack);
        }),
      );
    });
  }

  CastService _takeCastService() {
    final service = _idleCast ?? createCastService();
    _idleCast = null;
    return service;
  }

  static Future<AppComposition> create({
    // Test-only overrides (ch04-p03's integration test injects loopback
    // fixture servers/files instead of the real TMDB/30nama/DigiMoviez
    // endpoints); production callers never pass these.
    CrashLog? crashLog,
    Uri? omdbBaseUrl,
    Uri? tmdbBaseUrl,
    Uri? movieJavanHost,
    Uri? ccloudRoot,
    Uri? thirtyNamaSearchUrl,
    Uri? thirtyNamaActionUrl,
    File? thirtyNamaSessionFile,
    Uri? digiMoviezSiteRoot,
    Uri? digiMoviezApiRoot,
    File? digiMoviezSessionFile,
    LogSink? extraLogSink,
  }) async {
    final fileLog = RotatingFileLogSink();
    RotatingFileLogSink? debugLog;
    final logger = ConsoleLogger(
      // Release builds drop debug records; the debug-log build keeps them.
      minimumLevel:
          genotvDebugLog || !const bool.fromEnvironment('dart.vm.product')
          ? LogLevel.debug
          : LogLevel.info,
      sink: (record) {
        ConsoleLogger.developerSink(record);
        writeAndroidLog(record);
        extraLogSink?.call(record);
        fileLog.write(record);
        debugLog?.write(record);
      },
    );
    final paths = AppPaths(logger: logger);
    final support = await paths.support;
    final logs = await paths.logs;
    final platformChannel = MethodPlatformChannel();
    final mirror = Platform.operatingSystem == 'tvos'
        ? StorageMirror(channel: platformChannel, logger: logger)
        : null;
    if (mirror != null) sessionDirectory = support;
    await mirror?.restoreFiles(support);
    final dbExisted = File('${support.path}${Platform.pathSeparator}app.db')
        .existsSync();
    final settingsStore = JsonSettingsStore(
      file: File('${support.path}${Platform.pathSeparator}settings.json'),
      logger: logger,
    );
    await settingsStore.load();
    final settings = AppSettings(settingsStore);
    // User-editable domains (phase 14): Title API list and per-provider domain.
    final domains = DomainSettings(
      settingsStore,
      titleDefaults: {
        'tmdb': Uri.parse('https://api.themoviedb.org'),
        'proxy': builtInBackupProxy,
        'ccloud': Uri.parse('https://server-hi-speed-iran.info'),
        'moviejavan': Uri.parse('http://cdntmp.dnstmp10.q5eapp.ir'),
      },
    );
    backupProxyOverride = domains.titleOverride('proxy');
    final tmdbKey = TmdbApiKey(
      File(
        '${(sessionDirectory ?? Directory(Platform.environment['HOME'] ?? '.')).path}/.tmdb-session.json',
      ),
    );
    await tmdbKey.load();

    final database = await openDatabase(paths: paths);
    if (mirror != null) {
      if (!dbExisted) await mirror.restoreDb(database);
      mirror.start(support, database);
    }
    final transportState = createTransportStateRepository(database, logger);
    final progressRepository = createProgressRepository(database, logger);
    final favouritesRepository = createFavouritesRepository(database, logger);
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
    // Native code detects TV once (Android, tvOS); the existing report carries
    // the signal without adding a shared contract (decisions.md Android TV ruling).
    final isTv = isTvFrom((await capabilities.probe()).diagnostics);
    // Decoded-picture memory cap: 120 MB on desktop, 60 MB on phone and TV.
    // Never raised afterwards (ch01 p06).
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        (isTv || Platform.isAndroid || Platform.isIOS ? 60 : 120) * 1024 * 1024;
    final artworkCache = Directory(
      '${(await paths.cache).path}${Platform.pathSeparator}artwork',
    )..createSync(recursive: true);
    await RoutedNetworkImage.useDiskCache(artworkCache, logger: logger);
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
    final brightness = BrightnessService(channel: platformChannel);
    final mediaSession = MediaSessionService(channel: platformChannel);
    final mediaCache = await paths.mediaCache;
    StreamSourceImpl createStreamSource() => StreamSourceImpl(
      logger: logger,
      cacheDir: mediaCache,
      state: transportState,
    );
    final providerHttp = ProviderHttp();
    final movieJavanStreams = MovieJavanProvider(
      http: providerHttp,
      logger: logger,
      host: movieJavanHost,
      domain: () => domains.provider('moviejavan'),
    );
    final cCloud = CCloudProvider(
      http: providerHttp,
      logger: logger,
      roots: ccloudRoot == null ? null : [ccloudRoot],
      domain: () => domains.provider('ccloud'),
    );
    // The title catalogue uses its own instances so a service's Title API
    // domain and its Provider domain never share a value.
    final movieJavanTitles = MovieJavanProvider(
      http: providerHttp,
      logger: logger,
      host: movieJavanHost,
      domain: () => domains.titleOverride('moviejavan'),
    );
    final cCloudTitles = CCloudProvider(
      http: providerHttp,
      logger: logger,
      roots: ccloudRoot == null ? null : [ccloudRoot],
      domain: () => domains.titleOverride('ccloud'),
    );
    // TMDB first; MovieJavan then CCloud when it (and the proxy) cannot be
    // reached (Part 06 limited mode).
    final tmdbCatalogue = FallbackTmdbCatalogue(
      tmdb: TmdbCatalogue(
        client: TmdbClient(
          http: providerHttp,
          baseUrl: tmdbBaseUrl,
          apiKey: () => tmdbKey.value,
        ),
        omdb: OmdbRatings(
          http: providerHttp,
          logger: logger,
          baseUrl: omdbBaseUrl,
        ),
      ),
      javan: movieJavanTitles,
      others: [cCloudTitles],
    );
    tmdbCatalogue.fallback.reorder(domains.titleOrder);
    domains.addListener(() {
      backupProxyOverride = domains.titleOverride('proxy');
      tmdbCatalogue.fallback.reorder(domains.titleOrder);
    });
    final thirtyNama = ThirtyNamaProvider(
      http: providerHttp,
      logger: logger,
      sessionFile: thirtyNamaSessionFile,
      searchUrl: thirtyNamaSearchUrl,
      actionUrl: thirtyNamaActionUrl,
      domain: () => domains.provider('thirtynama'),
    );
    final digiMoviez = DigiMoviezProvider(
      http: providerHttp,
      logger: logger,
      sessionFile: digiMoviezSessionFile,
      siteRoot: digiMoviezSiteRoot,
      apiRoot: digiMoviezApiRoot,
      domain: () => domains.provider('digimoviez'),
    );
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
      crashLog: crashLog,
      paths: paths,
      settings: settings,
      settingsStore: settingsStore,
      domains: domains,
      tmdbKey: tmdbKey,
      capabilities: capabilities,
      isTv: isTv,
      displayModes: displayModes,
      audio: audio,
      lifecycle: lifecycle,
      window: window,
      brightness: brightness,
      mediaSession: mediaSession,
      createStreamSource: createStreamSource,
      linkResolver: LinkResolver(
        torrentDir: Directory(
          '${support.path}${Platform.pathSeparator}link-torrents',
        ),
      ),
      progressRepository: progressRepository,
      favouritesRepository: favouritesRepository,
      providerHttp: providerHttp,
      tmdbCatalogue: tmdbCatalogue,
      movieJavanStreams: movieJavanStreams,
      thirtyNama: thirtyNama,
      digiMoviez: digiMoviez,
      cCloud: cCloud,
      playtorrioDirect: playtorrioDirect,
      torrents: torrents,
      closeDatabase: () async {
        // Transport queues its final resume before this persistence barrier.
        await transportState.dispose();
        await progressRepository.dispose();
        await mirror?.stop(support, database);
        await database.close();
      },
    );

    moviePageHooks = (open: app._movieOpened, close: app._movieClosed);
    persianPlotOf = (details) => persianPlot(
      tmdbFa: () async => details.item.tmdbId == null
          ? null
          : tmdbCatalogue.client.overviewFa(
              details.item.tmdbId!,
              isTv: details.item.kind != MediaKind.movie,
            ),
      movieJavan: () => app.movieJavanStreams.persianPlot(details.item),
      cCloud: () => cCloud.persianPlot(details.item),
      english: details.overview,
    );
    app._crossMatchFile =
        '${support.path}${Platform.pathSeparator}cross-match.json';
    app._sourceCache = SourceCache(
      Directory('${support.path}${Platform.pathSeparator}source-cache'),
      logger,
    );
    app._idleWork = () async {
      fileLog.attach(logs, verbose: () => settings.verboseLogging);
      raiseOpenFileLimit(logger);
      if (genotvDebugLog) {
        final android = await androidDebugInfo();
        debugLog = debugFileLogSink(
          android?.logs ?? logs,
          device: android?.device ?? Platform.operatingSystemVersion,
        );
      }
      await app._sourceCache!.prune().catchError(
        (Object error, StackTrace stack) => logger.warn(
          'source cache prune failed',
          error: error,
          stack: stack,
        ),
      );
    };
    return app.._followFullscreen();
  }

  StreamSubscription<SettingDef>? _fullscreenSubscription;

  /// Whether the window is fullscreen (the Fullscreen mode setting), live.
  late final ValueNotifier<bool> _fullscreenOn = ValueNotifier<bool>(
    fullscreenOf(settings.values),
  );

  void _setFullscreen(bool on) => unawaited(
    settings.values
        .write(
          settingById('display.fullscreenMode'),
          on ? 'Fullscreen' : 'Windowed',
        )
        .catchError(
          (Object error, StackTrace stack) => logger.error(
            'saving fullscreen mode failed',
            error: error,
            stack: stack,
          ),
        ),
  );

  /// Phone screen brightness for the player's left-half swipe; other
  /// platforms get no scope, so the swipe is not attached.
  Widget _withBrightness(Widget child) {
    if (isTv || !(Platform.isAndroid || Platform.isIOS)) return child;
    void report(Object error, StackTrace stack) =>
        logger.error('screen brightness failed', error: error, stack: stack);
    return BrightnessScope(
      current: () => brightness.current().catchError((Object e, StackTrace s) {
        report(e, s);
        return null;
      }),
      set: (level) => unawaited(brightness.set(level).catchError(report)),
      restore: () => unawaited(brightness.restore().catchError(report)),
      child: child,
    );
  }

  /// The player's last volume lives in the settings store, not in Settings.
  void _saveVolume(double volume) => unawaited(
    settingsStore
        .write('player.volume', volume.toStringAsFixed(2))
        .catchError(
          (Object error, StackTrace stack) =>
              logger.error('saving volume failed', error: error, stack: stack),
        ),
  );

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
        .listen((_) {
          _fullscreenOn.value = fullscreenOf(settings.values);
          apply();
        });
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
      onProgressSaved: libraryChanges.announce,
      controllerFactory: createPlaybackController,
      releaseController: _audioDeviceKeepAlive.release,
      policy: policy,
      settings: settings,
      // Android has no system font provider: only the bundled font draws.
      // Android and tvOS have no system font provider: the bundled font is the default.
      subtitleFont: Platform.isAndroid || Platform.operatingSystem == 'tvos'
          ? 'Vazirmatn'
          : 'DejaVu Sans',
      nextSource: nextSource,
      logger: logger,
      insight: insight,
    );
  }

  /// Apple TV only: swipes stop moving focus; the player scrubs with them.
  late final SiriRemote? siriRemote = isAppleTv
      ? (SiriRemote()
          ..start().catchError((Object error, StackTrace stack) {
            logger.error(
              'siri remote setup failed',
              error: error,
              stack: stack,
            );
          }))
      : null;

  void _logRemoteInput() {
    final remote = siriRemote;
    if (genotvDebugLog && remote != null) logTvInput(logger, remote);
  }

  Widget _tvScaled(Widget child) => isTv ? TvScale(child: child) : child;

  Widget buildApp() {
    _logRemoteInput();
    return StreamBuilder<SettingDef>(
      stream: settings.values.changes.where(
        (d) => d.id == appLanguageSetting.id,
      ),
      builder: (_, _) => _app(),
    );
  }

  Widget _app() => MaterialApp(
    onGenerateTitle: (context) => AppStrings.of(context).app_title,
    debugShowCheckedModeBanner: false,
    locale: localeForLanguage(settings.language),
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: AppStrings.localizationsDelegates,
    builder: (_, child) => keepLayoutLtr(
      // Windows draws video in a native window seen through a colour-keyed hole in the
      // Flutter view, so anything translucent over the video would blend with the key
      // colour: overlays there use their solid player-chrome colours.
      _tvScaled(
        UiAccessibility(
          reduceTransparency: Platform.isWindows,
          child: BackdropGroup(
            child: AdaptiveBehavior(
              capabilities: isTv
                  ? ui.PlatformCapabilities.directionalPad(
                      remoteTouches: siriRemote?.touches,
                    )
                  : const ui.PlatformCapabilities(),
              child: FavouritesScope(
                repository: favouritesRepository,
                // One-time hints: "seen" flags live in the settings store under
                // `hint.<id>`, not in the Settings screen.
                child: PlayScope(
                  play: (context, item) =>
                      unawaited(_openPlayFlow(context, item)),
                  child: HintsScope(
                    seen: (id) => settingsStore.read('hint.$id') == 'true',
                    markSeen: (id) => unawaited(
                      settingsStore
                          .write('hint.$id', 'true')
                          .catchError(
                            (Object error, StackTrace stack) => logger.error(
                              'saving hint flag failed',
                              error: error,
                              stack: stack,
                            ),
                          ),
                    ),
                    child: PlayerPrefsScope(
                      volume: () =>
                          double.tryParse(
                            settingsStore.read('player.volume') ?? '',
                          ) ??
                          1,
                      saveVolume: _saveVolume,
                      fullscreen: _fullscreenOn,
                      setFullscreen: _setFullscreen,
                      child: _withBrightness(
                        NavigatorBackShortcuts(child: child!),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    theme: AppTheme.dark(tv: isTv),
    themeMode: ThemeMode.dark,
    home: AppShell(
      activeId: 'home',
      exitOnRootBack: isAppleTv,
      destinations: <AppDestination>[
        ...tmdbDestinations(
          catalogue: tmdbCatalogue,
          favourites: favouritesRepository,
          progress: progressRepository,
          libraryChanged: libraryChanges,
          onItemTap: _openDetail,
          logger: logger,
          snapshot: paths.cache.then(
            (dir) =>
                File('${dir.path}${Platform.pathSeparator}home_snapshot.json'),
          ),
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
            pickTorrent: _canPickFiles
                ? () => pickTorrentFile(
                    label: AppStrings.of(context).play_torrent,
                  )
                : null,
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
            cacheUsedBytes: streamSource.cacheUsedBytes,
            providersPage: (_) => providersPage(
              thirtyNama: thirtyNama,
              digiMoviez: digiMoviez,
              movieJavan: movieJavan,
              subtitles: subtitleAccounts,
              restored: providerRestoration,
              logger: logger,
              domains: domains,
            ),
            titleApiPage: (_) => titleApiPage(domains, tmdbKey),
            insight: insight,
            logger: logger,
            logDirectory: logDirectory,
            crashLog: crashLog,
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

  static const _lastProviderKey = 'play.lastProvider';

  /// Remembers the provider whose stream just started playing, so the next
  /// play flow opens on it.
  void _rememberProvider(String id) => unawaited(
    settingsStore
        .write(_lastProviderKey, id)
        .catchError(
          (Object error, StackTrace stack) => logger.error(
            'saving last provider failed',
            error: error,
            stack: stack,
          ),
        ),
  );

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
      initialProviderId: settingsStore.read(_lastProviderKey),
      logger: logger,
      onBuy: (url) => openBuyUrl(url, logger),
      buyAsQr: Platform.operatingSystem == 'tvos',
      onBack: () => Navigator.of(flowContext).pop(),
      onStreamSelected: (spec, entry) {
        Navigator.of(flowContext).pop();
        unawaited(
          _openPlayer(
            context,
            PlayerRoute(media, spec, providerName: entry.name),
            nextSource: nextEpisodeFrom(episodes, entry),
            onStarted: () => _rememberProvider(entry.id),
            onChangeSource: () =>
                unawaited(_openPlayFlow(context, media, episodes)),
          ),
        );
      },
      pickTorrent: _canPickFiles
          ? () => pickTorrentFile(label: AppStrings.of(context).play_torrent)
          : null,
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
    VoidCallback? onStarted,
    VoidCallback? onChangeSource,
  }) async {
    await _idleReady;
    await _displayReady;
    final discoveryFailure = _castDiscoveryFailure;
    if (discoveryFailure != null) {
      Error.throwWithStackTrace(discoveryFailure.$1, discoveryFailure.$2);
    }
    await _idleCastDiscovery?.cancel();
    _idleCastDiscovery = null;
    if (!context.mounted) return;
    await Navigator.of(context, rootNavigator: true).push<void>(
      AppPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ComposedPlayerRoute(
          route: route,
          onStarted: onStarted,
          onChangeSource: onChangeSource,
          createSession: (media, source) => createPlaybackSession(
            media: media,
            source: source,
            nextSource: nextSource,
          ),
          createVideoSurface: createVideoSurface,
          logger: logger,
          defaultSubtitleScale: subtitleSizes[settings.defaultSubtitleSize]!,
          mediaSession: mediaSession,
          onlineSubtitles: onlineSubtitles,
          createCast: (session) => CastBridge(
            failedToCast: AppStrings.of(context).cast_failedToCast,
            service: _takeCastService(),
            controller: session.controller!,
            url: session.handle!.playbackUri,
            title: session.media.title,
            logger: logger.scoped('cast'),
            createAirPlay: platformAirPlay,
          ),
        ),
      ),
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    await _audioDeviceKeepAlive.dispose();
    await _fullscreenSubscription?.cancel();
    await _displaySubscription?.cancel();
    await _idleCastDiscovery?.cancel();
    await _idleCast?.dispose();
    await _streamSource?.dispose();
    await mediaSession.dispose();
    await lifecycle.dispose();
    audio.dispose();
    await capabilities.dispose();
    await displayModes.dispose();
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
