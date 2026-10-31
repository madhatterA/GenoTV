import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_text.dart';
import '../l10n_gen/app_strings.dart';
import '../theme/rivulet_tokens.dart';
import '../components/tinted_surface.dart';

/// What the player last did by key, shown as a short-lived pill: "-10 s" /
/// "+10 s" (stacking, "+20 s", while presses keep coming within
/// [RivuletMotion.seekBadgeStack]) or the volume level.
class PlayerBadgeController extends ChangeNotifier {
  String? text;
  Alignment alignment = Alignment.center;
  int _seconds = 0;
  DateTime? _lastSeek;
  Timer? _hold;
  Timer? _clear;

  /// False while the badge fades out.
  bool shown = false;

  /// A seek of [delta] seconds (negative = back).
  void showSeek(AppStrings strings, int delta) {
    final now = DateTime.now();
    final last = _lastSeek;
    final stacking =
        last != null &&
        now.difference(last) < RivuletMotion.seekBadgeStack &&
        _seconds.sign == delta.sign;
    _seconds = stacking ? _seconds + delta : delta;
    _lastSeek = now;
    text =
        '${_seconds < 0 ? '−' : '+'}${strings.player_badge_seconds(_seconds.abs())}';
    alignment = delta < 0 ? Alignment.centerLeft : Alignment.centerRight;
    _show();
  }

  void showVolume(AppStrings strings, double volume) {
    final percent = (volume * 100).round();
    text = percent == 0
        ? strings.player_badge_muted
        : strings.player_badge_volume(percent);
    alignment = Alignment.topCenter;
    _show();
  }

  void _show() {
    _hold?.cancel();
    _clear?.cancel();
    shown = true;
    _hold = Timer(RivuletMotion.seekBadge, () {
      shown = false;
      notifyListeners();
    });
    _clear = Timer(RivuletMotion.seekBadge * 2, () {
      text = null;
      _seconds = 0;
      notifyListeners();
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _hold?.cancel();
    _clear?.cancel();
    super.dispose();
  }
}

/// Draws [controller]'s badge over the video; never takes input.
class PlayerBadgeOverlay extends StatelessWidget {
  const PlayerBadgeOverlay({required this.controller, super.key});

  final PlayerBadgeController controller;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final text = controller.text;
        if (text == null) return const SizedBox.shrink();
        return Align(
          alignment: controller.alignment,
          child: Padding(
            padding: const EdgeInsets.all(RivuletSpacing.s48),
            child: AnimatedOpacity(
              opacity: controller.shown ? 1 : 0,
              duration: effectiveDuration(context, RivuletMotion.seekBadge),
              child: TintedSurface.overMedia(
              key: const ValueKey<String>('player-badge'),
              radius: RivuletRadius.large,
              padding: const EdgeInsets.symmetric(
                horizontal: RivuletSpacing.s24,
                vertical: RivuletSpacing.s12,
              ),
              child: AppText(
                text,
                style: RivuletTokens.of(context).typeStyles.headline,
              ),
            ),
            ),
          ),
        );
      },
    ),
  );
}
