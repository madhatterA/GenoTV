/// One display mode this device supports.
class DisplayMode {
  const DisplayMode({
    required this.width,
    required this.height,
    required this.refreshHz,
    required this.isCurrent,
  });

  final int width;
  final int height;
  final double refreshHz;
  final bool isCurrent;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DisplayMode &&
          other.width == width &&
          other.height == height &&
          other.refreshHz == refreshHz &&
          other.isCurrent == isCurrent);

  @override
  int get hashCode => Object.hash(width, height, refreshHz, isCurrent);

  @override
  String toString() =>
      'DisplayMode(${width}x$height@${refreshHz}Hz${isCurrent ? ', current' : ''})';
}

/// Provided by Part 05, treated as a platform service, not a player-core
/// concern. Enumerate supported resolutions/refresh rates, select the
/// closest supported mode to the stream's cadence (including 23.976 vs 24
/// and 59.94 vs 60), apply only with user/device permission
/// (`research/technical/PLATFORM_PLAYBACK.md` "Display mode policy").
abstract interface class DisplayModeService {
  Future<List<DisplayMode>> availableModes();

  /// Switches to the closest supported mode for this content cadence, or
  /// returns null if none is close enough, or permission was unavailable.
  Future<DisplayModeLease?> matchFor({required double contentFps, int? width, int? height});
}

/// Holds the **restore obligation**: the previous display mode MUST be
/// restored on [release], on failure to apply the requested mode, and on
/// player teardown — including the error path. A lease that is garbage
/// collected without [release] having been called is a bug Part 08 will
/// hunt for.
abstract interface class DisplayModeLease {
  Future<void> release();
}
