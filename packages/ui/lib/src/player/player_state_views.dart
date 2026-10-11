import 'package:core/core.dart';

import '../states/failure_messages.dart';
import '../l10n_gen/app_strings.dart';
import '../l10n/app_text.dart';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import 'player_chrome_controller.dart';

/// Top-left status label — occupies the same spot the paused indicator
/// uses in Rivulet and shares its typography, styled "quiet text-only cue,
/// no spinner" (`PlayerContainerViewController.swift:224-232`: font 22
/// medium, `UIColor.white.withAlphaComponent(0.6)`, positioned
/// `top: 44, leading: 64`, lines 306-313).
import '../components/app_button.dart';
import '../components/orb_loader.dart';
import '../components/tinted_surface.dart';
import '../theme/rivulet_tokens.dart';

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

  @override
  Widget build(BuildContext context) => Positioned(
    top: 44,
    left: 64,
    child: AppText(
      AppStrings.of(context).player_loading,
      key: const ValueKey<String>('player-loading-label'),
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w500,
        color: RivuletTokens.of(context).colors.textSecondary,
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
    final opacity = switch (presentation) {
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
    top: 44,
    left: 64,
    right: 64,
    child: TintedSurface.overMedia(
      key: const ValueKey<String>('player-compatibility-notice'),
      radius: RivuletRadius.small,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: AppText(message, style: RivuletTokens.of(context).typeStyles.body),
    ),
  );
}

/// Focused error overlay with retry/dismiss, gated by
/// [PlayerChromeController.canDismissError] (pitfall: "Block re-dismiss for
/// 300 ms after mode change").
class PlayerErrorOverlay extends StatelessWidget {
  const PlayerErrorOverlay({
    required this.failure,
    required this.chrome,
    required this.onRetry,
    super.key,
  });

  final PlaybackFailure failure;
  final PlayerChromeController chrome;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: chrome,
    builder: (context, _) => Center(
      child: TintedSurface.overMedia(
        key: const ValueKey<String>('player-error-overlay'),
        radius: RivuletRadius.large,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.error_outline,
                color: RivuletTokens.of(context).colors.textTertiary,
                size: 40,
              ),
              const SizedBox(height: 12),
              AppText(
                playerFailureMessage(failure, AppStrings.of(context)),
                key: const ValueKey<String>('player-error-message'),
                style: RivuletTokens.of(context).typeStyles.title,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                runSpacing: 12,
                children: <Widget>[
                  AppButton.secondary(
                    key: const ValueKey<String>('player-error-dismiss'),
                    label: AppStrings.of(context).common_dismiss,
                    overMedia: true,
                    onActivate: chrome.canDismissError
                        ? chrome.dismissError
                        : null,
                  ),
                  const SizedBox(width: 12),
                  AppButton.primary(
                    key: const ValueKey<String>('player-error-retry'),
                    label: AppStrings.of(context).common_retry,
                    onActivate: chrome.canDismissError
                        ? () {
                            chrome.retryFromError();
                            onRetry?.call();
                          }
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
