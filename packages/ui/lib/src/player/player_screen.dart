import '../l10n_gen/app_strings.dart';
import '../l10n/app_text.dart';

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:contracts/fakes.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../focus/input_router.dart';
import '../focus/ui_command.dart';
import '../models/ui_media.dart';
import '../navigation/back_dispatcher.dart';
import '../theme/rivulet_tokens.dart';
import 'player_chrome_controller.dart';
import 'player_control_rail.dart';
import '../cast/cast_ui.dart';
import '../components/app_sheet.dart';
import 'player_desktop_pill.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import 'player_gesture_surface.dart';
import 'player_panel_host.dart';
import 'player_phone_chrome.dart';
import 'player_state_views.dart';
import 'player_view_model.dart';
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
    this.onAddSubtitleFiles,
    super.key,
  });

  /// "Add subtitle file…" in the Subtitles panel; null hides the row.
  final Future<List<({String name, Uri uri})>> Function()? onAddSubtitleFiles;

  /// What and how to show in the download popover and the stats overlay;
  /// null hides both (and the "i" key).
  final PlayerStatsSource? stats;

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
  /// resolves from `AdaptiveBehavior.of(context).formFactor`.
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

  /// Retry action for the focused error overlay. Re-opening the source is
  /// Part 02/07's concern (non-goal: "No decoder/source opening logic"); the
  /// scaffold only clears its own chrome mode and forwards the request.
  final VoidCallback? onRetry;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late PlayerChromeController _chrome;
  late PlayerViewModel _viewModel;
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
        widget.formFactor ?? AdaptiveBehavior.of(context).formFactor;
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
  void initState() {
    super.initState();
    _unregisterBack = widget.backDispatcher?.register(_handleBack);
    widget.setSystemUiMode(SystemUiMode.immersiveSticky);
    _bindSession(widget.controller);
    widget.thumbnailPreview?.addListener(_onChromeChanged);
    _stats = widget.stats == null ? null : PlayerStatsController(widget.stats!);
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
    _viewModel = PlayerViewModel(controller: controller);
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
  }

  @override
  void didUpdateWidget(covariant PlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stats != widget.stats) {
      _stats?.dispose();
      _stats = widget.stats == null
          ? null
          : PlayerStatsController(widget.stats!);
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
      _surface = null;
      _restoredSystemUi = false;
      _bindSession(widget.controller);
    }
  }

  @override
  void dispose() {
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
          onToggleChrome: _chrome.toggle,
          onRevealChrome: _chrome.reveal,
          onPlayPause: () =>
              _emitCommand(UiCommandType.playPause, CommandSource.keyboard),
          onSeekBackward: () =>
              _emitCommand(UiCommandType.stepSeekBackward, CommandSource.touch),
          onSeekForward: () =>
              _emitCommand(UiCommandType.stepSeekForward, CommandSource.touch),
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
          onTvKey: _isTv ? _handleTvKey : null,
          overlay: AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[
              _chrome,
              _viewModel,
              ?widget.cast?.state,
            ]),
            builder: (context, _) => _buildChrome(context, reduceMotion),
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
                      48,
                      96,
                      MediaQuery.sizeOf(context).width * 0.42,
                      170,
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
    final railVisible =
        !casting &&
        _chrome.visible &&
        mode != ChromeMode.error &&
        mode != ChromeMode.postVideo &&
        mode != ChromeMode.exiting;
    final formFactor =
        widget.formFactor ?? AdaptiveBehavior.of(context).formFactor;
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
          AnimatedOpacity(
            opacity: mode == ChromeMode.exiting ? 0 : 1,
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            child: Align(
              alignment: Alignment.topLeft,
              child: SafeArea(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      tooltip: AppStrings.of(context).player_close,
                      onPressed: _handleBack,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ],
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
                          padding: const EdgeInsets.only(left: 8),
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
                            iconSize: formFactor == FormFactor.tv ? 25 : 20,
                            icon: switch (panel) {
                              'subtitles' => Icons.subtitles_outlined,
                              'audio' => Icons.graphic_eq,
                              _ => Icons.settings_outlined,
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
                      if (widget.stats?.hasTransferStats ?? false)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: TransportControlButton(
                            key: const ValueKey('player-box-stats'),
                            focusNode: _statsOpenerNode,
                            touchTargetEnabled:
                                railVisible && mode != ChromeMode.panel,
                            diameter: formFactor == FormFactor.tv ? 74 : 44,
                            iconSize: formFactor == FormFactor.tv ? 25 : 20,
                            icon: Icons.info_outline,
                            semanticLabel: AppStrings.of(context)
                                .player_downloadInfo,
                            onPress: () => _openBoxPanel('stats'),
                          ),
                        ),
                      if (widget.cast != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: CastButton(
                            anchorLink: _castLink,
                            focusNode: _castOpenerNode,
                            onPress: () => _openBoxPanel('cast'),
                            touchTargetEnabled:
                                railVisible && mode != ChromeMode.panel,
                            diameter: formFactor == FormFactor.tv ? 74 : 44,
                            iconSize: formFactor == FormFactor.tv ? 25 : 20,
                          ),
                        ),
                      if (widget.onUpNext != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: TransportControlButton(
                            key: const ValueKey('rail-action-upNext'),
                            icon: Icons.video_collection_outlined,
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
                  extraActions:
                      (widget.cast == null ? 0 : 1) +
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
                      : null,
                ),
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
                          ? 14
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
            left: 16,
            top: 64,
            child: StatsOverlay(
              controller: _stats!,
              onClose: () => setState(() => _showStats = false),
            ),
          ),
        if (_shuttle.isActive && _shuttle.badge != null)
          Positioned(
            left: 40,
            bottom: _railHeight + 12,
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

  bool get _isTv =>
      (widget.formFactor ?? AdaptiveBehavior.of(context).formFactor) ==
      FormFactor.tv;

  /// TV remote keys. Media keys work from anywhere; D-pad Left/Right seek
  /// -10 s / +30 s (the rail's skip amounts), Up/Down reveal the controls
  /// and then move focus into them, Select toggles the controls — only while
  /// no control holds focus (a focused control handles its own keys).
  KeyEventResult _handleTvKey(LogicalKeyboardKey key, bool surfaceFocused) {
    final controller = widget.controller;
    if (key == LogicalKeyboardKey.mediaPlayPause) {
      unawaited(_viewModel.isPlaying ? controller.pause() : controller.play());
      _chrome.reveal();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPlay) {
      unawaited(controller.play());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPause) {
      unawaited(controller.pause());
      _chrome.reveal();
      return KeyEventResult.handled;
    }
    final isArrow =
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown;
    final isSelect =
        key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter;
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
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      final forward = key == LogicalKeyboardKey.arrowRight;
      final state = widget.controller.currentState;
      final target = state.position + Duration(seconds: forward ? 30 : -10);
      unawaited(
        controller.seek(
          target < Duration.zero
              ? Duration.zero
              : (target > state.duration ? state.duration : target),
        ),
      );
      _chrome.reveal();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      if (!_chrome.visible) {
        _chrome.reveal();
        return KeyEventResult.handled;
      }
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
      if (controls.isEmpty) return KeyEventResult.ignored;
      controls.first.requestFocus();
      return KeyEventResult.handled;
    }
    if (isSelect) {
      _chrome.toggle();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
    if (mounted) setState(() {});
  }

  void _onPlaybackStateChanged() {
    _chrome.setPlaying(_viewModel.isPlaying);
    final state = _viewModel.state;
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
    this.onFilter,
    this.onReplayLongPress,
    this.markers = const <ProgressMarker>[],
    this.thumbnail,
    this.onScrubStart,
    this.onScrubUpdate,
    this.onScrubEnd,
    this.previewPosition,
  });

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
              icon: state.isPlaying ? Icons.pause : Icons.play_arrow,
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
          padding: const EdgeInsets.only(bottom: 40),
          child: PlayerDesktopPill(
            controller: controller,
            state: state,
            actions: actions,
            onSubtitles: onSubtitles,
            onAudio: onAudioTrack,
            onInfo: onInfo,
            onUpNext: onUpNext,
            extraActions: extraActions,
            markers: markers,
            thumbnail: thumbnail,
            onScrubStart: onScrubStart,
            onScrubUpdate: onScrubUpdate,
            onScrubEnd: onScrubEnd,
            previewPosition: previewPosition,
          ),
        ),
      );
    }

    return SafeArea(top: false, child: rail);
  }
}
