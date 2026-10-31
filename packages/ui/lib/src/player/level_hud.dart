import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../components/tinted_surface.dart';
import '../l10n/app_text.dart';
import '../theme/rivulet_tokens.dart';

enum LevelKind { volume, brightness }

/// The level shown while a vertical swipe changes volume or brightness.
class LevelHudController extends ChangeNotifier {
  LevelKind kind = LevelKind.volume;
  double level = 0;
  bool shown = false;
  Timer? _hide;

  void show(LevelKind kind, double level) {
    this.kind = kind;
    this.level = level.clamp(0.0, 1.0);
    shown = true;
    _hide?.cancel();
    _hide = Timer(RivuletMotion.seekBadge, () {
      shown = false;
      notifyListeners();
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }
}

/// Draws [controller]'s level at the edge of the swiped half; never takes input.
class LevelHud extends StatelessWidget {
  const LevelHud({required this.controller, super.key});

  final LevelHudController controller;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final volume = controller.kind == LevelKind.volume;
        final percent = (controller.level * 100).round();
        return Align(
          alignment: volume ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.all(RivuletSpacing.s24),
            child: AnimatedOpacity(
              opacity: controller.shown ? 1 : 0,
              duration: effectiveDuration(context, RivuletMotion.seekBadge),
              child: TintedSurface.overMedia(
                key: ValueKey<String>('level-hud-${controller.kind.name}'),
                radius: RivuletRadius.large,
                padding: const EdgeInsets.symmetric(
                  horizontal: RivuletSpacing.s16,
                  vertical: RivuletSpacing.s12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      volume
                          ? PhosphorIconsRegular.speakerHigh
                          : PhosphorIconsRegular.sun,
                      size: 24,
                    ),
                    const SizedBox(height: RivuletSpacing.s8),
                    AppText(
                      '$percent%',
                      key: const ValueKey<String>('level-hud-text'),
                      style: RivuletTokens.of(context).typeStyles.headline,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
