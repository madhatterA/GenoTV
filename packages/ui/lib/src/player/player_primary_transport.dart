import '../l10n_gen/app_strings.dart';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'transport_control_button.dart';

/// The primary skip-back / play-pause / skip-forward cluster shown on
/// desktop (inside the floating glass pill) and phone (centered, large glyphs)
/// chrome — see `evidence/part-04-rivulet/infuse-ref/macos/macos_1.png` and
/// `ios/IMG_8298.PNG`. Built on the same glass [TransportControlButton] the
/// rail uses (not a plain `IconButton` row) so the primary transport reads as
/// one visual family with the rail's secondary actions.
///
/// Replaces the pre-rewrite `TransportBar` (deleted this phase — see
/// `bug_history.md`): that widget rendered as a second, plain-`IconButton`
/// floating strip stacked above the new `PlayerControlRail`, which the
/// owner rejected as duplicate controls. Its skip-amount/keyboard-shortcut
/// behavior is ported here verbatim; its `play-pause`/`skip-back`/
/// `skip-forward` keys are preserved so `app/test/ui_wiring_test.dart` keeps
/// working unchanged.
class PlayerPrimaryTransport extends StatelessWidget {
  const PlayerPrimaryTransport({
    required this.controller,
    required this.state,
    this.diameter = TransportControlButton.defaultDiameter,
    this.gap = 20,
    this.autofocus = true,
    super.key,
  });

  static const Duration skipBack = Duration(seconds: 10);
  static const Duration skipForward = Duration(seconds: 30);

  final PlaybackController controller;
  final PlaybackState state;

  /// Button diameter — desktop uses a smaller size than phone's "large
  /// glyphs" cluster (`ios/IMG_8298.PNG`); both are caller-supplied, not a
  /// Rivulet-sourced constant (no macOS/compact-phone primary-transport
  /// spec exists in Rivulet — see `player_control_rail.dart`'s own doc
  /// comment for the same gap on the rail itself).
  final double diameter;
  final double gap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Actions(
    actions: <Type, Action<Intent>>{
      _TogglePlayIntent: CallbackAction<_TogglePlayIntent>(
        onInvoke: (_) {
          if (state.isPlaying) {
            controller.pause();
          } else {
            controller.play();
          }
          return null;
        },
      ),
      _SkipIntent: CallbackAction<_SkipIntent>(
        onInvoke: (intent) {
          controller.seek(_clamp(state.position + intent.amount));
          return null;
        },
      ),
    },
    child: Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.space): const _TogglePlayIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowLeft): const _SkipIntent(
          Duration(seconds: -10),
        ),
        LogicalKeySet(LogicalKeyboardKey.arrowRight): const _SkipIntent(
          skipForward,
        ),
      },
      // `Focus(autofocus: true)` (matching the deleted `TransportBar`'s own
      // outer `Focus`): `Shortcuts` only intercepts a key event once some
      // descendant holds primary focus for it to bubble up from — with
      // nothing focused, space/arrow keys never reach the `Actions` above.
      child: Focus(
        autofocus: autofocus,
        onKeyEvent: (_, _) => KeyEventResult.ignored,
        child: Row(
          key: const ValueKey<String>('transport-bar'),
          textDirection: TextDirection.ltr,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TransportControlButton(
              key: const ValueKey<String>('skip-back'),
              icon: Icons.replay_10,
              semanticLabel: AppStrings.of(context).player_replayTen,
              diameter: diameter,
              iconSize: diameter * 0.4,
              onPress: () => controller.seek(_clamp(state.position - skipBack)),
            ),
            SizedBox(width: gap),
            TransportControlButton(
              key: const ValueKey<String>('play-pause'),
              icon: state.isPlaying ? Icons.pause : Icons.play_arrow,
              semanticLabel: state.isPlaying
                  ? AppStrings.of(context).common_pause
                  : AppStrings.of(context).common_play,
              diameter: diameter,
              iconSize: diameter * 0.5,
              onPress: state.isPlaying ? controller.pause : controller.play,
            ),
            SizedBox(width: gap),
            TransportControlButton(
              key: const ValueKey<String>('skip-forward'),
              icon: Icons.forward_30,
              semanticLabel: AppStrings.of(context).player_skipThirty,
              diameter: diameter,
              iconSize: diameter * 0.4,
              onPress: () =>
                  controller.seek(_clamp(state.position + skipForward)),
            ),
          ],
        ),
      ),
    ),
  );

  Duration _clamp(Duration value) => value < Duration.zero
      ? Duration.zero
      : state.duration > Duration.zero && value > state.duration
      ? state.duration
      : value;
}

class _TogglePlayIntent extends Intent {
  const _TogglePlayIntent();
}

class _SkipIntent extends Intent {
  const _SkipIntent(this.amount);

  final Duration amount;
}
