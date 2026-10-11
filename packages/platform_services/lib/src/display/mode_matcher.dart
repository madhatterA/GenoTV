import 'package:contracts/contracts.dart';

final class ModeMatch {
  const ModeMatch(this.mode, {this.reason});

  final DisplayMode mode;
  final String? reason;
}

/// Pure refresh-rate selection. It never changes resolution unless requested.
abstract final class ModeMatcher {
  static ModeMatch? match({
    required double contentFps,
    required List<DisplayMode> modes,
    DisplayMode? current,
    int? width,
    int? height,
  }) {
    if (!contentFps.isFinite || contentFps <= 0) return null;
    final reference = current ?? modes.where((m) => m.isCurrent).firstOrNull;
    // Kodi ChooseBestResolution: never smaller than the desktop mode; prefer the
    // exact source size, else fall back to the desktop size.
    final valid = modes.where((mode) {
      if (!mode.refreshHz.isFinite || mode.refreshHz <= 0) return false;
      if (reference == null) return true;
      return mode.width >= reference.width && mode.height >= reference.height;
    }).toList();
    final exactSize = valid
        .where(
          (m) =>
              (width == null || m.width == width) &&
              (height == null || m.height == height),
        )
        .toList();
    final usable = (width != null || height != null) && exactSize.isNotEmpty
        ? exactSize
        : reference == null
        ? exactSize
        : valid
              .where(
                (m) =>
                    m.width == reference.width && m.height == reference.height,
              )
              .toList();
    if (usable.isEmpty) return null;
    final sourceCurrent =
        current ?? modes.where((m) => m.isCurrent).firstOrNull;
    final exact = usable
        .where((m) => (m.refreshHz - contentFps).abs() < 0.001)
        .toList();
    final multiple = usable.where((m) {
      final ratio = m.refreshHz / contentFps;
      // Kodi: 1x, 2x and 2.5x (pull-down) only.
      return [1.0, 2.0, 2.5].any((r) => (ratio - r).abs() < 0.001);
    }).toList();
    final near = usable
        .where((m) => _isNearPair(m.refreshHz, contentFps))
        .toList();
    final candidates = exact.isNotEmpty
        ? exact
        : multiple.isNotEmpty
        ? multiple
        : near;
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final aScore = _score(a, contentFps);
      final bScore = _score(b, contentFps);
      return aScore.compareTo(bScore);
    });
    final selected = candidates.first;
    if (sourceCurrent != null &&
        sourceCurrent.width == selected.width &&
        sourceCurrent.height == selected.height &&
        (sourceCurrent.refreshHz - selected.refreshHz).abs() < 0.001) {
      return null;
    }
    return ModeMatch(
      selected,
      reason: exact.isNotEmpty || multiple.isNotEmpty
          ? null
          : 'approximate refresh match (${selected.refreshHz}Hz for ${contentFps}Hz)',
    );
  }

  static double _score(DisplayMode mode, double fps) {
    final ratio = mode.refreshHz / fps;
    final integerPenalty = (ratio - ratio.round()).abs();
    return integerPenalty * 1000 + (mode.refreshHz - fps).abs();
  }

  static bool _isNearPair(double refreshHz, double contentFps) {
    if ((refreshHz - contentFps).abs() <= 0.01) return true;
    final is23976Pair =
        (refreshHz - 23.976).abs() <= 0.01 && (contentFps - 24).abs() <= 0.01 ||
        (refreshHz - 24).abs() <= 0.01 && (contentFps - 23.976).abs() <= 0.01;
    final is5994Pair =
        (refreshHz - 59.94).abs() <= 0.01 && (contentFps - 60).abs() <= 0.01 ||
        (refreshHz - 60).abs() <= 0.01 && (contentFps - 59.94).abs() <= 0.01;
    return is23976Pair || is5994Pair;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
