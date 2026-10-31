import '../l10n_gen/app_strings.dart';
import '../l10n/app_text.dart';

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:contracts/fakes.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../focus/input_router.dart';
import '../focus/ui_command.dart';
import '../models/ui_media.dart';
import '../navigation/back_dispatcher.dart';
import '../theme/rivulet_tokens.dart';
import 'player_chrome_controller.dart';
import 'player_control_rail.dart';
import '../cast/cast_ui.dart';
import '../components/app_icon_button.dart';
import '../components/app_sheet.dart';
import 'player_desktop_pill.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../platform/siri_remote.dart';
import 'player_gesture_surface.dart';
import 'player_prefs_scope.dart';
import 'level_hud.dart';
import 'seek_badge.dart';
import '../components/hints_scope.dart';
import 'player_panel_host.dart';
import 'player_phone_chrome.dart';
import 'player_state_views.dart';
import 'player_view_model.dart';
import 'swipe_scrub.dart';
import 'post_video_overlay.dart';
import 'progress_rail.dart';
import 'seek_controller.dart';
import 'shuttle_controller.dart';
import 'skip_marker_button.dart';
import 'subtitle_replay_controller.dart';
import 'thumbnail_preview_controller.dart';
import 'track_panel.dart';
import 'transport_control_button.dart';

import 'player_box_options.dart';
import 'stats/player_stats.dart';
import 'stats/stats_overlay.dart';
import 'stats/stats_popover.dart';

import '../components/app_dialog.dart';

typedef SystemUiModeSetter = Future<void> Function(SystemUiMode mode);

/// A deterministic player surface for the UI gallery and the route-only
/// preview used when the composition root has not supplied a real session.
/// The application composition replaces this with its media engine route.
class PreviewPlayerScreen extends StatefulWidget {
  const PreviewPlayerScreen({required this.mediaId, super.key});

  final String mediaId;

  @override
  State<PreviewPlayerScreen> createState() => _PreviewPlayerScreenState();
}

class _PreviewPlayerScreenState extends State<PreviewPlayerScreen> {
  late final FakePlaybackController _controller = FakePlaybackController()
    ..setDuration(const Duration(minutes: 96));

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: const ValueKey<String>('player-screen'),
    child: PlayerScreen(
      controller: _controller,
      videoSurface: const FakeVideoSurface(),
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// One never-recreated [VideoSurface] plus the chrome state machine around
/// it (phase file `phase-01-player-scaffold.md`). The surface is built once
/// per session — identified by [controller] identity, matching the
/// Decisions table's "Surface lifetime: Create once per opened media
/// session" (`PlayerContainerViewController.swift`: one container per
/// player push) — and is never rebuilt by chrome/position/mode changes.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    required this.controller,
    required this.videoSurface,
    this.title = '',
    this.eyebrow,
    this.rating,
    this.runtimeLabel,
    this.audioLabel,
    this.compatibilityNotice,
    this.backDispatcher,
    this.setSystemUiMode = SystemChrome.setEnabledSystemUIMode,
    this.onExit,
    this.onRetry,
    this.onChangeSource,
    this.onSubtitles,
    this.onAudioTrack,
    this.onInfo,
    this.onInsights,
    this.onUpNext,
    this.onFilter,
    this.onReplayLongPress,
    this.markers = const <UiMarker>[],
    this.defaultSubtitleScale = 1,
    this.autoSkipDuration,
    this.thumbnailPreview,
    this.thumbnailPartId,
    this.nextTitle,
    this.nextArtwork,
    this.onPlayNext,
    this.onOpenShow,
    this.onOpenSeason,
    this.formFactor,
    this.audioOutput,
    this.cast,
    this.stats,
    this.sourceStatus,
    this.onAddSubtitleFiles,
    this.onSearchSubtitles,
    this.onFetchSubtitle,
    super.key,
  });

  /// "Add subtitle file…" in the Subtitles panel; null hides the row.
  final Future<List<({String name, Uri uri})>> Function()? onAddSubtitleFiles;

  /// Online subtitle search + fetch for the Options → Subtitles → Download list.
  final Future<UiSubtitleSearch> Function()? onSearchSubtitles;
  final Future<List<({String name, Uri uri})>> Function(UiSubtitleResult)?
  onFetchSubtitle;

  /// What and how to show in the download popover and the stats overlay;
  /// null hides both (and the "i" key).
  final PlayerStatsSource? stats;
  final SourceStatus? sourceStatus;

  final PlaybackController controller;
  final VideoSurface videoSurface;

  /// Null hides the cast button; non-null adds it and the casting chrome.
  final CastUiController? cast;

  /// Plain-text audio output for the Options → Info tab (app-supplied).
  final ValueListenable<String?>? audioOutput;
  final ThumbnailPreviewController? thumbnailPreview;
  final String? thumbnailPartId;
  final String? nextTitle;
  final ImageProvider? nextArtwork;
  final VoidCallback? onPlayNext;
  final VoidCallback? onOpenShow;
  final VoidCallback? onOpenSeason;

  /// TV/desktop/phone chrome selection (`platform/form_factor.dart`). `null`
  /// resolves from `AdaptiveBehavior.formFactorOf(context)`.
  final FormFactor? formFactor;

  /// Rail metadata (`player_control_rail.dart`'s `PlayerControlRail`).
  /// Content sourcing is out of this Part's scope (`CLAUDE.md`, "Out of
  /// scope"); defaults keep every pre-existing call site compiling.
  final String title;
  final String? eyebrow;
  final String? rating;
  final String? runtimeLabel;
  final String? audioLabel;

  /// Rail secondary-action callbacks — see `PlayerControlRail`'s own docs
  /// for why an action with no callback simply does not render.
  final VoidCallback? onSubtitles;
  final VoidCallback? onAudioTrack;
  final VoidCallback? onInfo;
  final VoidCallback? onInsights;
  final VoidCallback? onUpNext;
  final VoidCallback? onFilter;

  /// Fired on the subtitles rail button's long-press. When `null` (the
  /// common case), `PlayerScreen` supplies its own
  /// `SubtitleReplayController.invoke` — see the class doc comment on
  /// `subtitle_replay_controller.dart`. Passing a non-null override
  /// bypasses that controller entirely.
  final VoidCallback? onReplayLongPress;

  /// Skip-intro/credits/commercial markers for [SkipMarkerButton]. Empty by
  /// default — content sourcing is out of this Part's scope (`CLAUDE.md`,
  /// "Out of scope"), so the caller supplies whatever it has.
  final List<UiMarker> markers;

  /// Subtitle size the app applies on open; shown as selected in Options.
  final double defaultSubtitleScale;

  /// Non-null enables the skip pill's auto-skip countdown fill for every
  /// marker (`SkipMarkerButton.autoSkipDuration`). `null` (the default)
  /// shows the pill with no countdown — Select is still required to skip.
  final Duration? autoSkipDuration;

  /// Device/route compatibility notice; Part 05's capability probing
  /// resolves the string, this only renders it
  /// (`UniversalPlayerViewModel.swift:153`).
  final String? compatibilityNotice;
  final BackDispatcher? backDispatcher;
  final SystemUiModeSetter setSystemUiMode;

  /// Called once, after the 400 ms exit fade completes. Defaults to
  /// popping the enclosing route, matching the prior behavior.
  final VoidCallback? onExit;

  /// "Try another source" on the error card: the app reopens the source list
  /// for the same title. Without it the button is hidden.
  final VoidCallback? onChangeSource;

  /// Retry action for the focused error overlay. Re-opening the source is
  /// Part 02/07's concern (non-goal: "No decoder/source opening logic"); the
  /// scaffold only clears its own chrome mode and forwards the request.
  final VoidCallback? onRetry;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  late PlayerChromeController _chrome;
  late PlayerViewModel _viewModel;

  /// Bumps when the chrome must rebuild: anything but a plain position tick.
  final _chromeTick = ValueNotifier<int>(0);
  Object? _chromeSignature;
  late final _options = ValueNotifier(
    PlayerOptionValues(subtitleScale: widget.defaultSubtitleScale),
  );
  StreamSubscription<PlaybackEvent>? _optionEvents;
  StreamSubscription<MediaInfo>? _mediaInfoSub;
  MediaInfo _mediaInfo = MediaInfo.empty;
  late SubtitleReplayController _replay;
  PlaybackFailure? _replayFailure;
  late SeekController _seek;
  late ShuttleController _shuttle;
  late final SwipeScrub _swipe = SwipeScrub(
    currentPosition: () => widget.controller.currentState.position,
    duration: () => widget.controller.currentState.duration,
  );
  StreamSubscription<SiriTouch>? _touchSub;
  Stream<SiriTouch>? _touchStream;
  Duration? _swipePreview;
  late InputRouter _input;
  final Stopwatch _inputClock = Stopwatch()..start();
  final GlobalKey<PostVideoOverlayState> _postVideoKey = GlobalKey();
  bool _postVideoSeen = false;
  VoidCallback? _unregisterBack;
  Widget? _surface;
  bool _restoredSystemUi = false;
  PlaybackFailure? _lastFailure;
  final FocusNode _panelOpenerNode = FocusNode(
    debugLabel: 'player-box-options',
  );
  final FocusNode _subtitleOpenerNode = FocusNode(
    debugLabel: 'player-box-subtitles',
  );
  final FocusNode _audioOpenerNode = FocusNode(debugLabel: 'player-box-audio');
  final FocusNode _castOpenerNode = FocusNode(debugLabel: 'player-box-cast');
  final FocusNode _statsOpenerNode = FocusNode(debugLabel: 'player-box-stats');
  PlayerStatsController? _stats;
  bool _showStats = false;

  final PlayerBadgeController _badge = PlayerBadgeController();
  final LevelHudController _levelHud = LevelHudController();
  final ValueNotifier<bool> _fill = ValueNotifier<bool>(false);
  BrightnessScope? _brightnessScope;
  double? _brightness;
  bool _brightnessTouched = false;
  final ValueNotifier<double> _volume = ValueNotifier<double>(1);
  double _premute = 1;
  PlayerPrefsScope? _prefs;
  TrackChoice? _lastSubtitle;
  bool _hintChecked = false;

  final _castLink = LayerLink();

  void _toggleStatsOverlay() {
    if (_stats == null) return;
    setState(() => _showStats = !_showStats);
  }

  GlobalKey<PlayerPanelHostState> _boxPanelKey = GlobalKey();
  String _boxPanel = 'options';
  FocusNode get _boxOpener => switch (_boxPanel) {
    'subtitles' => _subtitleOpenerNode,
    'audio' => _audioOpenerNode,
    'cast' => _castOpenerNode,
    'stats' => _statsOpenerNode,
    _ => _panelOpenerNode,
  };
  void _openBoxPanel(String panel) {
    final formFactor =
        widget.formFactor ?? AdaptiveBehavior.formFactorOf(context);
    if (panel == 'cast' && formFactor == FormFactor.tv) {
      _boxPanel = panel;
      _chrome.openPanel();
      unawaited(
        showAppDialog<void>(
          context: context,
          builder: (dialogContext) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppText(
                AppStrings.of(context).player_castTo,
                style: RivuletTokens.of(context).typeStyles.title,
              ),
              const SizedBox(height: RivuletSpacing.s16),
              CastPicker(
                controller: widget.cast!,
                dismiss: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        ).whenComplete(() {
          if (mounted) _chrome.closePanel();
        }),
      );
      return;
    }
    if (panel == 'cast' && formFactor == FormFactor.phone) {
      _boxPanel = panel;
      _chrome.openPanel();
      unawaited(
        showAppSheet<void>(
          context,
          (sheetContext) => Padding(
            padding: const EdgeInsets.all(RivuletSpacing.s24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  AppStrings.of(context).player_castTo,
                  style: RivuletTokens.of(context).typeStyles.title,
                ),
                const SizedBox(height: RivuletSpacing.s16),
                Flexible(
                  child: CastPicker(
                    controller: widget.cast!,
                    dismiss: () => Navigator.of(sheetContext).pop(),
                  ),
                ),
              ],
            ),
          ),
        ).whenComplete(() {
          if (mounted) _chrome.closePanel();
        }),
      );
      return;
    }
    if (_chrome.mode == ChromeMode.panel && _boxPanel == panel) {
      _boxPanelKey.currentState?.dismiss();
      return;
    }
    setState(() {
      _boxPanel = panel;
      _boxPanelKey = GlobalKey();
    });
    _chrome.openPanel();
  }

  final FocusNode _skipPillNode = FocusNode(debugLabel: 'skip-pill');
  final GlobalKey _railKey = GlobalKey(debugLabel: 'player-rail');
  double _railHeight = 0;
  bool _railMeasureScheduled = false;

  /// Reads the rail's laid-out height after the frame and rebuilds once if
  /// it changed — the skip pill is positioned relative to the rail's top
  /// edge (see `_buildChrome`).
  void _scheduleRailMeasure() {
    if (_railMeasureScheduled) return;
    _railMeasureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _railMeasureScheduled = false;
      if (!mounted) return;
      final height = _railKey.currentContext?.size?.height;
      if (height == null || height == _railHeight) return;
      setState(() => _railHeight = height.roundToDouble());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Apple TV: the touch surface scrubs here (and moves no focus anywhere).
    final touches = _isTv
        ? AdaptiveBehavior.capabilitiesOf(context).remoteTouches
        : null;
    if (touches == _touchStream) return;
    _touchStream = touches;
    unawaited(_touchSub?.cancel());
    _touchSub = touches?.listen(_onRemoteTouch);
  }

  /// When a pad touch began with the controls hidden: the touch itself shows
  /// the rail (scrub drift), which must not turn a skip click into navigation.
  DateTime? _touchBeganHiddenAt;

  void _onRemoteTouch(SiriTouch touch) {
    if (touch.phase == 'started') {
      _touchBeganHiddenAt = _chrome.visible ? null : DateTime.now();
    }
    if (_chrome.mode == ChromeMode.panel ||
        _chrome.mode == ChromeMode.postVideo) {
      return;
    }
    final event = _swipe.add(touch);
    if (event == null) return;
    switch (event) {
      case SwipeScrubEvent.update:
        _chrome.enterScrubbing();
        setState(() => _swipePreview = _swipe.preview);
      case SwipeScrubEvent.commit:
        final target = _swipe.preview!;
        _swipe.clear();
        _chrome.exitScrubbing();
        unawaited(widget.controller.seek(target));
        setState(() => _swipePreview = null);
      case SwipeScrubEvent.cancel:
        _chrome.exitScrubbing();
        setState(() => _swipePreview = null);
    }
  }

  @override
  void initState() {
    super.initState();
    _unregisterBack = widget.backDispatcher?.register(_handleBack);
    HardwareKeyboard.instance.addHandler(_keepControlsOnKey);
    WidgetsBinding.instance.addObserver(this);
    widget.setSystemUiMode(SystemUiMode.immersiveSticky);
    _bindSession(widget.controller);
    widget.thumbnailPreview?.addListener(_onChromeChanged);
    _stats = widget.stats == null
        ? null
        : PlayerStatsController(
            widget.stats!,
            readSourceStatus: () => widget.sourceStatus,
          );
  }

  void _bindSession(PlaybackController controller) {
    _optionEvents?.cancel();
    _mediaInfoSub?.cancel();
    _mediaInfo = MediaInfo.empty;
    _mediaInfoSub = controller.mediaInfo.listen(
      (info) => setState(() => _mediaInfo = info),
    );
    _options.value = PlayerOptionValues(
      subtitleScale: widget.defaultSubtitleScale,
    );
    _optionEvents = controller.events.listen((event) {
      if (event is MediaOpened) {
        _options.value = PlayerOptionValues(
          subtitleScale: widget.defaultSubtitleScale,
        );
      }
    });
    _chrome = PlayerChromeController(onExit: _exit);
    _viewModel = PlayerViewModel(controller: controller)
      ..chromeVisible = _chrome.visible;
    _replayFailure = null;
    _replay = SubtitleReplayController(
      controller: controller,
      onFailure: (error, stack) {
        _replayFailure = PlaybackFailure.trackSelectionFailed(
          trackId: 'Replay captions',
          cause: error,
          stack: stack,
        );
        _chrome.showError();
      },
    );
    _seek = SeekController(controller: controller);
    _shuttle = ShuttleController(controller: controller)
      ..addListener(_onChromeChanged);
    _input = InputRouter(onCommand: _handleCommand);
    _lastFailure = _viewModel.failure;
    _chrome.setPlaying(_viewModel.isPlaying);
    if (_lastFailure != null) _chrome.showError();
    _viewModel.addListener(_onPlaybackStateChanged);
    _chrome.addListener(_onChromeChanged);
    // The last volume carries over from the previous playback.
    final prefs = context.getInheritedWidgetOfExactType<PlayerPrefsScope>();
    _prefs = prefs;
    _brightnessScope = context.getInheritedWidgetOfExactType<BrightnessScope>();
    if (prefs != null) {
      _volume.value = prefs.volume().clamp(0.0, 1.0);
      if (_volume.value > 0) _premute = _volume.value;
      _applyVolume(_volume.value);
    }
  }

  @override
  void didUpdateWidget(covariant PlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stats != widget.stats) {
      _stats?.dispose();
      _stats = widget.stats == null
          ? null
          : PlayerStatsController(
              widget.stats!,
              readSourceStatus: () => widget.sourceStatus,
            );
      _showStats = _showStats && _stats != null;
    }
    if (oldWidget.thumbnailPreview != widget.thumbnailPreview) {
      oldWidget.thumbnailPreview?.removeListener(_onChromeChanged);
      widget.thumbnailPreview?.addListener(_onChromeChanged);
    }
    if (oldWidget.controller != widget.controller) {
      widget.thumbnailPreview?.onItemChanged();
      // Session replacement: tear the old session's subscription and
      // timers down completely before the new one is bound, so a late
      // event from the outgoing controller can never reach the new
      // session's chrome state (pitfall: "A late controller event after
      // dispose must be ignored").
      _viewModel.removeListener(_onPlaybackStateChanged);
      _viewModel.dispose();
      _chrome.removeListener(_onChromeChanged);
      _chrome.dispose();
      // Session/media change cleanup (pitfall list): the outgoing session's
      // replay window must never revert into the new one.
      _replay.dispose();
      _seek.dispose();
      _shuttle.removeListener(_onChromeChanged);
      _shuttle.dispose();
      _input.dispose();
      _postVideoSeen = false;
      _chromeSignature = null;
      _surface = null;
      _restoredSystemUi = false;
      _bindSession(widget.controller);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_keepControlsOnKey);
    _mediaKeyGuard?.cancel();
    unawaited(_touchSub?.cancel());
    _optionEvents?.cancel();
    _mediaInfoSub?.cancel();
    _options.value = PlayerOptionValues(
      subtitleScale: widget.defaultSubtitleScale,
    );
    _options.dispose();
    _viewModel.removeListener(_onPlaybackStateChanged);
    _restoreSystemUi();
    _unregisterBack?.call();
    _chrome.removeListener(_onChromeChanged);
    _chrome.dispose();
    _viewModel.dispose();
    _chromeTick.dispose();
    _replay.dispose();
    _seek.dispose();
    _shuttle.removeListener(_onChromeChanged);
    _shuttle.dispose();
    _input.dispose();
    widget.thumbnailPreview?.removeListener(_onChromeChanged);
    _panelOpenerNode.dispose();
    _subtitleOpenerNode.dispose();
    _castOpenerNode.dispose();
    _statsOpenerNode.dispose();
    _stats?.dispose();
    _audioOpenerNode.dispose();
    _skipPillNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    if (_brightnessTouched) _brightnessScope?.restore();
    _badge.dispose();
    _levelHud.dispose();
    _fill.dispose();
    _volume.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Built once per session and never again — see the class doc comment.
    // Neither the chrome mode, playback position, buffering, nor any
    // overlay change reaches this line on a later build.
    _surface ??= KeyedSubtree(
      key: const ValueKey<String>('video-surface'),
      child: widget.videoSurface.build(context, widget.controller),
    );
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final desktop =
        (widget.formFactor ?? AdaptiveBehavior.formFactorOf(context)) ==
        FormFactor.desktop;
    final phone =
        (widget.formFactor ?? AdaptiveBehavior.formFactorOf(context)) ==
        FormFactor.phone;
    if (!_hintChecked) {
      _hintChecked = true;
      if (_isTv) {
        showHintOnce(context, 'tvSeek', AppStrings.of(context).hint_tvSeek);
      }
    }
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (_, _) => _handleBack(),
      // `Material(type: transparency)`: `PlayerScreen` is pushed as a route
      // over `AppShell`'s own `Scaffold` in production, but nothing
      // guarantees that ancestor is present everywhere this widget is
      // mounted (goldens, previews, future hosts). Without a `Material`
      // ancestor, `IconButton`/`Icon` glyphs in the chrome below silently
      // paint as solid color blocks instead of throwing — reproduced in
      // isolation: identical chrome renders correctly under a `Scaffold`
      // and corrupts without one, with zero `FlutterError`/exception in
      // either case, matching `surface_goldens_test.dart`'s existing note
      // about `PreviewPlayerScreen` needing the same ancestor for text.
      // The screen should not depend on its host providing this.
      child: Material(
        type: MaterialType.transparency,
        child: PlayerGestureSurface(
          chromeVisible: _chrome.visible,
          enabled: _chrome.mode != ChromeMode.postVideo,
          // A tap on the video while a panel is open only closes the panel.
          onToggleChrome: () {
            if (_chrome.mode != ChromeMode.panel) return _chrome.toggle();
            final host = _boxPanelKey.currentState;
            host != null ? host.dismiss() : _chrome.closePanel();
          },
          onRevealChrome: _chrome.reveal,
          onPlayPause: () =>
              _emitCommand(UiCommandType.playPause, CommandSource.keyboard),
          onSeekBackward: () {
            _emitCommand(UiCommandType.stepSeekBackward, CommandSource.touch);
            _badge.showSeek(AppStrings.of(context), -_seek.tapSeekSeconds);
          },
          onSeekForward: () {
            _emitCommand(UiCommandType.stepSeekForward, CommandSource.touch);
            _badge.showSeek(AppStrings.of(context), _seek.tapSeekSeconds);
          },
          onVolumeSwipe: phone ? _swipeVolume : null,
          onBrightnessSwipe: phone && _brightnessScope != null
              ? (d) => unawaited(_swipeBrightness(d))
              : null,
          onSwipeEnd: phone ? () => _prefs?.saveVolume(_volume.value) : null,
          onPinch: phone ? _setFill : null,
          onScrubBackward: () => _emitCommand(
            UiCommandType.scrubNudgeBackward,
            CommandSource.keyboard,
          ),
          onScrubForward: () => _emitCommand(
            UiCommandType.scrubNudgeForward,
            CommandSource.keyboard,
          ),
          onScrubCommit: () =>
              _emitCommand(UiCommandType.selectDown, CommandSource.keyboard),
          onScrubCancel: () =>
              _emitCommand(UiCommandType.menuBack, CommandSource.keyboard),
          onToggleStats: _stats == null ? null : _toggleStatsOverlay,
          onKeySeek: desktop ? _seekKey : null,
          onKeyVolume: desktop ? _stepVolume : null,
          onToggleMute: desktop ? _toggleMute : null,
          onToggleFullscreen: desktop && _prefs != null
              ? _toggleFullscreen
              : null,
          onToggleSubtitles: desktop ? _toggleSubtitles : null,
          scrubActive: _shuttle.isActive,
          onTvKey: _isTv ? _handleTvKey : null,
          overlay: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              LivePlaybackState(
                live: _viewModel.live,
                child: AnimatedBuilder(
                  animation: Listenable.merge(<Listenable>[
                    _chrome,
                    _chromeTick,
                    ?widget.cast?.state,
                  ]),
                  builder: (context, _) => _buildChrome(context, reduceMotion),
                ),
              ),
              PlayerBadgeOverlay(controller: _badge),
              if (phone) LevelHud(controller: _levelHud),
            ],
          ),
          child: AnimatedBuilder(
            animation: _chrome,
            builder: (context, _) => AnimatedPadding(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              padding: _chrome.mode == ChromeMode.postVideo
                  ? EdgeInsets.fromLTRB(
                      RivuletSpacing.s48,
                      RivuletSpacing.s64 + RivuletSpacing.s32,
                      MediaQuery.sizeOf(context).width * 0.42,
                      RivuletSpacing.s64 * 2 + RivuletSpacing.s40,
                    )
                  : EdgeInsets.zero,
              child: _surface!,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChrome(BuildContext context, bool reduceMotion) {
    final state = _viewModel.state;
    final mode = _chrome.mode;
    final loading = _isLoading(state);
    final casting = widget.cast?.state.value.castingTo != null;
    final backVisible =
        mode != ChromeMode.exiting &&
        (_chrome.visible || mode == ChromeMode.error || casting);
    final railVisible =
        !casting &&
        _chrome.visible &&
        mode != ChromeMode.error &&
        mode != ChromeMode.postVideo &&
        mode != ChromeMode.exiting;
    final formFactor =
        widget.formFactor ?? AdaptiveBehavior.formFactorOf(context);
    final activeMarker = activeMarkerAt(widget.markers, state.position);
    final progressMarkers = widget.markers
        .map(
          (marker) => ProgressMarker(
            kind: switch (marker.kind) {
              UiMarkerKind.intro => ProgressMarkerKind.intro,
              UiMarkerKind.credits => ProgressMarkerKind.credits,
              UiMarkerKind.commercial => ProgressMarkerKind.commercial,
            },
            start: marker.start,
            end: marker.end,
          ),
        )
        .toList();
    final skipPillVisible =
        activeMarker != null &&
        mode != ChromeMode.panel &&
        mode != ChromeMode.error &&
        mode != ChromeMode.postVideo &&
        mode != ChromeMode.exiting;
    // `PlayerContainerViewController.swift:315-320,650-653`: the pill's
    // bottom is pinned to the rail's top edge plus
    // `skipPillRaisedOffset`/`skipPillLoweredOffset`. The rail's real
    // rendered height (it differs per form factor and content) is measured
    // after layout, so that becomes `railHeight - offset` from the screen's
    // bottom edge.
    if (activeMarker != null) _scheduleRailMeasure();
    final skipPillOffset = railVisible
        ? SkipMarkerButton.skipPillRaisedOffset
        : SkipMarkerButton.skipPillLoweredOffset;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // Buffering renders without ever removing the surface underneath.
        // Gone the moment mpv reports 100%, not after the 2 s exit delay.
        if ((state.isBuffering && (state.bufferingProgress ?? 0) < 1) ||
            loading)
          PlayerBufferingIndicator(
            progress: state.isBuffering ? (state.bufferingProgress ?? 0) : 0,
          ),
        if (!_viewModel.isPlaying)
          PlayerPauseScrim(presentation: _chrome.pausePresentation),
        if (loading) const PlayerLoadingLabel(),
        if (widget.compatibilityNotice case final message?
            when !loading && state.failure == null)
          PlayerCompatibilityNotice(message: message),
        // TV and phone's resting chrome have no boxed rail plate (owner
        // rejection, ch03-p02) — a soft bottom gradient scrim over the video
        // stands in for it, matching `evidence/part-04-rivulet/infuse-ref/
        // tvos/IMG_8303.jpg` and `ios/IMG_8298.PNG` (no opaque slab behind
        // the phone rail either). Desktop keeps the pill's own glass fill
        // instead (`PlayerDesktopPill`, which owns its whole background).
        if (formFactor == FormFactor.tv || formFactor == FormFactor.phone)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: formFactor == FormFactor.tv ? 460 : 220,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: railVisible ? 1 : 0,
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      // Measured from infuse-ref/tvos/IMG_8303.jpg: the
                      // gradient reads as nearly transparent at the top of
                      // its span and solidly dark by the rail, with most of
                      // the darkening concentrated in the bottom third —
                      // three stops (not two) reproduce that non-linear
                      // falloff instead of a flat linear ramp.
                      stops: const <double>[0, 0.55, 1],
                      colors: <Color>[
                        RivuletTokens.of(context).colors.playerScrim
                            .withValues(alpha: 0),
                        RivuletTokens.of(context).colors.playerScrim
                            .withValues(alpha: 0.35),
                        RivuletTokens.of(context).colors.playerScrim
                            .withValues(alpha: 0.88),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (mode != ChromeMode.postVideo)
          // Hides with the rest of the controls (same chrome timer); stays up
          // on the error screen and while casting, where it is the only exit.
          ExcludeFocus(
            excluding: _isTv && !backVisible,
            child: IgnorePointer(
              ignoring: !backVisible,
              child: AnimatedOpacity(
                opacity: backVisible ? 1 : 0,
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SafeArea(
                    child: Padding(
                      padding: _isTv
                          ? const EdgeInsets.only(
                              left: RivuletSpacing.tvSafeX,
                              top: RivuletSpacing.tvSafeY,
                            )
                          : const EdgeInsets.all(RivuletSpacing.s8),
                      child: AppIconButton(
                        key: const ValueKey<String>('player-back'),
                        glass: true,
                        icon: PhosphorIconsRegular.arrowLeft,
                        semanticLabel: AppStrings.of(context).player_close,
                        onActivate: _handleBack,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (formFactor == FormFactor.phone)
          IgnorePointer(
            ignoring: !railVisible,
            child: AnimatedOpacity(
              opacity: railVisible ? 1 : 0,
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              child: Center(
                child: PlayerPhonePrimaryTransport(
                  controller: widget.controller,
                  state: state,
                ),
              ),
            ),
          ),
        if (casting) CastingChrome(controller: widget.cast!),
        // `Positioned` must be a direct `Stack` child to take effect — it
        // cannot be returned from inside `_OverlayPanel.build` because that
        // build runs underneath `AnimatedOpacity`/`IgnorePointer`, neither
        // of which is a `Stack`.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ExcludeFocus(
            excluding: _isTv && !railVisible,
            child: IgnorePointer(
              ignoring: !railVisible,
              child: AnimatedOpacity(
                // TV: the 540 px frame cannot hold a panel and the rail, so
                // the rail fades out while a panel is open. It stays in the
                // tree, so focus returns to the opener on close.
                opacity: railVisible && !(_isTv && mode == ChromeMode.panel)
                    ? 1
                    : 0,
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                child: _OverlayPanel(
                  key: _railKey,
                  actions: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final panel in ['subtitles', 'audio', 'options'])
                        Padding(
                          padding: const EdgeInsets.only(
                            left: RivuletSpacing.s8,
                          ),
                          child: TransportControlButton(
                            key: ValueKey('player-box-$panel'),
                            focusNode: switch (panel) {
                              'subtitles' => _subtitleOpenerNode,
                              'audio' => _audioOpenerNode,
                              _ => _panelOpenerNode,
                            },
                            touchTargetEnabled:
                                railVisible && mode != ChromeMode.panel,
                            diameter: formFactor == FormFactor.tv ? 74 : 44,
                            iconSize: formFactor == FormFactor.tv ? 32 : 20,
                            icon: switch (panel) {
                              'subtitles' => PhosphorIconsRegular.subtitles,
                              'audio' => PhosphorIconsRegular.waveform,
                              _ => PhosphorIconsRegular.gear,
                            },
                            semanticLabel: switch (panel) {
                              'subtitles' => AppStrings.of(
                                context,
                              ).player_subtitles,
                              'audio' => AppStrings.of(context).player_audio,
                              _ => AppStrings.of(context).player_options,
                            },
                            onPress: () => _openBoxPanel(panel),
                            onLongPress: panel == 'subtitles'
                                ? (widget.onReplayLongPress ?? _replay.invoke)
                                : null,
                          ),
                        ),
                      if (formFactor == FormFactor.phone)
                        Padding(
                          padding: const EdgeInsets.only(
                            left: RivuletSpacing.s8,
                          ),
                          child: ValueListenableBuilder<bool>(
                            valueListenable: _fill,
                            builder: (context, on, _) => TransportControlButton(
                              key: const ValueKey('player-fill'),
                              touchTargetEnabled:
                                  railVisible && mode != ChromeMode.panel,
                              diameter: 44,
                              iconSize: 20,
                              icon: on
                                  ? PhosphorIconsRegular.arrowsIn
                                  : PhosphorIconsRegular.arrowsOut,
                              semanticLabel: on
                                  ? AppStrings.of(context).player_fitScreen
                                  : AppStrings.of(context).player_fillScreen,
                              onPress: () => _setFill(!on),
                            ),
                          ),
                        ),
                      if (widget.stats?.hasTransferStats ?? false)
                        Padding(
                          padding: const EdgeInsets.only(
                            left: RivuletSpacing.s8,
                          ),
                          child: TransportControlButton(
                            key: const ValueKey('player-box-stats'),
                            focusNode: _statsOpenerNode,
                            touchTargetEnabled:
                                railVisible && mode != ChromeMode.panel,
                            diameter: formFactor == FormFactor.tv ? 74 : 44,
                            iconSize: formFactor == FormFactor.tv ? 32 : 20,
                            icon: PhosphorIconsRegular.info,
                            semanticLabel: AppStrings.of(context)
                                .player_downloadInfo,
                            onPress: () => _openBoxPanel('stats'),
                          ),
                        ),
                      if (widget.cast != null)
                        Padding(
                          padding: const EdgeInsets.only(
                            left: RivuletSpacing.s8,
                          ),
                          child: CastButton(
                            anchorLink: _castLink,
                            focusNode: _castOpenerNode,
                            onPress: () => _openBoxPanel('cast'),
                            touchTargetEnabled:
                                railVisible && mode != ChromeMode.panel,
                            diameter: formFactor == FormFactor.tv ? 74 : 44,
                            iconSize: formFactor == FormFactor.tv ? 32 : 20,
                          ),
                        ),
                      if (widget.onUpNext != null)
                        Padding(
                          padding: const EdgeInsets.only(
                            left: RivuletSpacing.s8,
                          ),
                          child: TransportControlButton(
                            key: const ValueKey('rail-action-upNext'),
                            icon: PhosphorIconsRegular.stack,
                            semanticLabel: AppStrings.of(context).player_upNext,
                            touchTargetEnabled:
                                railVisible && mode != ChromeMode.panel,
                            diameter: formFactor == FormFactor.tv ? 74 : 44,
                            onPress: widget.onUpNext,
                          ),
                        ),
                    ],
                  ),
                  controller: widget.controller,
                  volume: _volume,
                  onVolumeChanged: (v) => _setVolume(v, save: false),
                  onVolumeChangeEnd: (v) => _prefs?.saveVolume(v),
                  extraActions:
                      (widget.cast == null ? 0 : 1) +
                      (formFactor == FormFactor.desktop && _prefs != null
                          ? 1
                          : 0) +
                      (formFactor == FormFactor.phone ? 1 : 0) +
                      ((widget.stats?.hasTransferStats ?? false) ? 1 : 0),
                  state: state,
                  formFactor: formFactor,
                  title: widget.title,
                  eyebrow: widget.eyebrow,
                  rating: widget.rating,
                  runtimeLabel: widget.runtimeLabel,
                  audioLabel: widget.audioLabel,
                  onSubtitles: widget.onSubtitles,
                  onAudioTrack: widget.onAudioTrack,
                  onInfo: widget.onInfo,
                  onInsights: widget.onInsights,
                  onUpNext: widget.onUpNext,
                  onNextEpisode: widget.onPlayNext,
                  onFilter: widget.onFilter,
                  onReplayLongPress: widget.onReplayLongPress ?? _replay.invoke,
                  markers: progressMarkers,
                  thumbnail: widget.thumbnailPreview?.currentThumbnail,
                  onScrubStart: _chrome.enterScrubbing,
                  onScrubUpdate: (position) {
                    final preview = widget.thumbnailPreview;
                    final partId = widget.thumbnailPartId;
                    if (preview != null && partId != null) {
                      unawaited(
                        preview.requestThumbnail(
                          partId: partId,
                          time: position,
                        ),
                      );
                    }
                  },
                  onScrubEnd: (position) {
                    _chrome.exitScrubbing();
                    widget.controller.seek(position);
                  },
                  previewPosition: _shuttle.isActive
                      ? _shuttle.previewPosition
                      : _swipePreview,
                ),
              ),
            ),
          ),
        ),
        if (_swipePreview != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: AppText(
                  key: const ValueKey<String>('swipe-scrub-time'),
                  formatProgressTime(_swipePreview!),
                  style: RivuletTokens.of(context).typeStyles.display,
                ),
              ),
            ),
          ),
        if (activeMarker != null && _railHeight > 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: _railHeight - skipPillOffset,
            child: IgnorePointer(
              ignoring: !skipPillVisible,
              child: AnimatedOpacity(
                key: const ValueKey<String>('skip-pill'),
                opacity: skipPillVisible ? 1 : 0,
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                // `PlayerContainerViewController.swift:299-303`: right-aligned
                // with the scrubber's right end, i.e. the rail's own
                // horizontal padding (14 compact, `railPadH` otherwise).
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: formFactor == FormFactor.phone
                          ? RivuletSpacing.s16
                          : RivuletTokens.of(context).geometry.railPadH,
                    ),
                    child: SkipMarkerButton(
                      marker: activeMarker,
                      position: state.position,
                      autoSkipDuration: widget.autoSkipDuration,
                      isPaused: !state.isPlaying || !skipPillVisible,
                      focusNode: _skipPillNode,
                      onDirectionalPress: (_) {
                        if (_chrome.visible) return false;
                        _chrome.reveal();
                        return true;
                      },
                      onSkip: () => widget.controller.seek(activeMarker.end),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (mode == ChromeMode.panel &&
            !(_boxPanel == 'cast' && formFactor != FormFactor.desktop))
          PlayerPanelHost(
            key: _boxPanelKey,
            opener: _boxOpener,
            anchorLink: _boxPanel == 'cast' ? _castLink : null,
            railKey: _railKey,
            panelWidth: _boxPanel == 'options' ? 560 : 320,
            fitContent: _boxPanel != 'options',
            alignToOpenerStart: _boxPanel != 'options',
            panelHeight: _boxPanel == 'options'
                ? MediaQuery.sizeOf(context).height -
                      2 * PlayerPanelGeometry.edgeInset
                : 400,
            title: switch (_boxPanel) {
              'subtitles' => AppStrings.of(context).player_subtitles,
              'audio' => AppStrings.of(context).player_audio,
              'cast' => AppStrings.of(context).player_castTo,
              'stats' => AppStrings.of(context).player_download,
              _ => AppStrings.of(context).player_options,
            },
            onDismissed: _chrome.closePanel,
            builder: (context, dismiss) => KeyedSubtree(
              key: const ValueKey('player-overlay'),
              child: _boxPanel == 'options'
                  ? PlayerBoxOptions(
                      options: _options,
                      mediaInfo: _mediaInfo,
                      audioOutput: widget.audioOutput,
                      controller: widget.controller,
                      state: state,
                      dismiss: dismiss,
                      onAddSubtitleFiles: widget.onAddSubtitleFiles,
                      onSearchSubtitles: widget.onSearchSubtitles,
                      onFetchSubtitle: widget.onFetchSubtitle,
                    )
                  : _boxPanel == 'cast'
                  ? CastPicker(controller: widget.cast!, dismiss: dismiss)
                  : _boxPanel == 'stats'
                  ? StatsPopover(
                      controller: _stats!,
                      onAdvanced: () {
                        dismiss();
                        setState(() => _showStats = true);
                      },
                    )
                  : TrackPanel(
                      controller: widget.controller,
                      state: state,
                      dismiss: dismiss,
                      showHeadings: false,
                      compact: true,
                      closeOnSelection: true,
                      onAddSubtitleFiles: widget.onAddSubtitleFiles,
                      type: _boxPanel == 'subtitles'
                          ? TrackType.subtitle
                          : TrackType.audio,
                    ),
            ),
          ),
        if (_showStats && _stats != null)
          Positioned(
            left: RivuletSpacing.s16,
            top: RivuletSpacing.s64,
            child: StatsOverlay(
              controller: _stats!,
              onClose: () => setState(() => _showStats = false),
            ),
          ),
        if (_shuttle.isActive && _shuttle.badge != null)
          Positioned(
            left: RivuletSpacing.tvSafeX,
            bottom: _railHeight + RivuletSpacing.s12,
            child: AppText(
              _shuttle.badge!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        if ((state.failure ?? _replayFailure) case final failure?
            when mode == ChromeMode.error)
          PlayerErrorOverlay(
            failure: failure,
            chrome: _chrome,
            onRetry: widget.onRetry,
            onTryAnotherSource: widget.onChangeSource,
            onClose: _exit,
          ),
        if (mode == ChromeMode.postVideo && widget.onPlayNext != null)
          PostVideoOverlay(
            key: _postVideoKey,
            nextTitle:
                widget.nextTitle ?? AppStrings.of(context).player_nextEpisode,
            nextArtwork: widget.nextArtwork,
            onPlayNext: widget.onPlayNext!,
            onDismiss: _dismissPostVideo,
            onOpenShow: widget.onOpenShow,
            onOpenSeason: widget.onOpenSeason,
          ),
        IgnorePointer(
          child: AnimatedOpacity(
            key: const ValueKey<String>('player-exit-fade'),
            opacity: mode == ChromeMode.exiting ? 1 : 0,
            duration: reduceMotion
                ? Duration.zero
                : PlayerChromeController.exitFadeDuration,
            child: const ColoredBox(color: Color(0xFF000000)),
          ),
        ),
      ],
    );
  }

  bool _isLoading(PlaybackState state) =>
      state.failure == null &&
      !state.isPlaying &&
      !state.isBuffering &&
      state.position == Duration.zero &&
      state.duration == Duration.zero;

  DateTime? _tvControlsHiddenByBack;

  /// TV: every press, whichever control handles it, restarts the auto-hide.
  bool _keepControlsOnKey(KeyEvent event) {
    if (event is KeyDownEvent && _isTv && _chrome.mode == ChromeMode.rail) {
      _chrome.reveal();
    }
    return false;
  }

  Timer? _mediaKeyGuard;

  bool get _isTv =>
      (widget.formFactor ?? AdaptiveBehavior.formFactorOf(context)) ==
      FormFactor.tv;

  /// TV remote keys. Media keys work from anywhere; D-pad Left/Right seek
  /// -10 s / +10 s, Up/Down reveal the controls
  /// and then move focus into them, Select toggles the controls — only while
  /// no control holds focus (a focused control handles its own keys).
  KeyEventResult _handleTvKey(LogicalKeyboardKey key, bool surfaceFocused) {
    final controller = widget.controller;
    final isMedia =
        key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause;
    if (isMedia) {
      // One Siri Remote press can arrive as the key and again as a system
      // media command; the second must not undo the first.
      if (_mediaKeyGuard?.isActive ?? false) return KeyEventResult.handled;
      _mediaKeyGuard = Timer(const Duration(milliseconds: 300), () {});
      unawaited(switch (key) {
        LogicalKeyboardKey.mediaPlay => controller.play(),
        // The Siri Remote's one button arrives as Media Pause on every press
        // (log 2026-10-30), so Media Pause while paused must resume.
        LogicalKeyboardKey.mediaPause when _viewModel.isPlaying =>
          controller.pause(),
        LogicalKeyboardKey.mediaPause => controller.play(),
        _ => _viewModel.isPlaying ? controller.pause() : controller.play(),
      });
      if (key != LogicalKeyboardKey.mediaPlay) _chrome.reveal();
      return KeyEventResult.handled;
    }
    final isArrow =
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown;
    final isSelect =
        key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter;
    final hiddenTouch = _touchBeganHiddenAt;
    final controlsWereShown =
        _chrome.visible &&
        (hiddenTouch == null ||
            DateTime.now().difference(hiddenTouch) >
                const Duration(seconds: 2));
    // Any D-pad use keeps the controls on screen.
    if ((isArrow || isSelect) && _chrome.mode == ChromeMode.rail) {
      _chrome.reveal();
    }
    final seekBarFocused =
        FocusManager.instance.primaryFocus?.debugLabel == 'tv-seek-bar';
    final horizontal =
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
    if ((!surfaceFocused && !(seekBarFocused && horizontal)) ||
        _chrome.mode == ChromeMode.panel) {
      return KeyEventResult.ignored;
    }
    if (horizontal &&
        surfaceFocused &&
        controlsWereShown &&
        _focusFirstControl()) {
      // Controls on screen: Left/Right belong to them, never to the skip.
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      _seekKey(key == LogicalKeyboardKey.arrowRight);
      _chrome.reveal();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      if (!_chrome.visible) {
        _chrome.reveal();
        return KeyEventResult.handled;
      }
      return _focusFirstControl()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (isSelect) {
      // Apple TV (Infuse style): click centre plays/pauses and shows the controls.
      if (_touchStream != null) {
        unawaited(
          _viewModel.isPlaying ? controller.pause() : controller.play(),
        );
        _chrome.reveal();
        return KeyEventResult.handled;
      }
      _chrome.toggle();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Moves focus to the top-left control in the lower half (the Pause button).
  bool _focusFirstControl() {
    final height = MediaQuery.sizeOf(context).height;
    final controls =
        FocusScope.of(context).traversalDescendants
            .where(
              (n) =>
                  n.canRequestFocus &&
                  !n.skipTraversal &&
                  n is! FocusScopeNode &&
                  n.rect.center.dy > height / 2,
            )
            .toList()
          ..sort((first, second) {
            final vertical = first.rect.top.compareTo(second.rect.top);
            return vertical != 0
                ? vertical
                : first.rect.left.compareTo(second.rect.left);
          });
    if (controls.isEmpty) return false;
    controls.first.requestFocus();
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_brightnessTouched) return;
    if (state == AppLifecycleState.resumed) {
      final level = _brightness;
      if (level != null) _brightnessScope?.set(level);
    } else if (state == AppLifecycleState.paused) {
      _brightnessScope?.restore();
    }
  }

  /// Phone swipe on the left half: window brightness, remembered until close.
  Future<void> _swipeBrightness(double delta) async {
    final scope = _brightnessScope;
    if (scope == null) return;
    _brightness ??= await scope.current() ?? 0.5;
    final level = (_brightness! + delta).clamp(0.01, 1.0).toDouble();
    _brightness = level;
    _brightnessTouched = true;
    scope.set(level);
    _levelHud.show(LevelKind.brightness, level);
  }

  void _swipeVolume(double delta) {
    final value = (_volume.value + delta).clamp(0.0, 1.0).toDouble();
    _volume.value = value;
    if (value > 0) _premute = value;
    _applyVolume(value);
    _levelHud.show(LevelKind.volume, value);
  }

  void _setFill(bool on) {
    _fill.value = on;
    unawaited(
      widget.controller.setFillScreen(on).catchError((Object _, StackTrace _) {}),
    );
  }

  void _applyVolume(double volume) {
    // An engine failure is already reported through the controller's events.
    unawaited(
      widget.controller
          .setVolume(volume)
          .catchError((Object _, StackTrace _) {}),
    );
  }

  /// Sets the level, shows it, and (unless muting) remembers it.
  void _setVolume(double volume, {bool save = true}) {
    final value = volume.clamp(0.0, 1.0).toDouble();
    _volume.value = value;
    if (value > 0) _premute = value;
    _applyVolume(value);
    _badge.showVolume(AppStrings.of(context), value);
    if (save) _prefs?.saveVolume(value);
  }

  void _stepVolume(int direction) =>
      _setVolume(((_volume.value * 100).round() + direction * 5) / 100);

  void _toggleMute() {
    if (_volume.value > 0) {
      _premute = _volume.value;
      _setVolume(0, save: false);
    } else {
      _setVolume(_premute > 0 ? _premute : 1);
    }
  }

  Duration? _keySeekTarget;
  DateTime? _keySeekAt;

  /// +/-10 s from the keyboard or D-pad, with the badge. Presses in quick
  /// succession add up from the last target (the engine's position lags).
  void _seekKey(bool forward) {
    final seconds = forward ? 10 : -10;
    final state = widget.controller.currentState;
    final now = DateTime.now();
    final recent =
        _keySeekAt != null &&
        now.difference(_keySeekAt!) < RivuletMotion.keySeekStack;
    final base = recent ? _keySeekTarget! : state.position;
    var target = base + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (state.duration > Duration.zero && target > state.duration) {
      target = state.duration;
    }
    _keySeekTarget = target;
    _keySeekAt = now;
    unawaited(widget.controller.seek(target));
    _badge.showSeek(AppStrings.of(context), seconds);
  }

  void _toggleFullscreen() {
    final prefs = _prefs;
    if (prefs != null) prefs.setFullscreen(!prefs.fullscreen.value);
  }

  /// C: subtitles off, or back to the last one used.
  void _toggleSubtitles() {
    final state = widget.controller.currentState;
    final current = state.selected.subtitle;
    final TrackChoice next;
    if (current.mode == TrackSelectionMode.off) {
      final tracks = state.tracks.subtitle;
      next =
          _lastSubtitle ??
          (tracks.isEmpty
              ? const TrackChoice.off()
              : TrackChoice.specific(tracks.first.id));
    } else {
      _lastSubtitle = current;
      next = const TrackChoice.off();
    }
    if (next == current) return;
    unawaited(
      widget.controller.selectTrack(
        TrackSelection(
          video: state.selected.video,
          audio: state.selected.audio,
          subtitle: next,
        ),
      ),
    );
  }

  bool _handleBack() {
    if (_chrome.mode == ChromeMode.panel) {
      _boxPanelKey.currentState?.dismiss();
      return true;
    }
    if (_shuttle.isActive) {
      unawaited(_shuttle.cancel());
      _chrome.exitShuttle();
      return true;
    }
    if (_chrome.mode == ChromeMode.postVideo) {
      _postVideoKey.currentState?.handleBack();
      return true;
    }
    // TV: Back closes the controls first, then the player. The remote's Back
    // can reach this twice for one press (key event and system back); the
    // repeat must not also close the player.
    if (_isTv) {
      final now = DateTime.now();
      final last = _tvControlsHiddenByBack;
      if (last != null &&
          now.difference(last) < const Duration(milliseconds: 300)) {
        return true;
      }
      if (_chrome.mode == ChromeMode.rail) {
        _tvControlsHiddenByBack = now;
        _chrome.toggle();
        return true;
      }
    }
    // Desktop: Esc leaves fullscreen first, a second one leaves the player.
    final fullscreen = _prefs?.fullscreen;
    if (!_isTv && fullscreen != null && fullscreen.value) {
      _prefs!.setFullscreen(false);
      return true;
    }
    return _chrome.handleBack();
  }

  void _dismissPostVideo() => _chrome.exitPostVideo();

  void _emitCommand(UiCommandType type, CommandSource source) =>
      _input.emit(type, source: source, timestamp: _inputClock.elapsed);

  void _handleCommand(UiCommand command) {
    switch (command.type) {
      case UiCommandType.playPause:
        unawaited(
          _viewModel.isPlaying
              ? widget.controller.pause()
              : widget.controller.play(),
        );
      case UiCommandType.stepSeekForward ||
          UiCommandType.stepSeekBackward ||
          UiCommandType.jumpSeekForward ||
          UiCommandType.jumpSeekBackward:
        _seek.handleCommand(command);
      case UiCommandType.scrubNudgeForward || UiCommandType.scrubNudgeBackward:
        _shuttle.handleCommand(command);
        _chrome.enterShuttle();
      case UiCommandType.selectDown:
        if (_shuttle.isActive) {
          unawaited(_shuttle.commit());
          _chrome.exitShuttle();
        }
      case UiCommandType.menuBack || UiCommandType.directionDown:
        if (_shuttle.isActive) {
          unawaited(_shuttle.cancel());
          _chrome.exitShuttle();
        } else if (command.type == UiCommandType.menuBack) {
          _handleBack();
        }
      default:
        break;
    }
  }

  void _onChromeChanged() {
    _viewModel.chromeVisible = _chrome.visible;
    if (mounted) setState(() {});
  }

  void _onPlaybackStateChanged() {
    _chrome.setPlaying(_viewModel.isPlaying);
    final state = _viewModel.state;
    // The position and buffered bar are drawn by the progress row alone
    // (LivePlaybackState); only a skip marker's countdown needs the chrome.
    final signature = (
      state.duration,
      state.isPlaying,
      state.isBuffering,
      state.isCompleted,
      state.rate,
      state.tracks,
      state.selected,
      state.chapters,
      state.failure,
      state.bufferingProgress,
      _isLoading(state),
      activeMarkerAt(widget.markers, state.position) == null
          ? null
          : state.position,
    );
    if (signature != _chromeSignature) {
      _chromeSignature = signature;
      _chromeTick.value++;
    }
    if (!_postVideoSeen &&
        widget.onPlayNext != null &&
        (state.isCompleted ||
            (state.duration > Duration.zero &&
                state.position >= state.duration))) {
      _postVideoSeen = true;
      _chrome.enterPostVideo();
    }
    final failure = _viewModel.failure;
    if (failure != null && !identical(failure, _lastFailure)) {
      _chrome.showError();
      _restoreSystemUi();
    }
    _lastFailure = failure;
  }

  void _restoreSystemUi() {
    if (_restoredSystemUi) return;
    _restoredSystemUi = true;
    widget.setSystemUiMode(SystemUiMode.edgeToEdge);
  }

  void _exit() {
    widget.onExit?.call();
    if (widget.onExit != null) return;
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }
}

/// The bottom transport chrome — geometry/metadata/secondary actions are
/// `phase-02-transport-controls.md`'s (`PlayerControlRail`, ported from
/// `PlayerRailView.swift`/`IOSPlayerChrome.swift`). Which widget renders here
/// depends on [formFactor] (owner rejection, ch03-p02):
///
/// - TV: `PlayerControlRail` alone, plate-less (`showPlate: false`, the
///   bottom gradient lives one layer up in `_buildChrome`), with a single
///   play-pause button as the rail's `leadingButton` — TV has no separate
///   primary-transport cluster (`tvos/IMG_8303.jpg`).
/// - Desktop: `PlayerDesktopPill` (the floating glass pill, which owns its
///   own primary transport + progress row) sits above the rail; the rail
///   still carries title/metadata only (no leading play button — the pill
///   already has one, and "exactly one play-pause control per form factor"
///   rules out a second).
/// - Phone: the rail (compact geometry), also plate-less (`showPlate:
///   false`, same bottom gradient scrim as TV, sized shorter — no opaque
///   slab behind the rail, matching `ios/IMG_8298.PNG`); phone's own primary
///   transport and volume readout render one layer up in `_buildChrome`,
///   centered/top-right respectively.
///
/// `Positioned` (see the call site in `_buildChrome`) pins this to the full,
/// bounded viewport width — `Align` hands an unconstrained width to its
/// child, which overflows the rail's progress track (unbounded-width).
class _OverlayPanel extends StatelessWidget {
  const _OverlayPanel({
    super.key,
    required this.controller,
    required this.state,
    required this.formFactor,
    required this.title,
    required this.actions,
    this.extraActions = 0,
    this.eyebrow,
    this.rating,
    this.runtimeLabel,
    this.audioLabel,
    this.onSubtitles,
    this.onAudioTrack,
    this.onInfo,
    this.onInsights,
    this.onUpNext,
    this.onNextEpisode,
    this.onFilter,
    this.onReplayLongPress,
    this.markers = const <ProgressMarker>[],
    this.thumbnail,
    this.onScrubStart,
    this.onScrubUpdate,
    this.onScrubEnd,
    this.previewPosition,
    this.volume,
    this.onVolumeChanged,
    this.onVolumeChangeEnd,
  });

  final ValueListenable<double>? volume;
  final ValueChanged<double>? onVolumeChanged;
  final ValueChanged<double>? onVolumeChangeEnd;
  final PlaybackController controller;
  final PlaybackState state;
  final FormFactor formFactor;
  final String title;
  final Widget actions;

  /// Action buttons inside [actions] beyond the pill's own (e.g. cast).
  final int extraActions;
  final String? eyebrow;
  final String? rating;
  final String? runtimeLabel;
  final String? audioLabel;
  final VoidCallback? onSubtitles;
  final VoidCallback? onAudioTrack;
  final VoidCallback? onInfo;
  final VoidCallback? onInsights;
  final VoidCallback? onUpNext;

  /// Desktop pill's "Next episode" button (series with a next episode only).
  final VoidCallback? onNextEpisode;
  final VoidCallback? onFilter;
  final VoidCallback? onReplayLongPress;
  final List<ProgressMarker> markers;
  final ImageProvider? thumbnail;
  final VoidCallback? onScrubStart;
  final ValueChanged<Duration>? onScrubUpdate;
  final ValueChanged<Duration>? onScrubEnd;
  final Duration? previewPosition;

  @override
  Widget build(BuildContext context) {
    final compact = formFactor == FormFactor.phone;
    // Desktop's action buttons (subtitles/audio/info/up next) already live
    // in `PlayerDesktopPill`'s row 1 — the rail below it carries title/
    // metadata/progress only, so the same four actions never render twice
    // ("only one control set may render", the owner's ch03-p02 rejection).

    final rail = PlayerControlRail(
      title: title,
      actions: actions,
      eyebrow: eyebrow,
      rating: rating,
      runtime: runtimeLabel,
      audio: audioLabel,
      compact: compact,
      controller: controller,
      state: state,
      onSubtitles: null,
      onAudio: null,
      onInfo: null,
      onInsights: null,
      onUpNext: null,
      onFilter: null,
      onReplayLongPress: null,
      markers: markers,
      thumbnail: thumbnail,
      onScrubStart: onScrubStart,
      onScrubUpdate: onScrubUpdate,
      onScrubEnd: onScrubEnd,
      previewPosition: previewPosition,
      showPlate: formFactor == FormFactor.desktop,
      elapsedUnderPlayhead: formFactor == FormFactor.tv,
      leadingButton: formFactor == FormFactor.tv
          ? TransportControlButton(
              key: const ValueKey<String>('play-pause'),
              autofocus: true,
              icon: state.isPlaying
                  ? PhosphorIconsRegular.pause
                  : PhosphorIconsRegular.play,
              semanticLabel: state.isPlaying
                  ? AppStrings.of(context).common_pause
                  : AppStrings.of(context).common_play,
              diameter: 74,
              iconSize: 32,
              onPress: state.isPlaying ? controller.pause : controller.play,
            )
          : null,
    );

    // Desktop renders the pill only — the pill already owns primary
    // transport, the four contract-backed secondary actions, and its own
    // elapsed/rail/remaining row 2, so stacking the full rail underneath it
    // would double every one of those (the exact "duplicate controls" shape
    // the owner rejected, just with the pill instead of the old
    // `TransportBar` as the second copy). No title renders on desktop,
    // matching `macos/macos_1.png`'s resting chrome, which shows none.
    if (formFactor == FormFactor.desktop) {
      return SafeArea(
        top: false,
        child: Padding(
          // measured from infuse-ref/macos/macos_1.png: the pill floats
          // clear of the bottom edge, not flush against it — 16 read as
          // "hugging the edge" in the owner's rejection.
          padding: const EdgeInsets.only(bottom: RivuletSpacing.s40),
          child: PlayerDesktopPill(
            controller: controller,
            state: state,
            actions: actions,
            onSubtitles: onSubtitles,
            onAudio: onAudioTrack,
            onInfo: onInfo,
            onUpNext: onUpNext,
            onNextEpisode: onNextEpisode,
            extraActions: extraActions,
            markers: markers,
            thumbnail: thumbnail,
            onScrubStart: onScrubStart,
            onScrubUpdate: onScrubUpdate,
            onScrubEnd: onScrubEnd,
            previewPosition: previewPosition,
            volume: volume,
            onVolumeChanged: onVolumeChanged,
            onVolumeChangeEnd: onVolumeChangeEnd,
          ),
        ),
      );
    }

    return SafeArea(top: false, child: rail);
  }
}
