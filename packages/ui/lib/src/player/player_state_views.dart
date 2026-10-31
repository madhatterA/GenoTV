import 'package:core/core.dart';

import '../states/failure_messages.dart';
import '../l10n_gen/app_strings.dart';
import '../l10n/app_text.dart';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import 'player_chrome_controller.dart';

import '../components/app_button.dart';
import '../components/orb_loader.dart';
import '../accessibility/ui_accessibility.dart';
import '../components/tinted_surface.dart';
import '../theme/rivulet_tokens.dart';
import '../states/error_view.dart' show errorIconFor;

String playerFailureMessage(AppFailure failure, AppStrings strings) =>
    switch (failure.code) {
      'playback.open.failed' => strings.player_failure_openFailed,
      'playback.decode.failed' => strings.player_failure_decodeFailed,
      'playback.engine.crashed' => strings.player_failure_engineCrashed,
      'playback.source.unreachable' => strings.player_failure_sourceUnreachable,
      'playback.unsupported.codec' => strings.player_failure_unsupportedCodec(
        failure.message.substring(failure.message.indexOf(': ') + 2),
      ),
      'playback.track.selection_failed' =>
        strings.player_failure_trackSelectionFailed(
          failure.message.substring(failure.message.indexOf(': ') + 2),
        ),
      'playback.subtitle.load_failed' =>
        strings.player_failure_subtitleLoadFailed(
          failure.message.substring(failure.message.indexOf(': ') + 2),
        ),
      _ => messageForFailure(failure, strings: strings),
    };

class PlayerLoadingLabel extends StatelessWidget {
  const PlayerLoadingLabel({super.key});

  /// Sits under the centred orb, inside the safe area (Part 07 p01).
  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: SafeArea(
      child: Align(
        alignment: const Alignment(0, 0.4),
        child: AppText(
          AppStrings.of(context).player_loading,
          key: const ValueKey<String>('player-loading-label'),
          textAlign: TextAlign.center,
          style: RivuletTokens.of(context).typeStyles.body
              .copyWith(color: RivuletTokens.of(context).colors.textSecondary),
        ),
      ),
    ),
  );
}

/// Renders buffering without ever removing the video surface (pitfall:
/// "Never replace surface with a spinner during buffering"). A small
/// indicator only; the surface underneath is untouched.
class PlayerBufferingIndicator extends StatelessWidget {
  const PlayerBufferingIndicator({required this.progress, super.key});

  /// Readiness to play, 0..1 (not file download progress).
  final double progress;

  @override
  Widget build(BuildContext context) {
    final percent = (progress.clamp(0.0, 1.0) * 100).floor();
    final tokens = RivuletTokens.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const OrbLoader.medium(
            key: ValueKey<String>('player-buffering-indicator'),
          ),
          AppText(
            '$percent%',
            key: const ValueKey<String>('player-buffering-percent'),
            style: tokens.typeStyles.title,
          ),
        ],
      ),
    );
  }
}

/// Full-frame paused-ambient dim. `PlayerContainerViewController.swift:171-173`
/// gives the ambient-pause dim's opacity: `UIColor.black.withAlphaComponent(0.28)`.
/// No distinct constant for the deeper "dimmed" (120 s) tier was found within
/// this phase's research budget; it is deepened to 0.6 as a Part 04 default,
/// not a Rivulet-sourced value.
class PlayerPauseScrim extends StatelessWidget {
  const PlayerPauseScrim({required this.presentation, super.key});

  final PausePresentation presentation;

  @override
  Widget build(BuildContext context) {
    // Opaque mode (colour-keyed native video): a dimming scrim would hide the video.
    final opacity = switch (UiAccessibility.opaqueOf(context)
        ? PausePresentation.frame
        : presentation) {
      PausePresentation.frame => 0.0,
      PausePresentation.ambient => 0.28,
      PausePresentation.dimmed => 0.6,
    };
    return IgnorePointer(
      child: AnimatedOpacity(
        key: const ValueKey<String>('player-pause-scrim'),
        opacity: opacity,
        duration: const Duration(milliseconds: 250),
        child: ColoredBox(color: RivuletTokens.of(context).colors.playerScrim),
      ),
    );
  }
}

/// A device/route compatibility notice. Source: `UniversalPlayerViewModel.swift:153`,
/// `@Published var compatibilityNotice: String?` — capability probing itself is
/// Part 05's; this only renders the string the composition root supplies.
class PlayerCompatibilityNotice extends StatelessWidget {
  const PlayerCompatibilityNotice({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Positioned(
    top: RivuletSpacing.s40,
    left: RivuletSpacing.s64,
    right: RivuletSpacing.s64,
    child: TintedSurface.overMedia(
      key: const ValueKey<String>('player-compatibility-notice'),
      radius: RivuletRadius.large,
      padding: const EdgeInsets.symmetric(
        horizontal: RivuletSpacing.s16,
        vertical: RivuletSpacing.s8,
      ),
      child: AppText(message, style: RivuletTokens.of(context).typeStyles.body),
    ),
  );
}

/// Focused error overlay with retry/dismiss, gated by
/// [PlayerChromeController.canDismissError] (pitfall: "Block re-dismiss for
/// 300 ms after mode change").
class PlayerErrorOverlay extends StatefulWidget {
  const PlayerErrorOverlay({
    required this.failure,
    required this.chrome,
    required this.onRetry,
    this.onTryAnotherSource,
    this.onClose,
    super.key,
  });

  final PlaybackFailure failure;
  final PlayerChromeController chrome;
  final VoidCallback? onRetry;

  /// Opens the source list for the same title; the button is hidden without it.
  final VoidCallback? onTryAnotherSource;

  /// Leaves the player (back to the title page).
  final VoidCallback? onClose;

  @override
  State<PlayerErrorOverlay> createState() => _PlayerErrorOverlayState();
}

class _PlayerErrorOverlayState extends State<PlayerErrorOverlay> {
  final FocusNode _retryNode = FocusNode(debugLabel: 'player-error-retry');

  @override
  void initState() {
    super.initState();
    // The player surface holds focus, so autofocus alone would not move it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _retryNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _retryNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chrome = widget.chrome;
    final failure = widget.failure;
    final onRetry = widget.onRetry;
    final onTryAnotherSource = widget.onTryAnotherSource;
    final onClose = widget.onClose;
    return AnimatedBuilder(
      animation: chrome,
      builder: (context, _) => Center(
        child: TintedSurface.overMedia(
          key: const ValueKey<String>('player-error-overlay'),
          radius: RivuletRadius.large,
          child: Padding(
            padding: const EdgeInsets.all(RivuletSpacing.s24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  errorIconFor(failure.code),
                  color: RivuletTokens.of(context).colors.decorative,
                  size: 40,
                ),
                const SizedBox(height: RivuletSpacing.s12),
                AppText(
                  AppStrings.of(context).player_errorTitle,
                  style: RivuletTokens.of(context).typeStyles.title,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: RivuletSpacing.s8),
                AppText(
                  playerFailureMessage(failure, AppStrings.of(context)),
                  key: const ValueKey<String>('player-error-message'),
                  style: RivuletTokens.of(context).typeStyles.body,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: RivuletSpacing.s20),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: RivuletSpacing.s12,
                  runSpacing: RivuletSpacing.s12,
                  children: <Widget>[
                    AppButton.primary(
                      key: const ValueKey<String>('player-error-retry'),
                      label: AppStrings.of(context).common_retry,
                      focusNode: _retryNode,
                      // Always enabled so it can take focus on arrival; the
                      // 300 ms guard is checked when it is pressed.
                      onActivate: () {
                        if (!chrome.canDismissError) return;
                        chrome.retryFromError();
                        onRetry?.call();
                      },
                    ),
                    if (onTryAnotherSource != null)
                      AppButton.secondary(
                        key: const ValueKey<String>('player-error-another'),
                        label: AppStrings.of(context).player_tryAnotherSource,
                        overMedia: true,
                        onActivate: chrome.canDismissError
                            ? onTryAnotherSource
                            : null,
                      ),
                    AppButton.secondary(
                      key: const ValueKey<String>('player-error-dismiss'),
                      label: AppStrings.of(context).common_close,
                      overMedia: true,
                      onActivate: chrome.canDismissError
                          ? (onClose ?? chrome.dismissError)
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
