import 'package:flutter/widgets.dart' show Locale;

import 'dart:async';

import 'package:cast/dart_cast.dart';
import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:ui/ui.dart';

/// DLNA capability for one renderer; the default asks its GetProtocolInfo.
typedef DlnaCompatibility = Future<CastCompatibility> Function(
  CastDevice device,
  CastMediaType type,
);

Future<CastCompatibility> _askRenderer(CastDevice d, CastMediaType t) async {
  final s = DlnaSession.fromDevice(d);
  try {
    return await s.compatibilityFor(t);
  } finally {
    s.dispose();
  }
}

/// A fresh [CastService] with Chromecast and DLNA discovery and sessions.
CastService createCastService() => CastService(
  discoveryProviders: [ChromecastDiscoveryProvider(), DlnaDiscoveryProvider()],
  sessionFactory: (device) {
    if (device.protocol == CastProtocol.chromecast) {
      return ChromecastSession(
        device: device,
        mediaTransformer: DeviceMediaTransformer(device: device),
      );
    }
    late DlnaSession session;
    session = DlnaSession.fromDevice(
      device,
      mediaTransformer: DeviceMediaTransformer(
        device: device,
        dlnaSink: () => session.protocolInfoSink(),
      ),
    );
    return session;
  },
);

/// AirPlay where the platform has it (macOS for now), else null.
AirPlaySession Function()? get platformAirPlay =>
    AirPlaySession.isSupported ? AirPlaySession.new : null;

/// Container and codecs as the cast capability tables name them, from what
/// mpv reported. mpv says `matroska,webm` for both; a VP8/VP9/AV1 stream in
/// it is WebM, anything else is Matroska.
({String container, String video, String audio})? _facts(MediaInfo i) {
  final c = i.container?.toLowerCase(), v = i.videoCodec, a = i.audioCodec;
  if (c == null || v == null || a == null) return null;
  final webm = {'vp8', 'vp9', 'av1'}.contains(v.toLowerCase());
  final container = c.contains('matroska')
      ? (webm ? 'webm' : 'mkv')
      : c.contains('mp4')
      ? 'mp4'
      : c.contains('mpegts')
      ? 'mpegts'
      : c;
  return (container: container, video: v, audio: a);
}

CastMediaType? _dlnaType(String container) => switch (container) {
  'mp4' => CastMediaType.mp4,
  'mkv' => CastMediaType.mkv,
  'mpegts' => CastMediaType.mpegTs,
  _ => null,
};

/// Connects the player's [CastUiController] seam to the cast package for one
/// opened file: lists TVs once each with the best protocol, casts the local
/// stream URL, mirrors the remote state, and on stop hands the TV's position
/// back to the local player.
final class CastBridge implements CastUiController {
  CastBridge({
    required this.service,
    required this.controller,
    required this.url,
    required this.title,
    required this.logger,
    this.dlnaCompatibility = _askRenderer,
    this.createAirPlay,
    this.failedToCast,
  }) {
    _infoSub = controller.mediaInfo.listen((i) {
      _info = i;
      _compat.clear();
      unawaited(_evaluateFound());
      if (_discoverySub != null) unawaited(_prepareAirPlay());
    });
  }

  final CastService service;
  final PlaybackController controller;
  final Uri url;
  final String title;
  final AppLogger logger;
  final String Function(String)? failedToCast;
  final DlnaCompatibility dlnaCompatibility;

  /// Makes the AirPlay session (AVPlayer, Apple platforms only); null where
  /// AirPlay does not exist, which hides its entry in the picker.
  final AirPlaySession Function()? createAirPlay;

  @override
  final ValueNotifier<CastUiState> state = ValueNotifier(const CastUiState());

  /// Null until the player has reported the file's facts; devices show as
  /// "checking" until then.
  MediaInfo? _info;
  late final StreamSubscription<MediaInfo> _infoSub;
  StreamSubscription<List<CastDevice>>? _discoverySub;
  final Map<String, CastCompatibility> _compat = {};
  List<MergedCastDevice> _merged = const [];
  CastSession? _session;

  /// Prepared on the proxy URL while the picker is open; becomes [_session]
  /// when the user picks an AirPlay device in the system route picker.
  AirPlaySession? _airPlay;
  StreamSubscription<bool>? _routeSub;
  final List<StreamSubscription<Object?>> _sessionSubs = [];

  CastCompatibility _compatOf(CastDevice d) =>
      _compat[d.id] ?? CastCompatibility.notCompatible;

  Future<CastCompatibility> _evaluate(CastDevice d) async {
    final f = _facts(_info!);
    if (f == null) return CastCompatibility.notCompatible;
    if (d.protocol == CastProtocol.chromecast) {
      return chromecastCompatibility(
        model: chromecastModelFromMd(d.metadata['md'] ?? ''),
        container: f.container,
        videoCodec: f.video,
        audioCodec: f.audio,
      );
    }
    final type = _dlnaType(f.container);
    if (type == null) return CastCompatibility.notCompatible;
    try {
      return await dlnaCompatibility(d, type);
    } catch (e, st) {
      logger.warn(
        'DLNA capability query failed for ${d.name}',
        error: e,
        stack: st,
      );
      return CastCompatibility.notCompatible;
    }
  }

  void _publishTargets() {
    _merged = mergeCastDevices(_found, _compatOf);
    state.value = CastUiState(
      targets: [
        for (final m in _merged)
          CastTarget(
            id: m.best.id,
            name: m.name,
            playable: m.compatibility != CastCompatibility.notCompatible,
            checking: m.devices.any((d) => !_compat.containsKey(d.id)),
          ),
      ],
      airPlayAvailable: _airPlayShown,
      airPlayPlayable: _airPlayPlayable,
    );
  }

  List<CastDevice> _found = const [];

  bool get _airPlayShown => createAirPlay != null && _session == null;

  /// AVPlayer plays MP4 only (no remuxer yet); other files get the AirPlay
  /// row marked unplayable, never no row.
  bool get _airPlayPlayable =>
      _info == null || _facts(_info!)?.container == 'mp4';

  /// AVPlayer plays MP4 (no remuxer yet), so only an MP4 is prepared.
  Future<void> _prepareAirPlay() async {
    if (_airPlay != null || _session != null) return;
    final f = _info == null ? null : _facts(_info!);
    if (f?.container != 'mp4') return;
    final s = createAirPlay?.call();
    if (s == null) return;
    try {
      await s.connect();
      await s.loadMedia(
        CastMedia(
          url: url.toString(),
          type: CastMediaType.mp4,
          title: title,
          startPosition: controller.currentState.position,
        ),
      );
    } catch (e, st) {
      logger.error('AirPlay prepare failed', error: e, stack: st);
      s.dispose();
      return;
    }
    if (_discoverySub == null) {
      await _releaseAirPlay(s); // picker closed while preparing
      return;
    }
    _airPlay = s;
    _routeSub = s.externalPlaybackStream.listen(
      (active) => unawaited(_onAirPlayRoute(s, active)),
    );
    _publishTargets();
  }

  Future<void> _releaseAirPlay(AirPlaySession s) async {
    try {
      await s.disconnect();
    } catch (e, st) {
      logger.warn('AirPlay release failed', error: e, stack: st);
    }
    s.dispose();
  }

  /// A device took the route: move playback there from the local position.
  /// Route lost while casting: hand the position back like Stop.
  Future<void> _onAirPlayRoute(AirPlaySession s, bool active) async {
    if (active && _session == null) {
      try {
        final at = controller.currentState.position;
        await controller.pause();
        _session = s;
        await s.seek(at);
        await s.play();
        _mirror(s, 'AirPlay');
      } catch (e, st) {
        logger.error('AirPlay start failed', error: e, stack: st);
        await _closeSession();
        state.value = CastUiState(
          targets: state.value.targets,
          error: "Couldn't cast to AirPlay",
        );
      }
    } else if (!active && identical(_session, s)) {
      await stop();
    }
  }

  /// Publishes the list, then fills in each device not yet checked. Does
  /// nothing past the publish while the file's facts are unknown; the info
  /// listener runs it again when they arrive.
  Future<void> _evaluateFound() async {
    _publishTargets();
    final info = _info;
    if (info == null) return;
    for (final d in _found.where((d) => !_compat.containsKey(d.id))) {
      final result = await _evaluate(d);
      if (!identical(info, _info)) return; // newer info restarted the pass
      _compat[d.id] = result;
      _publishTargets();
    }
  }

  @override
  Future<void> startDiscovery() async {
    await _discoverySub?.cancel();
    _discoverySub = service.startDiscovery().listen(
      (devices) async {
        _found = devices;
        await _evaluateFound();
      },
      onError: (Object e, StackTrace st) {
        logger.error('cast discovery failed', error: e, stack: st);
        state.value = CastUiState(
          error: "Couldn't search for devices",
          airPlayAvailable: _airPlayShown,
          airPlayPlayable: _airPlayPlayable,
        );
      },
    );
    await _prepareAirPlay();
  }

  @override
  Future<void> stopDiscovery() async {
    await _discoverySub?.cancel();
    _discoverySub = null;
    service.stopDiscovery();
    final s = _airPlay;
    if (s != null && _session == null) {
      await _routeSub?.cancel();
      _routeSub = null;
      _airPlay = null;
      await _releaseAirPlay(s);
    }
  }

  @override
  Future<void> cast(String targetId) async {
    final target = _merged.firstWhere((m) => m.best.id == targetId);
    final f = _facts(_info!)!;
    final type = f.container == 'mp4'
        ? CastMediaType.mp4
        : _dlnaType(f.container) ?? CastMediaType.mp4;
    final start = controller.currentState.position;
    try {
      final session = await service.connect(target.best);
      _session = session;
      await controller.pause();
      _mirror(session, target.name);
      await session.loadMedia(
        CastMedia(
          url: url.toString(),
          type: type,
          title: title,
          startPosition: start,
        ),
      );
    } catch (e, st) {
      logger.error('cast to ${target.name} failed', error: e, stack: st);
      for (final subscription in _sessionSubs) {
        await subscription.cancel();
      }
      _sessionSubs.clear();
      _session = null;
      state.value = CastUiState(
        targets: state.value.targets,
        airPlayAvailable: _airPlayShown,
        airPlayPlayable: _airPlayPlayable,
        error: e is CastTransformFailure
            ? e.message
            : state.value.error ??
                  (failedToCast ??
                      lookupAppStrings(const Locale('en'))
                          .cast_failedToCast)(target.name),
      );
    }
  }

  void _mirror(CastSession s, String name) {
    String? sessionError;
    void push() => state.value = CastUiState(
      castingTo: name,
      isPlaying: s.state == SessionState.playing,
      position: s.position,
      duration: s.duration,
      error: sessionError,
    );
    push();
    _sessionSubs.addAll([
      s.stateStream.listen((_) => push()),
      s.positionStream.listen((_) => push()),
      s.durationStream.listen((_) => push()),
      s.errorStream.listen((error) {
        sessionError = error is CastTransformFailure
            ? error.message
            : "Couldn't cast to $name";
        push();
      }),
    ]);
  }

  @override
  Future<void> play() async => _session?.play();
  @override
  Future<void> pause() async => _session?.pause();
  @override
  Future<void> seek(Duration position) async => _session?.seek(position);

  @override
  Future<void> stop() async {
    final s = _session;
    if (s == null) return;
    final at = s.position;
    final wasPlaying = s.state == SessionState.playing;
    await _closeSession();
    state.value = CastUiState(targets: state.value.targets);
    await controller.seek(at);
    if (wasPlaying) await controller.play();
  }

  Future<void> _closeSession() async {
    for (final sub in _sessionSubs) {
      await sub.cancel();
    }
    _sessionSubs.clear();
    await _routeSub?.cancel();
    _routeSub = null;
    final s = _session;
    _session = null;
    if (s == null) return;
    try {
      await s.stop();
      await s.disconnect();
    } catch (e, st) {
      logger.warn('cast stop failed', error: e, stack: st);
    }
    if (identical(s, _airPlay)) {
      _airPlay = null;
      s.dispose();
    }
  }

  Future<void> dispose() async {
    await _infoSub.cancel();
    await stopDiscovery();
    await _closeSession();
    await service.dispose();
    state.dispose();
  }
}
