import 'package:contracts/contracts.dart';

/// The display modes the user allows switching to, from the Expert
/// "display mode whitelist" text: comma-separated entries, each `WxH`,
/// `WxH@Hz` or `@Hz` (`1920x1080@24, 3840x2160, @59.94`). Empty allows every
/// mode. An entry that does not parse allows nothing and is listed in
/// [invalid], so a typo never widens what the app may switch to.
final class DisplayModeWhitelist {
  const DisplayModeWhitelist._(this._entries, this.invalid);

  static const DisplayModeWhitelist all = DisplayModeWhitelist._(null, []);

  factory DisplayModeWhitelist.parse(String text) {
    if (text.trim().isEmpty) return all;
    final entries = <_Entry>[];
    final invalid = <String>[];
    final pattern = RegExp(r'^(?:(\d+)x(\d+))?(?:@(\d+(?:\.\d+)?))?$');
    for (final raw in text.split(',')) {
      final token = raw.trim().toLowerCase();
      final match = token.isEmpty ? null : pattern.firstMatch(token);
      if (match == null) {
        invalid.add(raw.trim());
        continue;
      }
      entries.add(
        _Entry(
          width: int.tryParse(match[1] ?? ''),
          height: int.tryParse(match[2] ?? ''),
          hz: double.tryParse(match[3] ?? ''),
        ),
      );
    }
    return DisplayModeWhitelist._(entries, invalid);
  }

  final List<_Entry>? _entries;

  /// Entries of the source text that are not valid; they allow nothing.
  final List<String> invalid;

  bool allows(DisplayMode mode) =>
      _entries == null || _entries.any((entry) => entry.matches(mode));

  List<DisplayMode> filter(List<DisplayMode> modes) =>
      modes.where(allows).toList();
}

final class _Entry {
  const _Entry({this.width, this.height, this.hz});

  final int? width;
  final int? height;
  final double? hz;

  bool matches(DisplayMode mode) =>
      (width == null || mode.width == width) &&
      (height == null || mode.height == height) &&
      (hz == null || (mode.refreshHz - hz!).abs() < 0.01);
}
