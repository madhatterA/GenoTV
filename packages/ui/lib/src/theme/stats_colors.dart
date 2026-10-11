import 'package:flutter/painting.dart';

/// Colours of the player's download popover graph and "Stats for nerds"
/// overlay. Fixed (not theme-dependent): the overlay always sits on video.
abstract final class StatsColors {
  static const Color panel = Color(0xB8000000);
  static const Color text = Color(0xFFFFFFFF);
  static const Color label = Color(0xB3FFFFFF);
  static const Color heading = Color(0x99FFFFFF);
  static const Color baseline = Color(0x3DFFFFFF);
  static const Color graph = Color(0xFF66BB6A);
}
