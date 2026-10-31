import '../l10n_gen/app_strings.dart';
import '../l10n_gen/app_strings_en.dart';
import '../l10n/app_text.dart';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../accessibility/ui_accessibility.dart';
import '../components/app_button.dart';
import '../components/artwork.dart';
import '../components/orb_loader.dart';
import '../platform/adaptive_behavior.dart';
import '../navigation/page_back_button.dart';
import '../platform/form_factor.dart';
import '../states/error_view.dart';
import '../theme/rivulet_tokens.dart';
import 'stats/stats_format.dart';

/// What the opening screen says and how far along it is. [progress] is null
/// for a stage that has no measurable total (never a made-up number).
class StreamOpeningStatus {
  const StreamOpeningStatus({required this.label, this.progress});

  /// Maps the app's real signals to a stage: [source] is the transport's
  /// status once the stream handle exists (null before), [playback] is the
  /// engine's state. Only mpv's cache-buffering percentage is a total; the
  /// connecting, metadata and engine-start stages have none.
  factory StreamOpeningStatus.from({
    required SourceKind kind,
    AppStrings? strings,
    SourceStatus? source,
    PlaybackState? playback,
  }) {
    final s = strings ?? AppStringsEn();
    final torrent =
        kind == SourceKind.torrentMagnet || kind == SourceKind.torrentFile;
    final buffering = playback?.bufferingProgress;
    final speed = (source?.bytesPerSecond ?? 0) > 0
        ? ' · ${formatSpeed(source!.bytesPerSecond)}'
        : '';
    if (buffering != null) {
      final percent = (buffering * 100).floor();
      return StreamOpeningStatus(
        label: s.player_bufferingProgress(percent, speed),
        progress: buffering,
      );
    }
    if (source == null) {
      return StreamOpeningStatus(
        label: torrent ? s.player_fetchingMetadata : s.player_connecting,
      );
    }
    if (source.state == SourceState.stalled) {
      return StreamOpeningStatus(label: s.player_sourceStalled);
    }
    if (source.state == SourceState.resolving) {
      return StreamOpeningStatus(label: s.player_connecting);
    }
    if (source.state == SourceState.metadata) {
      return StreamOpeningStatus(label: s.player_fetchingMetadata);
    }
    final downloaded = source.available.ranges.fold<int>(
      0,
      (sum, range) => sum + range.length,
    );
    if (downloaded > 0) {
      return StreamOpeningStatus(
        label: s.player_preparingProgress('${formatBytes(downloaded)}$speed'),
      );
    }
    return StreamOpeningStatus(label: s.player_preparing);
  }

  /// True once the engine knows the length, is playing and its cache is full:
  /// the video is on screen and the opening screen can leave.
  static bool isReady(PlaybackState state) =>
      state.duration > Duration.zero &&
      state.isPlaying &&
      !state.isBuffering &&
      (state.bufferingProgress ?? 1) >= 1;

  final String label;
  final double? progress;
}

/// The page shown from the moment a stream is picked until its first frame:
/// the title's artwork darkened by the scrim, the title, the orb, a progress
/// bar and a status line. With a [failure] it offers Retry and Back instead.
class StreamOpeningScreen extends StatelessWidget {
  const StreamOpeningScreen({
    required this.title,
    required this.artwork,
    required this.kind,
    required this.status,
    required this.onBack,
    this.failure,
    this.onRetry,
    super.key,
  });

  final String title;
  final Uri? artwork;
  final MediaKind kind;
  final StreamOpeningStatus status;
  final AppFailure? failure;
  final VoidCallback? onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final colors = tokens.colors;
    final labels = UiAccessibility.labelsOf(context);
    final formFactor = AdaptiveBehavior.formFactorOf(context);
    final failure = this.failure;
    return PopOnEscape(
      onPop: onBack,
      child: Material(
        type: MaterialType.transparency,
        child: Focus(
          canRequestFocus: false,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ColoredBox(color: colors.bgBase),
              if (artwork case final url?)
                LayoutBuilder(
                  builder: (context, box) => ArtworkView(
                    requestId: url.toString(),
                    provider: ArtworkResolverScope.of(context)(url.toString()),
                    aspect: box.maxWidth / box.maxHeight,
                    fallbackKind: kind,
                    alignment: Alignment.topCenter,
                  ),
                ),
              // Two spec scrims stacked (60 % + 50 % black = 80 %) so the text
              // reads over any artwork.
              ColoredBox(color: colors.scrim),
              ColoredBox(color: colors.scrimMenu),
              Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: 0.45,
                  widthFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: colors.scrimBottom),
                  ),
                ),
              ),
              SafeArea(
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.all(RivuletSpacing.s16),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: AppButton.secondary(
                          key: const ValueKey<String>('stream-opening-back'),
                          autofocus: true,
                          label: labels.back,
                          icon: PhosphorIconsRegular.arrowLeft,
                          overMedia: true,
                          onActivate: onBack,
                        ),
                      ),
                    ),
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: formFactor == FormFactor.phone ? 320 : 420,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: RivuletSpacing.s16,
                          ),
                          child: failure == null
                              ? _Progress(title: title, status: status)
                              : ErrorView(
                                  failure: failure,
                                  onRetry: onRetry,
                                  onBack: onBack,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.title, required this.status});

  final String title;
  final StreamOpeningStatus status;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final colors = tokens.colors;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AppText(
          title,
          key: const ValueKey<String>('stream-opening-title'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: tokens.typeStyles.title,
        ),
        // The orb paints a halo beyond its 72 px box: give it room so the
        // halo never touches the title or the bar.
        const SizedBox(height: 128, child: Center(child: OrbLoader.large())),
        ClipRRect(
          borderRadius: BorderRadius.circular(RivuletRadius.full),
          child: LinearProgressIndicator(
            key: const ValueKey<String>('stream-opening-bar'),
            // Null animates (a stage with no total); under reduced motion an
            // empty track is shown instead of a moving bar.
            value: status.progress ?? (reduceMotion ? 0 : null),
            minHeight: 4,
            color: colors.accent,
            backgroundColor: colors.textSecondary.withValues(alpha: 0.2),
          ),
        ),
        const SizedBox(height: RivuletSpacing.s12),
        AppText(
          status.label,
          key: const ValueKey<String>('stream-opening-status'),
          textAlign: TextAlign.center,
          style: tokens.typeStyles.body.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

/// Stacks the [screen] over the [player] and cross-fades it away once the
/// first frame is [ready]. A [screen] showing a failure never leaves.
class StreamOpeningHost extends StatefulWidget {
  const StreamOpeningHost({
    required this.ready,
    required this.screen,
    this.player,
    super.key,
  });

  final bool ready;
  final StreamOpeningScreen screen;

  /// Null until the player exists.
  final Widget? player;

  @override
  State<StreamOpeningHost> createState() => _StreamOpeningHostState();
}

class _StreamOpeningHostState extends State<StreamOpeningHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    value: 1,
  );
  final FocusScopeNode _playerScope = FocusScopeNode(
    debugLabel: 'stream-opening-player',
  );
  bool _revealing = false;
  bool _gone = false;

  @override
  void dispose() {
    _playerScope.dispose();
    _fade.dispose();
    super.dispose();
  }

  void _maybeReveal() {
    if (_revealing ||
        !widget.ready ||
        widget.player == null ||
        widget.screen.failure != null) {
      return;
    }
    _revealing = true;
    // The opening screen holds focus for Escape; hand it to the player.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _playerScope.requestFocus();
    });
    // Reduced motion: fades stay at or under 120 ms (DESIGN_SPEC §5.3).
    final duration = MediaQuery.disableAnimationsOf(context)
        ? RivuletMotion.press
        : RivuletMotion.base;
    _fade
        .animateTo(0, duration: duration, curve: RivuletMotion.easeOut)
        .whenComplete(() {
          if (mounted) setState(() => _gone = true);
        });
  }

  @override
  Widget build(BuildContext context) {
    _maybeReveal();
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (widget.player case final player?)
          FocusScope(node: _playerScope, child: player),
        if (!_gone)
          IgnorePointer(
            ignoring: _revealing,
            child: ExcludeFocus(
              excluding: _revealing,
              child: FadeTransition(
                key: const ValueKey<String>('stream-opening-fade'),
                opacity: _fade,
                child: widget.screen,
              ),
            ),
          ),
      ],
    );
  }
}
