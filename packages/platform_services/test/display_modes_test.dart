import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';

final class _DisplayChannel implements PlatformChannel {
  _DisplayChannel(this.payload);

  final Object? payload;

  @override
  Future<Object?> invoke(String method, [Object? arguments]) async => payload;

  @override
  Stream<Object?> get events => const Stream<Object?>.empty();

  @override
  Future<void> dispose() async {}
}

void main() {
  test(
    'deduplicates near-identical modes and preserves fractional rates',
    () async {
      final service = DisplayModeServiceImpl(
        channel: _DisplayChannel({
          'supported': true,
          'modes': [
            {
              'width': 1920,
              'height': 1080,
              'refreshHz': 23.976,
              'isCurrent': false,
            },
            {
              'width': 1920,
              'height': 1080,
              'refreshHz': 23.9764,
              'isCurrent': false,
            },
            {
              'width': 1920,
              'height': 1080,
              'refreshHz': 24.0,
              'isCurrent': false,
            },
            {
              'width': 1920,
              'height': 1080,
              'refreshHz': 29.97,
              'isCurrent': false,
            },
            {
              'width': 1920,
              'height': 1080,
              'refreshHz': 30.0,
              'isCurrent': false,
            },
            {
              'width': 1920,
              'height': 1080,
              'refreshHz': 59.94,
              'isCurrent': false,
            },
            {
              'width': 1920,
              'height': 1080,
              'refreshHz': 60.0,
              'isCurrent': true,
            },
          ],
        }),
      );
      final modes = await service.availableModes();
      expect(modes.map((mode) => mode.refreshHz), [
        23.976,
        24.0,
        29.97,
        30.0,
        59.94,
        60.0,
      ]);
      expect(modes.where((mode) => mode.isCurrent), hasLength(1));
      expect(modes.singleWhere((mode) => mode.isCurrent).refreshHz, 60.0);
    },
  );

  test('unsupported platform returns an empty list and diagnostic', () async {
    final service = DisplayModeServiceImpl(
      channel: _DisplayChannel({
        'supported': false,
        'modes': <Object?>[],
        'reason': 'platform.unsupported: display modes',
      }),
    );
    expect(await service.availableModes(), isEmpty);
    expect(service.diagnostic, contains('platform.unsupported'));
  });

  test('zero refresh is reported as 60 Hz like Kodi macOS 4.4', () async {
    final service = DisplayModeServiceImpl(
      channel: _DisplayChannel({
        'supported': true,
        'modes': [
          {'width': 3024, 'height': 1964, 'refreshHz': 0, 'isCurrent': true},
        ],
      }),
    );
    final modes = await service.availableModes();
    expect(modes, hasLength(1));
    expect(modes.single.refreshHz, 60);
    expect(modes.single.isCurrent, isTrue);
  });
}
