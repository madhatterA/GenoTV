import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

/// How the video is currently reaching the display.
enum SurfaceMode {
  /// mpv draws into a native EDR surface and the source is HDR on an EDR display.
  hdrNative,

  /// mpv draws into the native surface but output is SDR (SDR source or no EDR display).
  sdrNative,

  /// No native surface; the caller keeps media_kit's texture path.
  texture,
}

/// Current surface mode and why. `reason` is always set.
@immutable
final class SurfaceState {
  const SurfaceState(this.mode, this.reason);

  final SurfaceMode mode;
  final String reason;

  @override
  bool operator ==(Object other) =>
      other is SurfaceState && other.mode == mode && other.reason == reason;

  @override
  int get hashCode => Object.hash(mode, reason);

  @override
  String toString() => 'SurfaceState(${mode.name}: $reason)';
}

/// Pure mode decision; the only place the HDR/SDR/texture policy lives.
SurfaceState resolveSurfaceState({
  required double edrHeadroom,
  required bool hdrSource,
}) {
  final headroom = edrHeadroom.toStringAsFixed(2);
  if (edrHeadroom <= 1.0) {
    return SurfaceState(
      SurfaceMode.sdrNative,
      'display reports no EDR headroom ($headroom)',
    );
  }
  if (!hdrSource) {
    return SurfaceState(
      SurfaceMode.sdrNative,
      'source is SDR; EDR headroom $headroom unused',
    );
  }
  return SurfaceState(
    SurfaceMode.hdrNative,
    'HDR source on EDR display, headroom $headroom',
  );
}

const MethodChannel _channel = MethodChannel('video_surface');

/// A native HDR-capable video surface for one media_kit [Player].
///
/// mpv renders into a `CAMetalLayer` (EDR, half-float, extended linear Display P3) owned by
/// this plugin; Flutter widgets stack above [build]. Dispose it before the [Player].
final class NativeVideoSurface {
  NativeVideoSurface._(this._id, this.state, this._hdrSource, this._headroom);

  final int? _id;
  StreamSubscription<bool>? _hdrSub;
  bool _hdrSource;
  double _headroom;
  bool _disposed = false;

  /// Current [SurfaceState]; listen to follow HDR/SDR changes and display moves.
  final ValueNotifier<SurfaceState> state;

  /// Creates the surface for [player]; on failure returns a `texture`-mode surface whose
  /// reason is the failure.
  static Future<NativeVideoSurface> attach(Player player) {
    return create(
      handle: player.handle,
      hdrSource: player.stream.videoParams.map(
        (p) => p.gamma == 'pq' || p.gamma == 'hlg',
      ),
    );
  }

  /// [attach] with the player's pieces passed in directly.
  static Future<NativeVideoSurface> create({
    required Future<int> handle,
    required Stream<bool> hdrSource,
  }) async {
    // The one platform gate: other OSes keep the texture path until their phases land.
    if (!Platform.isMacOS) {
      return NativeVideoSurface._(
        null,
        ValueNotifier(
          const SurfaceState(
            SurfaceMode.texture,
            'native surface not implemented on this platform',
          ),
        ),
        false,
        1,
      );
    }
    final Map<Object?, Object?> info;
    try {
      info = (await _channel.invokeMapMethod<Object?, Object?>('create', {
        'handle': await handle,
      }))!;
    } on PlatformException catch (e) {
      return NativeVideoSurface._(
        null,
        ValueNotifier(
          SurfaceState(SurfaceMode.texture, '${e.code}: ${e.message}'),
        ),
        false,
        1,
      );
    }
    final id = info['id']! as int;
    final headroom = _headroomOf(info);
    final surface = NativeVideoSurface._(
      id,
      ValueNotifier(
        resolveSurfaceState(edrHeadroom: headroom, hdrSource: false),
      ),
      false,
      headroom,
    );
    surface._hdrSub = hdrSource.listen((hdr) async {
      if (surface._disposed) return;
      surface._hdrSource = hdr;
      try {
        await _channel.invokeMethod<void>('source', {'id': id, 'hdr': hdr});
        if (!surface._disposed) surface._publish();
      } catch (error) {
        if (!surface._disposed) {
          surface.state.value = SurfaceState(
            SurfaceMode.texture,
            'native source update failed: $error',
          );
        }
      }
    });
    _channel.setMethodCallHandler(_onNative);
    _live[id] = surface;
    return surface;
  }

  static final Map<int, NativeVideoSurface> _live = {};

  static Future<void> _onNative(MethodCall call) async {
    final info = call.arguments as Map<Object?, Object?>;
    final s = _live[info['id']];
    if (s == null || s._disposed) return;
    if (call.method == 'failed') {
      s.state.value = SurfaceState(
        SurfaceMode.texture,
        'native failure: ${info['message']}',
      );
      return;
    }
    if (call.method != 'screen') return;
    final headroom = _headroomOf(info);
    if (headroom == s._headroom) return;
    s._headroom = headroom;
    s._publish();
  }

  static double _headroomOf(Map<Object?, Object?> info) =>
      (info['headroom']! as num).toDouble();

  void _publish() => state.value = resolveSurfaceState(
    edrHeadroom: _headroom,
    hdrSource: _hdrSource,
  );

  /// The widget showing the video; stack Flutter controls above it. Only valid while
  /// [state] is not [SurfaceMode.texture].
  Widget build() {
    final id = _id;
    if (id == null) {
      throw StateError('no native surface: ${state.value.reason}');
    }
    return AppKitView(
      key: ValueKey<int>(id),
      viewType: 'video_surface/view',
      creationParams: {'id': id},
      creationParamsCodec: const StandardMessageCodec(),
    );
  }

  /// Native diagnostics: EDR headroom, `peak` (max linear value in the last frame, 1.0 =
  /// SDR white), frames rendered and whether the layer requests EDR.
  Future<Map<String, Object?>> probe() async {
    final id = _id;
    if (id == null) return {};
    return Map<String, Object?>.from(
      (await _channel.invokeMapMethod<String, Object?>('probe', {'id': id}))!,
    );
  }

  /// Main screen EDR headroom (`edr` now, `potential` maximum); 1.0 means SDR only.
  static Future<Map<String, double>> screenEdr() async =>
      (await _channel.invokeMapMethod<String, double>('screenEdr'))!;

  /// Live native objects (`views`, `instances`, `ioSurfaces`, `glContexts`).
  static Future<Map<String, int>> nativeCounters() async =>
      (await _channel.invokeMapMethod<String, int>('counters'))!;

  /// Frees the native render context and surface. Call before disposing the [Player].
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _hdrSub?.cancel();
    final id = _id;
    if (id != null) {
      _live.remove(id);
      await _channel.invokeMethod<void>('dispose', {'id': id});
    }
    state.dispose();
  }
}
