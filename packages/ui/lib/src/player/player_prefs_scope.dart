import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// What the player remembers between sessions: the last volume and the
/// window's fullscreen state. The app backs it with its settings store (the
/// volume is not listed in Settings; fullscreen is the existing
/// `display.fullscreenMode` setting). Without a scope the volume starts at
/// full and fullscreen is unavailable.
class PlayerPrefsScope extends InheritedWidget {
  const PlayerPrefsScope({
    required this.volume,
    required this.saveVolume,
    required this.fullscreen,
    required this.setFullscreen,
    required super.child,
    super.key,
  });

  /// Last saved volume, 0.0-1.0.
  final double Function() volume;
  final void Function(double volume) saveVolume;
  final ValueListenable<bool> fullscreen;
  final void Function(bool on) setFullscreen;

  static PlayerPrefsScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlayerPrefsScope>();

  @override
  bool updateShouldNotify(PlayerPrefsScope oldWidget) => false;
}

/// The phone's screen brightness, for the player's left-half swipe. Provided
/// by the app only where the platform can do it (phones); without a scope the
/// swipe is not attached.
class BrightnessScope extends InheritedWidget {
  const BrightnessScope({
    required this.current,
    required this.set,
    required this.restore,
    required super.child,
    super.key,
  });

  /// Current level 0.0-1.0.
  final Future<double?> Function() current;
  final void Function(double level) set;

  /// Back to the system brightness (player closed or app in background).
  final void Function() restore;

  static BrightnessScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BrightnessScope>();

  @override
  bool updateShouldNotify(BrightnessScope oldWidget) => false;
}
