import 'dart:async';
import 'dart:typed_data';

import '../channel/platform_channel.dart';
import '../channel/platform_events.dart';

final class KeepAwakeLease {
  KeepAwakeLease(this._releaseCallback);

  final Future<void> Function() _releaseCallback;
  bool _released = false;

  Future<void> release() async {
    if (_released) return;
    await _releaseCallback();
    _released = true;
  }
}

final class PlaybackLifecycleService {
  PlaybackLifecycleService({required this.channel}) {
    _subscription = platformEvents(channel).listen((event) {
      if (!_disposed) _events.add(event);
    });
  }

  final PlatformChannel channel;
  final StreamController<PlatformEvent> _events = StreamController.broadcast();
  late final StreamSubscription<PlatformEvent> _subscription;
  final Set<KeepAwakeLease> _leases = {};
  bool _disposed = false;

  Stream<PlatformEvent> get events => _events.stream;

  Future<KeepAwakeLease> acquireKeepAwake() async {
    if (_disposed) throw StateError('lifecycle service is disposed');
    await channel.invoke(PlatformMethods.lifecycleKeepAwake, {'enabled': true});
    late KeepAwakeLease lease;
    lease = KeepAwakeLease(() async {
      await channel.invoke(PlatformMethods.lifecycleReleaseAwake, {
        'enabled': false,
      });
      _leases.remove(lease);
    });
    _leases.add(lease);
    return lease;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    Object? firstError;
    StackTrace? firstStack;
    for (final lease in List<KeepAwakeLease>.of(_leases)) {
      try {
        await lease.release();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    await _subscription.cancel();
    await _events.close();
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }
}

final class MediaSessionInfo {
  const MediaSessionInfo({
    required this.title,
    this.subtitle,
    this.artworkUri,
    this.artworkBytes,
    this.duration,
    this.position,
    this.playing = false,
  });

  final String title;
  final String? subtitle;
  final Uri? artworkUri;
  final List<int>? artworkBytes;
  final Duration? duration;
  final Duration? position;
  final bool playing;
}

enum MediaSessionCommandType {
  play,
  pause,
  togglePlay,
  seekTo,
  skipForward,
  skipBackward,
  stop,
  unknown,
}

final class MediaSessionCommand {
  const MediaSessionCommand(this.type, {this.position});

  final MediaSessionCommandType type;
  final Duration? position;

  factory MediaSessionCommand.from(Object? raw) {
    final map = asMap(raw);
    final type = switch (stringValue(map['command'])) {
      'play' => MediaSessionCommandType.play,
      'pause' => MediaSessionCommandType.pause,
      'togglePlay' => MediaSessionCommandType.togglePlay,
      'seekTo' => MediaSessionCommandType.seekTo,
      'skipForward' => MediaSessionCommandType.skipForward,
      'skipBackward' => MediaSessionCommandType.skipBackward,
      'stop' => MediaSessionCommandType.stop,
      _ => MediaSessionCommandType.unknown,
    };
    final seconds = doubleValue(map['positionSeconds']);
    return MediaSessionCommand(
      type,
      position: seconds == null
          ? null
          : Duration(microseconds: (seconds * 1000000).round()),
    );
  }
}

final class MediaSessionService {
  MediaSessionService({required this.channel, DateTime Function()? now})
    : _now = now ?? DateTime.now {
    _subscription = platformEvents(channel).listen((event) {
      if (!_disposed && event.type == PlatformEventType.mediaCommand) {
        _commands.add(MediaSessionCommand.from(event.payload));
      }
    });
  }

  final PlatformChannel channel;
  final DateTime Function() _now;
  final StreamController<MediaSessionCommand> _commands =
      StreamController.broadcast();
  late final StreamSubscription<PlatformEvent> _subscription;
  static const _minInterval = Duration(seconds: 1);
  DateTime? _lastUpdate;
  Map<String, Object?>? _lastPayload;
  bool _disposed = false;

  Stream<MediaSessionCommand> get commands => _commands.stream;

  Future<void> updateNowPlaying(MediaSessionInfo info) async {
    if (_disposed) return;
    final now = _now();
    final payload = <String, Object?>{
      'title': info.title,
      'subtitle': info.subtitle,
      'artworkUri': info.artworkUri?.toString(),
      // Uint8List, not List<int>: only a typed list crosses the channel as bytes.
      'artworkBytes': info.artworkBytes == null
          ? null
          : Uint8List.fromList(info.artworkBytes!),
      'durationSeconds': info.duration?.inMicroseconds == null
          ? null
          : info.duration!.inMicroseconds / 1000000,
      'positionSeconds': info.position?.inMicroseconds == null
          ? null
          : info.position!.inMicroseconds / 1000000,
      'playing': info.playing,
    };
    // Only position-only ticks are throttled; a pause, seek-state or metadata
    // change must reach the OS controls immediately.
    final last = _lastPayload;
    // A paused position change is a seek, never a tick: always publish it.
    if (info.playing &&
        last != null &&
        now.difference(_lastUpdate!) < _minInterval) {
      final rest = {...payload}..remove('positionSeconds');
      final lastRest = {...last}..remove('positionSeconds');
      if (_sameFields(rest, lastRest)) return;
    }
    _lastUpdate = now;
    _lastPayload = payload;
    await channel.invoke(PlatformMethods.mediaSessionUpdate, payload);
  }

  static bool _sameFields(Map<String, Object?> a, Map<String, Object?> b) =>
      a.entries.every((e) {
        final other = b[e.key];
        final v = e.value;
        return v is List && other is List
            ? v.length == other.length && _listEq(v, other)
            : v == other;
      });

  static bool _listEq(List<Object?> a, List<Object?> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> clear() async {
    if (_disposed) return;
    _lastPayload = null;
    await channel.invoke(PlatformMethods.mediaSessionClear);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await channel.invoke(PlatformMethods.mediaSessionClear);
    await _subscription.cancel();
    await _commands.close();
  }
}
