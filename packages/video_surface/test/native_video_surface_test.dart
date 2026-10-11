import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_surface/video_surface.dart';

const _channel = MethodChannel('video_surface');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];

  void mockNative(Future<Object?> Function(MethodCall) handler) {
    calls.clear();
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (c) {
          calls.add(c);
          return handler(c);
        });
  }

  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('resolveSurfaceState', () {
    test('HDR source on EDR display is hdrNative', () {
      final s = resolveSurfaceState(edrHeadroom: 6.15, hdrSource: true);
      expect(s.mode, SurfaceMode.hdrNative);
      expect(s.reason, contains('6.15'));
    });

    test(
      'SDR source on EDR display is sdrNative with the source as reason',
      () {
        final s = resolveSurfaceState(edrHeadroom: 16, hdrSource: false);
        expect(s.mode, SurfaceMode.sdrNative);
        expect(s.reason, contains('SDR'));
      },
    );

    test(
      'HDR source without EDR headroom drops to sdrNative, never hdrNative',
      () {
        final s = resolveSurfaceState(edrHeadroom: 1.0, hdrSource: true);
        expect(s.mode, SurfaceMode.sdrNative);
        expect(s.reason, contains('no EDR headroom'));
      },
    );
  });

  group('NativeVideoSurface', () {
    test('source update errors report texture instead of escaping', () async {
      mockNative((call) async {
        if (call.method == 'source') {
          throw PlatformException(
            code: 'source_failed',
            message: 'color update',
          );
        }
        return {'id': 21, 'headroom': 6.0};
      });
      final hdr = StreamController<bool>.broadcast();
      final surface = await NativeVideoSurface.create(
        handle: Future.value(1),
        hdrSource: hdr.stream,
      );
      hdr.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(surface.state.value.mode, SurfaceMode.texture);
      expect(surface.state.value.reason, contains('color update'));
      await surface.dispose();
      await hdr.close();
    });

    test('in-flight source update cannot publish after disposal', () async {
      final source = Completer<Object?>();
      mockNative(
        (call) async => call.method == 'source'
            ? source.future
            : {'id': 22, 'headroom': 6.0},
      );
      final hdr = StreamController<bool>.broadcast();
      final surface = await NativeVideoSurface.create(
        handle: Future.value(1),
        hdrSource: hdr.stream,
      );
      hdr.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await surface.dispose();
      source.complete(null);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await hdr.close();
    });

    test('create reports the native headroom and follows HDR source and screen changes', () async {
      mockNative(
        (c) async => {'id': 7, 'edr': 1.0, 'potential': 16.0, 'headroom': 16.0},
      );
      final hdr = StreamController<bool>();
      final surface = await NativeVideoSurface.create(
        handle: Future.value(1234),
        hdrSource: hdr.stream,
      );

      expect(calls.single.method, 'create');
      expect(calls.single.arguments, {'handle': 1234});
      expect(surface.state.value.mode, SurfaceMode.sdrNative);

      hdr.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(calls.last.method, 'source');
      expect(calls.last.arguments, {'id': 7, 'hdr': true});
      expect(surface.state.value.mode, SurfaceMode.hdrNative);

      // Window moved to a display without EDR: native reports headroom 1.0.
      await TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'video_surface',
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('screen', {
                'id': 7,
                'edr': 1.0,
                'potential': 1.0,
                'headroom': 1.0,
              }),
            ),
            (_) {},
          );
      expect(surface.state.value.mode, SurfaceMode.sdrNative);
      expect(surface.state.value.reason, contains('no EDR headroom'));

      await surface.dispose();
      await hdr.close();
    });

    test(
      'a native runtime failure drops the state to texture with its message',
      () async {
        mockNative(
          (c) async => {
            'id': 5,
            'edr': 1.0,
            'potential': 16.0,
            'headroom': 16.0,
          },
        );
        final surface = await NativeVideoSurface.create(
          handle: Future.value(1),
          hdrSource: const Stream.empty(),
        );

        await TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              'video_surface',
              const StandardMethodCodec().encodeMethodCall(
                const MethodCall('failed', {
                  'id': 5,
                  'message': 'Metal: IOSurface 10x10 allocation failed',
                }),
              ),
              (_) {},
            );
        expect(surface.state.value.mode, SurfaceMode.texture);
        expect(
          surface.state.value.reason,
          contains('IOSurface 10x10 allocation failed'),
        );
        await surface.dispose();
      },
    );

    test(
      'create failure is reported as texture with the native reason',
      () async {
        mockNative(
          (c) async => throw PlatformException(
            code: 'create_failed',
            message: 'no 3.2 core pixel format',
          ),
        );
        final surface = await NativeVideoSurface.create(
          handle: Future.value(1),
          hdrSource: const Stream.empty(),
        );

        expect(surface.state.value.mode, SurfaceMode.texture);
        expect(
          surface.state.value.reason,
          'create_failed: no 3.2 core pixel format',
        );
        expect(surface.build, throwsStateError);
        expect(await surface.probe(), isEmpty);
        await surface.dispose();
        expect(calls.map((c) => c.method), ['create']);
      },
    );

    test('dispose releases the native surface once', () async {
      mockNative(
        (c) async => c.method == 'create'
            ? {'id': 3, 'edr': 1.0, 'potential': 1.0, 'headroom': 1.0}
            : null,
      );
      final surface = await NativeVideoSurface.create(
        handle: Future.value(1),
        hdrSource: const Stream.empty(),
      );
      await surface.dispose();
      await surface.dispose();

      expect(calls.map((c) => c.method), ['create', 'dispose']);
      expect(calls.last.arguments, {'id': 3});
    });
  });
}
