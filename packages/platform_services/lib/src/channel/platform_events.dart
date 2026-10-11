import 'dart:async';

import 'platform_channel.dart';

enum PlatformEventType {
  audioRouteChanged,
  audioInterruptionBegan,
  audioInterruptionEnded,
  becameNoisy,
  appBackgrounded,
  appForegrounded,
  mediaCommand,
  unknown,
}

final class PlatformEvent {
  const PlatformEvent(this.type, this.payload);

  final PlatformEventType type;
  final Map<String, Object?> payload;

  bool get shouldResume => payload['shouldResume'] == true;
  String? get lossKind =>
      payload['lossKind'] is String ? payload['lossKind'] as String : null;

  factory PlatformEvent.from(Object? raw) {
    final payload = asMap(raw);
    final value =
        stringValue(payload['event']) ??
        stringValue(payload['type']) ??
        stringValue(payload['name']);
    final type = switch (value) {
      'audioRouteChanged' ||
      'audio.route.changed' ||
      'routeChanged' => PlatformEventType.audioRouteChanged,
      'audioInterruptionBegan' => PlatformEventType.audioInterruptionBegan,
      'audioInterruptionEnded' => PlatformEventType.audioInterruptionEnded,
      'becameNoisy' => PlatformEventType.becameNoisy,
      'appBackgrounded' => PlatformEventType.appBackgrounded,
      'appForegrounded' => PlatformEventType.appForegrounded,
      'mediaCommand' => PlatformEventType.mediaCommand,
      _ => PlatformEventType.unknown,
    };
    return PlatformEvent(type, payload);
  }
}

Stream<PlatformEvent> platformEvents(PlatformChannel channel) =>
    channel.events.map(PlatformEvent.from);
