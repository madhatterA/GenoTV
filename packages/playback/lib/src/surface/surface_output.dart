import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:video_surface/video_surface.dart' as native;

/// One render context per player, prepared before media opens and freed before it.
final class SurfaceOutput {
  SurfaceOutput({
    required this.attach,
    required this.texture,
    required this.logger,
    required this.onError,
  });

  final Future<native.NativeVideoSurface> Function() attach;
  final Future<void> Function() texture;
  final AppLogger logger;
  final void Function(Object, StackTrace) onError;
  final mode = ValueNotifier<SurfaceMode>(
    const SurfaceMode(SurfaceModeKind.texture, 'video output not initialized'),
  );
  native.NativeVideoSurface? nativeSurface;
  SurfaceModeKind? _loggedKind;
  Future<void>? _preparation;
  Future<void>? _fallback;
  bool _disposed = false;

  Future<void> prepare() => _preparation ??= _prepare();

  Future<void> _prepare() async {
    try {
      nativeSurface = await attach();
    } catch (error, stack) {
      logger.warn('native surface creation failed', error: error, stack: stack);
      await _fallBack('native surface creation failed: $error');
      return;
    }
    final surface = nativeSurface!;
    surface.state.addListener(_changed);
    if (surface.state.value.mode == native.SurfaceMode.texture) {
      await _fallBack(surface.state.value.reason);
    } else {
      _publish(surface.state.value);
    }
  }

  void _changed() {
    final state = nativeSurface!.state.value;
    if (state.mode == native.SurfaceMode.texture) {
      unawaited(
        _fallBack(state.reason).catchError((Object error, StackTrace stack) {
          logger.error('texture fallback failed', error: error, stack: stack);
          onError(error, stack);
        }),
      );
    } else if (_fallback == null) {
      _publish(state);
    }
  }

  void _publish(native.SurfaceState state) {
    final kind = switch (state.mode) {
      native.SurfaceMode.hdrNative => SurfaceModeKind.hdrNative,
      native.SurfaceMode.sdrNative => SurfaceModeKind.sdrNative,
      native.SurfaceMode.texture => SurfaceModeKind.texture,
    };
    final changed = _loggedKind != kind;
    _loggedKind = kind;
    mode.value = SurfaceMode(kind, state.reason);
    // The reason carries the live EDR headroom, which moves constantly; only
    // a change of mode is worth a log line.
    if (changed) logger.info('video surface ${kind.name}: ${state.reason}');
  }

  Future<void> _fallBack(String reason) => _fallback ??= _useTexture(reason);

  Future<void> _useTexture(String reason) async {
    final surface = nativeSurface;
    nativeSurface = null;
    if (surface != null) {
      surface.state.removeListener(_changed);
      await surface.dispose();
    }
    await texture();
    mode.value = SurfaceMode(SurfaceModeKind.texture, reason);
    logger.warn('video surface texture: $reason');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _preparation;
      await _fallback;
    } finally {
      final surface = nativeSurface;
      nativeSurface = null;
      if (surface != null) {
        surface.state.removeListener(_changed);
        await surface.dispose();
      }
      mode.dispose();
    }
  }
}
