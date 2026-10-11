import 'package:contracts/contracts.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';

final class _ModeChannel implements PlatformChannel {
  _ModeChannel(this.handler);

  final Object? Function(String method, Object? arguments) handler;
  final calls = <String>[];

  @override
  Future<Object?> invoke(String method, [Object? arguments]) async {
    calls.add(method);
    return handler(method, arguments);
  }

  @override
  Stream<Object?> get events => const Stream<Object?>.empty();

  @override
  Future<void> dispose() async {}
}

const _modes = [
  DisplayMode(width: 1920, height: 1080, refreshHz: 23.976, isCurrent: false),
  DisplayMode(width: 1920, height: 1080, refreshHz: 24, isCurrent: false),
  DisplayMode(width: 1920, height: 1080, refreshHz: 47.952, isCurrent: false),
  DisplayMode(width: 1920, height: 1080, refreshHz: 59.94, isCurrent: false),
  DisplayMode(width: 1920, height: 1080, refreshHz: 60, isCurrent: false),
  DisplayMode(width: 1280, height: 720, refreshHz: 120, isCurrent: false),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('exact fractional match wins', () {
    expect(
      ModeMatcher.match(contentFps: 23.976, modes: _modes)!.mode.refreshHz,
      23.976,
    );
  });

  test('integer multiple wins over near 24Hz', () {
    final result = ModeMatcher.match(
      contentFps: 23.976,
      modes: _modes.where((mode) => mode.refreshHz != 23.976).toList(),
    );
    expect(result!.mode.refreshHz, 47.952);
    expect(result.reason, isNull);
  });

  test('near match is marked approximate when no better mode exists', () {
    final result = ModeMatcher.match(
      contentFps: 23.976,
      modes: const [
        DisplayMode(width: 1920, height: 1080, refreshHz: 24, isCurrent: false),
        DisplayMode(width: 1920, height: 1080, refreshHz: 60, isCurrent: false),
      ],
    );
    expect(result!.mode.refreshHz, 24);
    expect(result.reason, contains('approximate'));
  });

  test('59.94 uses 60 only as an explicit approximation', () {
    final result = ModeMatcher.match(
      contentFps: 59.94,
      modes: const [
        DisplayMode(width: 1920, height: 1080, refreshHz: 60, isCurrent: false),
      ],
    );
    expect(result!.mode.refreshHz, 60);
    expect(result.reason, contains('approximate'));
  });

  test('59.94 remains distinct from 60 and resolution is preserved', () {
    final result = ModeMatcher.match(
      contentFps: 59.94,
      modes: _modes,
      current: _modes[0],
    );
    expect(result!.mode.refreshHz, 59.94);
    expect(result.mode.width, 1920);
    expect(result.mode.height, 1080);
  });

  test(
    '24fps does not select a 5x (120Hz) multiple: Kodi allows 1x/2x/2.5x',
    () {
      final result = ModeMatcher.match(
        contentFps: 24,
        modes: _modes,
        width: 1280,
        height: 720,
      );
      expect(result, isNull);
    },
  );

  test('matching current mode is a no-op', () {
    final result = ModeMatcher.match(
      contentFps: 23.976,
      modes: _modes,
      current: _modes[0],
    );
    expect(result, isNull);
  });

  test('no acceptable mode returns null', () {
    expect(
      ModeMatcher.match(
        contentFps: 25,
        modes: const [
          DisplayMode(
            width: 1920,
            height: 1080,
            refreshHz: 60,
            isCurrent: false,
          ),
        ],
      ),
      isNull,
    );
  });

  test('lease release restores exactly once and is idempotent', () async {
    final channel = _ModeChannel((method, _) => {'supported': true});
    final lease = DisplayModeLeaseImpl(
      channel: channel,
      previous: _modes[0],
      restoreArguments: {'width': 1920, 'height': 1080, 'refreshHz': 23.976},
    );
    await lease.release();
    await lease.release();
    expect(
      channel.calls.where((call) => call == PlatformMethods.displayRestore),
      hasLength(1),
    );
  });

  test('apply failure restores and surfaces typed failure', () async {
    final channel = _ModeChannel((method, _) {
      if (method == PlatformMethods.displayModes) {
        return {
          'supported': true,
          'modes': [
            {'width': 1920, 'height': 1080, 'refreshHz': 24, 'isCurrent': true},
            {
              'width': 1920,
              'height': 1080,
              'refreshHz': 60,
              'isCurrent': false,
            },
          ],
        };
      }
      if (method == PlatformMethods.displayApply) {
        return {'supported': false, 'reason': 'mode vanished'};
      }
      return {'supported': true};
    });
    final service = DisplayModeServiceImpl(channel: channel);
    await expectLater(
      service.matchFor(contentFps: 60),
      throwsA(isA<PlatformFailure>()),
    );
    expect(channel.calls, contains(PlatformMethods.displayRestore));
  });

  test('service teardown restores an active lease', () async {
    final channel = _ModeChannel((method, _) {
      if (method == PlatformMethods.displayModes) {
        return {
          'supported': true,
          'modes': [
            {'width': 1920, 'height': 1080, 'refreshHz': 24, 'isCurrent': true},
            {
              'width': 1920,
              'height': 1080,
              'refreshHz': 60,
              'isCurrent': false,
            },
          ],
        };
      }
      return {'supported': true};
    });
    final service = DisplayModeServiceImpl(channel: channel);
    expect(await service.matchFor(contentFps: 60), isNotNull);
    await service.dispose();
    expect(channel.calls, contains(PlatformMethods.displayRestore));
  });

  test('lifecycle detach without release restores and diagnostics record the match', () async {
    final channel = _ModeChannel((method, _) {
      if (method == PlatformMethods.displayModes) {
        return {
          'supported': true,
          'modes': [
            {'width': 1920, 'height': 1080, 'refreshHz': 24, 'isCurrent': true},
            {
              'width': 1920,
              'height': 1080,
              'refreshHz': 60,
              'isCurrent': false,
            },
          ],
        };
      }
      return {'supported': true};
    });
    final service = DisplayModeServiceImpl(channel: channel);
    expect(await service.matchFor(contentFps: 60), isNotNull);
    expect(service.matchDiagnostic, contains('requested 60.0Hz'));
    expect(service.matchDiagnostic, contains('chosen 1920x1080@60.0Hz'));
    expect(service.matchDiagnostic, contains('previous 1920x1080@24.0Hz'));
    service.didChangeAppLifecycleState(AppLifecycleState.detached);
    await Future<void>.delayed(Duration.zero);
    expect(channel.calls, contains(PlatformMethods.displayRestore));
    await service.dispose();
  });
}
