import 'dart:async';
import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui/ui.dart';
import 'package:platform_services/platform_services.dart';

import 'cast_bridge.dart';
import 'subtitle_import.dart';
import 'playback_insight.dart';
import 'playback_session.dart';

typedef PlaybackSessionFactory = PlaybackSession Function(
  MediaItem media,
  SourceSpec source,
);

/// App-owned typed player route. Part 04 ch01-p02 deleted the named-route
/// `AppRoute`/`AppRouter` machinery this used to ride on; the player is now
/// opened as a direct root-navigator push (see `AppComposition._open` in
/// composition.dart), so this is just the small data carrier for that push.
/// Carries the [MediaItem] directly (ch04-p03): a provider-lookup-by-id was
/// only ever needed because the old fixture catalogue had no other way to
/// hand the item over; the real play flow already has it in hand.
final class PlayerRoute {
  const PlayerRoute(
    this.media,
    this.source, {
    this.markers = const <UiMarker>[],
    this.providerName,
  });

  final MediaItem media;
  final SourceSpec source;
  final List<UiMarker> markers;

  /// The provider the viewer picked the stream from, shown in the stats
  /// overlay.
  final String? providerName;
}

/// The app-owned seam between typed navigation and Part 04's player surface.
/// UI receives a controller and surface; it never receives a repository.
final class PlaybackRouteView extends StatefulWidget {
  const PlaybackRouteView({
    required this.media,
    required this.source,
    required this.createSession,
    required this.createVideoSurface,
    required this.logger,
    this.markers = const <UiMarker>[],
    this.providerName,
    this.defaultSubtitleScale = 1,
    this.setSystemUiMode = SystemChrome.setEnabledSystemUIMode,
    this.createCast,
    this.mediaSession,
    this.pickSubtitles,
    super.key,
  });

  /// The "Add subtitle file…" picker (injected so tests need no file dialog).
  final Future<List<({String name, Uri uri})>> Function()? pickSubtitles;

  /// Builds the cast controller for an opened session; null hides casting.
  final CastBridge Function(PlaybackSession session)? createCast;
  final MediaSessionService? mediaSession;
  final double defaultSubtitleScale;
  final AppLogger logger;
  final MediaItem media;
  final SourceSpec source;
  final String? providerName;
  final PlaybackSessionFactory createSession;
  final VideoSurface Function() createVideoSurface;
  final List<UiMarker> markers;
  final SystemUiModeSetter setSystemUiMode;

  @override
  State<PlaybackRouteView> createState() => _PlaybackRouteViewState();
}

final class _PlaybackRouteViewState extends State<PlaybackRouteView> {
  late PlaybackSession _session = widget.createSession(
    widget.media,
    widget.source,
  );
  Object? _error;
  StackTrace? _stack;
  bool _started = false;
  bool _opened = false;
  CastBridge? _cast;
  PlaybackController? _castController;
  StreamSubscription<PlaybackSessionSnapshot>? _updates;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    // A `late final` whose initializer throws is never marked initialized,
    // so re-reading `_session` after `_start()` caught that failure into
    // `_error` would re-run `widget.createSession` a second time (and, for
    // a factory that always throws, throw again — this time uncaught,
    // during element unmount). Only a session that actually started needs
    // disposing.
    unawaited(_updates?.cancel());
    unawaited(_cast?.dispose());
    unawaited(_clearMediaSession());
    if (_error == null || _started) unawaited(_session.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final AppFailure? failure = error == null
        ? _session.snapshot.failure
        : error is AppFailure
        ? error
        : UnexpectedFailure(cause: error, stack: _stack);
    final controller = _started ? _session.controller : null;
    // Latched: once the first frame has shown, later buffering or a failure
    // is the player's business, not the opening screen's.
    _opened =
        _opened ||
        (failure == null &&
            controller != null &&
            StreamOpeningStatus.isReady(_session.snapshot.playback));
    if (failure != null && _opened) {
      return ErrorView(
        failure: failure,
        logger: widget.logger,
        fullScreen: true,
      );
    }
    final media = widget.media;
    final snapshot = _error == null ? _session.snapshot : null;
    return StreamOpeningHost(
      ready: _opened,
      screen: StreamOpeningScreen(
        title: media.title,
        artwork: media.artwork,
        kind: media.kind,
        status: StreamOpeningStatus.from(
          strings: AppStrings.of(context),
          kind: widget.source.kind,
          source: snapshot?.source,
          playback: snapshot?.playback,
        ),
        failure: failure,
        onRetry: _retry,
        onBack: () => unawaited(Navigator.of(context).maybePop()),
      ),
      player: controller == null || failure != null
          ? null
          : _player(controller),
    );
  }

  Widget _player(PlaybackController controller) =>
      // Flutter hands remote media keys to the focused view and never on to the
      // system session, so the skip keys the player screen leaves unhandled are
      // applied here with the session's own skip amounts.
      Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          final position = controller.currentState.position;
          if (key == LogicalKeyboardKey.mediaFastForward ||
              key == LogicalKeyboardKey.mediaTrackNext) {
            unawaited(controller.seek(position + const Duration(seconds: 30)));
          } else if (key == LogicalKeyboardKey.mediaRewind ||
              key == LogicalKeyboardKey.mediaTrackPrevious) {
            final back = position - const Duration(seconds: 10);
            unawaited(
              controller.seek(back < Duration.zero ? Duration.zero : back),
            );
          } else {
            return KeyEventResult.ignored;
          }
          return KeyEventResult.handled;
        },
        child: PlayerScreen(
          key: const ValueKey<String>('composed-player-screen'),
          controller: controller,
          videoSurface: widget.createVideoSurface(),
          audioOutput: _session.audioOutput,
          stats: _statsSource(),
          cast: _cast,
          onAddSubtitleFiles:
              widget.pickSubtitles ??
              () => pickSubtitleFiles(strings: AppStrings.of(context)),
          markers: widget.markers,
          defaultSubtitleScale: widget.defaultSubtitleScale,
          setSystemUiMode: widget.setSystemUiMode,
        ),
      );

  PlayerStatsSource? _stats;
  StreamHandle? _statsHandle;

  /// One stable source per open stream (auto-play swaps the handle). The
  /// readers look at the session's current handle and controller when called,
  /// so a swap never leaves them reading a disposed one.
  PlayerStatsSource _statsSource() {
    final handle = _session.handle;
    if (_stats != null && identical(_statsHandle, handle)) return _stats!;
    _statsHandle = handle;
    final spec = _session.source;
    final networked =
        handle is TransportStatsProvider &&
        (spec.kind == SourceKind.httpUrl ||
            spec.kind == SourceKind.torrentMagnet ||
            spec.kind == SourceKind.torrentFile);
    return _stats = PlayerStatsSource(
      kind: spec.kind,
      uri: spec.uri,
      providerName: widget.providerName,
      readTransport: networked
          ? () => (handle as TransportStatsProvider).readStats()
          : null,
      readEngine: (names) async {
        final engine = _session.controller;
        return engine is EngineProperties
            ? (engine as EngineProperties).readProperties(names)
            : const <String, String>{};
      },
    );
  }

  void _bindCast() {
    _castController = _session.controller;
    _cast = widget.createCast?.call(_session);
  }

  /// Auto-play replaces the session's controller (and handle); the screen and
  /// the cast bridge must follow it, never keep the disposed one.
  void _onSessionUpdate(PlaybackSessionSnapshot _) {
    if (!mounted) return;
    if (!_started) {
      setState(() {});
      return;
    }
    final controller = _session.controller;
    unawaited(_publishMediaSession());
    if (_session.snapshot.failure != null) {
      setState(() {});
      return;
    }
    if (controller != _castController) {
      unawaited(_cast?.dispose());
      _cast = null;
      _castController = controller;
      if (controller != null) _cast = widget.createCast?.call(_session);
      setState(() {});
      return;
    }
    if (!_opened) setState(() {});
  }

  Future<void> _publishMediaSession() async {
    final service = widget.mediaSession;
    if (service == null || !mounted) return;
    final state = _session.snapshot.playback;
    try {
      if (state.failure != null || state.isCompleted) {
        await service.clear();
      } else {
        final media = _session.media;
        await service.updateNowPlaying(
          MediaSessionInfo(
            title: media.title,
            subtitle: media.subtitle,
            artworkUri: media.artwork,
            duration: state.duration,
            position: state.position,
            playing: state.isPlaying,
          ),
        );
      }
    } catch (error, stack) {
      widget.logger.error(
        'media session update failed',
        error: error,
        stack: stack,
      );
      if (mounted) {
        setState(() {
          _error = error;
          _stack = stack;
        });
      }
    }
  }

  Future<void> _clearMediaSession() async {
    try {
      await widget.mediaSession?.clear();
    } catch (error, stack) {
      widget.logger.error(
        'media session clear failed',
        error: error,
        stack: stack,
      );
    }
  }

  /// Opens the same stream again on a fresh session (Retry on the opening
  /// screen). The session being replaced is disposed first.
  Future<void> _retry() async {
    // An uninitialised `_session` (its factory threw) must not be read.
    final old = _error == null || _started ? _session : null;
    await _updates?.cancel();
    _updates = null;
    await _cast?.dispose();
    _cast = null;
    _castController = null;
    try {
      await old?.dispose();
      if (!mounted) return;
      _session = widget.createSession(widget.media, widget.source);
    } catch (error, stack) {
      widget.logger.error('playback retry failed', error: error, stack: stack);
      if (mounted) {
        setState(() {
          _error = error;
          _stack = stack;
          _started = false;
        });
      }
      return;
    }
    setState(() {
      _error = null;
      _stack = null;
      _started = false;
    });
    await _start();
  }

  Future<void> _start() async {
    try {
      _updates = _session.updates.listen(_onSessionUpdate);
      await _session.start();
      _bindCast();
      if (!mounted) return;
      _started = true;
      // The engine opens paused; picking a stream means "play it".
      await _session.controller!.play();
      await _publishMediaSession();
      if (mounted) setState(() {});
    } catch (error, stack) {
      widget.logger.error('playback start failed', error: error, stack: stack);
      if (mounted) {
        setState(() {
          _error = error;
          _stack = stack;
        });
      }
    }
  }
}

/// Hands a typed player route straight to [PlaybackRouteView] — the route
/// already carries its [MediaItem], so there is no provider to look it up
/// in (ch04-p03; see [PlayerRoute]'s doc comment).
final class ComposedPlayerRoute extends StatelessWidget {
  const ComposedPlayerRoute({
    required this.route,
    required this.createSession,
    required this.createVideoSurface,
    required this.logger,
    this.defaultSubtitleScale = 1,
    this.setSystemUiMode = SystemChrome.setEnabledSystemUIMode,
    this.createCast,
    this.mediaSession,
    super.key,
  });

  final CastBridge Function(PlaybackSession session)? createCast;
  final MediaSessionService? mediaSession;
  final double defaultSubtitleScale;
  final AppLogger logger;
  final PlayerRoute route;
  final PlaybackSessionFactory createSession;
  final VideoSurface Function() createVideoSurface;
  final SystemUiModeSetter setSystemUiMode;

  @override
  Widget build(BuildContext context) => PlaybackRouteView(
    media: route.media,
    source: route.source,
    createSession: createSession,
    createVideoSurface: createVideoSurface,
    logger: logger,
    markers: route.markers,
    providerName: route.providerName,
    defaultSubtitleScale: defaultSubtitleScale,
    setSystemUiMode: setSystemUiMode,
    createCast: createCast,
    mediaSession: mediaSession,
  );
}

/// The one place the app decides which [SettingCapability]s this device has,
/// from the probed [report] and the OS name ([os] is `Platform.operatingSystem`).
///
/// iOS offers the Kodi monitor selector even on a single touchscreen.
Set<SettingCapability> availableSettingCapabilities(
  CapabilityReport report, {
  required String os,
}) => <SettingCapability>{
  if (report.displayModeSwitching) SettingCapability.displayModeSwitching,
  // Kodi iOS 4.3/4.4/4.6: modes carry no refresh rate, so only resolution matches.
  if (report.displayModeSwitching && os != 'ios')
    SettingCapability.refreshRateControl,
  // Kodi iOS always offers Default/Touchscreen, even with one screen.
  // Kodi Windows/macOS 4.1 (videoscreen.monitor): Default + monitor names.
  if (os == 'ios' || os == 'windows' || os == 'macos')
    SettingCapability.multipleDisplays,
  if (report.hdrOutput) SettingCapability.hdrOutput,
  // Kodi macOS 1.5.8: offered only when the probe found a digital device.
  if (os == 'android' || report.audioPassthrough)
    SettingCapability.audioPassthrough,
  if (os == 'macos' || os == 'windows') SettingCapability.audioDeviceSelection,
  if (os == 'macos' || os == 'windows') SettingCapability.exclusiveAudio,
  if (os == 'macos' || os == 'windows') SettingCapability.desktopWindow,
  // iOS: GLES via EAGL only; Windows: Direct3D 11 only (Kodi 3.1).
  if (os != 'ios' && os != 'windows') SettingCapability.gpuBackend,
};

/// The app's Settings destination: the [SettingsScreen] with the app's real
/// settings and (once probed) capability report.
final class SettingsDestination extends StatefulWidget {
  const SettingsDestination({
    required this.settings,
    required this.probe,
    required this.logger,
    this.audioDevices,
    this.displayScreens,
    this.clearCache,
    this.insight,
    this.logDirectory,
    this.providersPage,
    super.key,
  });

  /// Settings → Providers page.
  final WidgetBuilder? providersPage;
  final String? logDirectory;
  final PlaybackInsight? insight;
  final AppSettings settings;
  final Future<CapabilityReport> Function() probe;

  final Future<List<AudioDevice>> Function()? audioDevices;
  final DisplayScreenService? displayScreens;

  /// Clears the stream cache; see `StreamSource.clearCache`.
  final Future<int> Function()? clearCache;
  final AppLogger logger;

  @override
  State<SettingsDestination> createState() => _SettingsDestinationState();
}

final class _SettingsDestinationState extends State<SettingsDestination> {
  late Future<(CapabilityReport, List<AudioDevice>)> _report = _load();
  StreamSubscription<DisplayScreens>? _displayEvents;
  StreamSubscription<SettingDef>? _displaySettings;
  StreamSubscription<SettingDef>? _audioSettings;
  DisplayScreens? _screens;
  final _displayChoices = ValueNotifier<Map<String, String>>(const {});
  Object? _displayError;
  Future<void> _selection = Future.value();

  @override
  void initState() {
    super.initState();
    _audioSettings = widget.settings.values.changes
        .where(
          (def) =>
              def.id == 'audio.passthroughDevice' ||
              def.id == 'audio.outputDevice',
        )
        .listen((_) {
          if (mounted) {
            setState(() {
              _report = _load();
            });
          }
        });
    final service = widget.displayScreens;
    if (service != null) {
      _displayEvents = service.changes.listen(
        _setScreens,
        onError: _setDisplayError,
      );
      _displaySettings = widget.settings.values.changes
          .where((def) => def.id == 'display.monitor')
          .listen((_) {
            final requested = widget.settings.values.read<String>(
              settingById('display.monitor'),
            );
            _selection = _selection
                .then((_) async {
                  if (!mounted) return;
                  final selected = await service.select(requested);
                  if (widget.settings.values.read<String>(
                        settingById('display.monitor'),
                      ) ==
                      requested) {
                    _setScreens(selected);
                    await _saveFallback(selected, requested: requested);
                  }
                })
                .catchError(
                  (Object error, StackTrace stack) => _setDisplayError(error),
                );
          });
    }
  }

  void _setScreens(DisplayScreens screens) {
    if (mounted) {
      _displayChoices.value = screens.choices;
      setState(() => _screens = screens);
    }
  }

  void _setDisplayError(Object error) {
    if (mounted) setState(() => _displayError = error);
  }

  Future<void> _saveFallback(
    DisplayScreens screens, {
    String? requested,
  }) async {
    final def = settingById('display.monitor');
    final current = widget.settings.values.read<String>(def);
    if ((requested == null || current == requested) &&
        current != screens.selected) {
      await widget.settings.values.write(def, screens.selected);
    }
  }

  Future<(CapabilityReport, List<AudioDevice>)> _load() async {
    final report = await widget.probe();
    final devices = await widget.audioDevices?.call() ?? const <AudioDevice>[];
    final service = widget.displayScreens;
    if (service != null) {
      final requested = widget.settings.values.read<String>(
        settingById('display.monitor'),
      );
      _screens = await service.select(requested);
      if (mounted) {
        _displayChoices.value = _screens!.choices;
        await _saveFallback(_screens!, requested: requested);
      }
    }
    return (report, devices);
  }

  @override
  void dispose() {
    unawaited(_displayEvents?.cancel());
    unawaited(_displaySettings?.cancel());
    unawaited(_audioSettings?.cancel());
    _displayChoices.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<(CapabilityReport, List<AudioDevice>)>(
        future: _report,
        builder: (context, snapshot) {
          final error = _displayError ?? snapshot.error;
          if (error != null) {
            return ErrorView(
              failure: error is AppFailure
                  ? error
                  : UnexpectedFailure(cause: error, stack: snapshot.stackTrace),
              logger: widget.logger,
            );
          }
          final result = snapshot.data;
          if (result == null) return const LoadingView();
          final (report, devices) = result;
          final insight = widget.insight;
          Widget screen(String? customNote) => SettingsScreen(
            logDirectory: widget.logDirectory,
            settingNotes: {'advanced.customMpvOptions': ?customNote},
            liveDiagnostics: insight?.rows,
            settings: widget.settings,
            capabilities: report,
            audioDevices: devices,
            displayChoices: _screens?.choices ?? const {},
            displayChoicesListenable: _displayChoices,
            onClearCache: widget.clearCache,
            providersPage: widget.providersPage,
            available: availableSettingCapabilities(
              report,
              os: report.diagnostics['os'] ?? Platform.operatingSystem,
            ),
          );
          return insight == null
              ? screen(null)
              : ValueListenableBuilder<String?>(
                  valueListenable: insight.customOptionsNote,
                  builder: (_, note, _) => screen(note),
                );
        },
      );
}
