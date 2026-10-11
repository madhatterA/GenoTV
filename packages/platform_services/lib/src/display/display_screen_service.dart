import '../channel/platform_channel.dart';
import '../channel/platform_events.dart';

/// Screen choices are native identifiers, not display-mode or mpv options.
final class DisplayScreens {
  DisplayScreens._(this.choices, this.selected);

  final Map<String, String> choices;
  final String selected;

  factory DisplayScreens.from(Object? value) {
    final payload = asMap(value);
    final raw = asMap(payload['choices']);
    final selected = payload['selected'];
    if (payload['supported'] == false ||
        raw.isEmpty ||
        raw.values.any((label) => label is! String) ||
        selected is! String ||
        !raw.containsKey(selected)) {
      throw StateError('Invalid native display-screen response: $payload');
    }
    return DisplayScreens._(
      Map.unmodifiable(raw.map((key, label) => MapEntry(key, label as String))),
      selected,
    );
  }
}

final class DisplayScreenService {
  const DisplayScreenService({required this.channel});

  final PlatformChannel channel;

  Future<DisplayScreens> displays() async =>
      DisplayScreens.from(await channel.invoke('display.screens'));

  Future<DisplayScreens> select(String id) async =>
      DisplayScreens.from(await channel.invoke('display.select', {'id': id}));

  Stream<DisplayScreens> get changes =>
      platformEvents(channel)
          .where((event) => event.payload['event'] == 'displayScreensChanged')
          .map((event) => DisplayScreens.from(event.payload));
}
