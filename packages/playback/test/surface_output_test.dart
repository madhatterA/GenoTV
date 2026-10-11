import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playback/playback.dart';
import 'package:playback/src/surface/surface_output.dart';
import 'package:video_surface/video_surface.dart' as native;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('video_surface');
  late StreamController<bool> hdr;
  late List<String> calls;
  late MemoryLogger logger;
  late SurfaceOutput output;
  Object? createError;
  setUp(() {
    hdr = StreamController<bool>.broadcast();
    calls = [];
    logger = MemoryLogger();
    createError = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'create') {
            if (createError != null) throw createError!;
            return {'id': 9, 'headroom': 6.0};
          }
          return null;
        });
    output = SurfaceOutput(
      attach: () => native.NativeVideoSurface.create(
        handle: Future.value(123),
        hdrSource: hdr.stream,
      ),
      texture: () async => calls.add('texture'),
      logger: logger,
      onError: (error, stack) => fail('$error'),
    );
  });
  tearDown(() async {
    await output.dispose();
    await hdr.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  Future<void> event(String method, Map<String, Object> values) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'video_surface',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, {'id': 9, ...values}),
          ),
          (_) {},
        );
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  test('headroom changes alone are not logged; a mode change is', () async {
    await output.prepare();
    for (final h in [5.0, 4.0, 3.0, 2.0]) {
      await event('screen', {'headroom': h});
    }
    List<String> lines() => [
      for (final r in logger.records)
        if (r.message.startsWith('video surface')) r.message,
    ];
    expect(lines(), hasLength(1));
    hdr.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(lines(), hasLength(2));
    expect(lines().last, contains('hdrNative'));
  });

  test(
    'native follows HDR source and live HDR off/on without texture',
    () async {
      await output.prepare();
      expect(output.mode.value.kind, SurfaceModeKind.sdrNative);
      hdr.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(output.mode.value.kind, SurfaceModeKind.hdrNative);
      await event('screen', {'headroom': 1.0});
      expect(output.mode.value.kind, SurfaceModeKind.sdrNative);
      expect(output.mode.value.reason, contains('no EDR headroom'));
      await event('screen', {'headroom': 6.0});
      expect(output.mode.value.kind, SurfaceModeKind.hdrNative);
      expect(calls, isNot(contains('texture')));
    },
  );
  test('creation failure selects texture with actual logged reason', () async {
    createError = PlatformException(
      code: 'create_failed',
      message: 'no Metal device',
    );
    await output.prepare();
    expect(output.mode.value.kind, SurfaceModeKind.texture);
    expect(output.mode.value.reason, contains('no Metal device'));
    expect(calls.last, 'texture');
    expect(logger.records.last.message, contains('no Metal device'));
  });
  test(
    'runtime failure releases native before texture and stays sticky',
    () async {
      await output.prepare();
      await event('failed', {'message': 'render context lost'});
      expect(output.mode.value.kind, SurfaceModeKind.texture);
      expect(output.mode.value.reason, contains('render context lost'));
      expect(calls.sublist(calls.length - 2), ['dispose', 'texture']);
      expect(output.nativeSurface, isNull);
      await event('screen', {'headroom': 6.0});
      expect(output.mode.value.kind, SurfaceModeKind.texture);
      expect(logger.records.last.message, contains('render context lost'));
    },
  );
  test(
    'dispose waits for preparation and releases native exactly once',
    () async {
      final preparation = output.prepare();
      await output.dispose();
      await preparation;
      await output.dispose();
      expect(calls.where((method) => method == 'dispose'), hasLength(1));
    },
  );
}
