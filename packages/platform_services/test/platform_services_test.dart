import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';

final class FakeChannel implements PlatformChannel {
  FakeChannel(this.handler);

  final FutureOr<Object?> Function(String, Object?) handler;
  final StreamController<Object?> _events = StreamController.broadcast();
  final calls = <String>[];

  void emit(Object event) => _events.add(event);

  @override
  Future<Object?> invoke(String method, [Object? arguments]) async {
    calls.add(method);
    return handler(method, arguments);
  }

  @override
  Stream<Object?> get events => _events.stream;

  @override
  Future<void> dispose() => _events.close();
}

void main() {
  runPlatformContractTests(
    createCapabilities: () => PlatformCapabilitiesService(
      channel: FakeChannel(
        (method, _) => {
          'hardwareDecode': false,
          'decoders': <String>[],
          'hdrOutput': false,
          'hdrFormats': <String>[],
          'displayModeSwitching': false,
          'audioPassthrough': false,
          'passthroughFormats': <String>[],
          'diagnostics': {'probe': 'test'},
        },
      ),
    ),
    createDisplayModeService: () => DisplayModeServiceImpl(
      channel: FakeChannel(
        (method, _) => {
          'supported': false,
          'modes': <Object?>[],
          'reason': 'test platform unsupported',
        },
      ),
    ),
    createAudioOutputService: () => AudioOutputServiceImpl(
      channel: FakeChannel(
        (method, _) => {
          'passthrough': false,
          'fallbackReason': 'test sink unsupported',
          'deviceId': 'test',
        },
      ),
    ),
    passthroughRequestSpec: () => const AudioStreamSpec(
      codec: 'eac3',
      channels: 6,
      sampleRate: 48000,
      bitDepth: 24,
      requestedPassthrough: true,
    ),
  );

  test('capability probe caches success and invalidates on demand', () async {
    var probes = 0;
    final channel = FakeChannel((method, _) {
      if (method == PlatformMethods.probe) {
        probes++;
        return {
          'hardwareDecode': true,
          'decoders': ['h264'],
          'hdrOutput': true,
          'hdrFormats': ['hdr10'],
          'displayModeSwitching': false,
          'audioPassthrough': false,
          'passthroughFormats': <String>[],
          'diagnostics': {'probe': 'api'},
        };
      }
      return {};
    });
    final service = PlatformCapabilitiesService(channel: channel);
    final first = await service.probe();
    expect(identical(first, await service.probe()), isTrue);
    expect(probes, 1);
    service.invalidate();
    await service.probe();
    expect(probes, 2);
  });

  test('audio route events invalidate the capability cache', () async {
    var probes = 0;
    final channel = FakeChannel((method, _) {
      if (method == PlatformMethods.probe) {
        probes++;
        return {
          'hardwareDecode': false,
          'decoders': <String>[],
          'hdrOutput': false,
          'hdrFormats': <String>[],
          'displayModeSwitching': false,
          'audioPassthrough': false,
          'passthroughFormats': <String>[],
        };
      }
      return {};
    });
    final service = PlatformCapabilitiesService(channel: channel);
    await service.probe();
    channel.emit({'event': 'audioRouteChanged'});
    await Future<void>.delayed(Duration.zero);
    await service.probe();
    expect(probes, 2);
    await service.dispose();
  });

  test(
    'mode matching preserves fractional rates and avoids a no-op switch',
    () {
      final modes = [
        const DisplayMode(
          width: 1920,
          height: 1080,
          refreshHz: 23.976,
          isCurrent: false,
        ),
        const DisplayMode(
          width: 1920,
          height: 1080,
          refreshHz: 24,
          isCurrent: true,
        ),
      ];
      final result = ModeMatcher.match(
        contentFps: 23.976,
        modes: modes,
        current: modes[1],
      );
      expect(result, isNotNull);
      expect(result!.mode.refreshHz, 23.976);
      expect(
        ModeMatcher.match(contentFps: 24, modes: modes, current: modes[1]),
        isNull,
      );
    },
  );

  test('rejected display restoration stays retryable and surfaces failure', () async {
    var attempts = 0;
    final channel = FakeChannel((method, _) => {
      'supported': ++attempts > 1,
      'reason': 'requested mode was not observed before timeout',
    });
    final lease = DisplayModeLeaseImpl(
      channel: channel,
      previous: const DisplayMode(width: 1920, height: 1080, refreshHz: 60, isCurrent: true),
      restoreArguments: {'width': 1920},
    );
    await expectLater(lease.release(), throwsA(isA<PlatformFailure>()));
    expect(lease.isReleased, isFalse);
    await lease.release();
    expect(lease.isReleased, isTrue);
    expect(attempts, 2);
  });

  test('display lease restores exactly once', () async {
    final channel = FakeChannel((method, _) => {});
    final lease = DisplayModeLeaseImpl(
      channel: channel,
      previous: const DisplayMode(
        width: 1920,
        height: 1080,
        refreshHz: 60,
        isCurrent: true,
      ),
      restoreArguments: {'width': 1920},
    );
    await lease.release();
    await lease.release();
    expect(
      channel.calls.where((call) => call == PlatformMethods.displayRestore),
      hasLength(1),
    );
  });

  test('display apply failure restores the previous mode', () async {
    final channel = FakeChannel((method, _) {
      if (method == PlatformMethods.displayModes) {
        return {
          'supported': true,
          'modes': [
            {'width': 1920, 'height': 1080, 'refreshHz': 60, 'isCurrent': true},
            {
              'width': 1920,
              'height': 1080,
              'refreshHz': 24,
              'isCurrent': false,
            },
          ],
        };
      }
      if (method == PlatformMethods.displayApply) {
        throw StateError('simulated apply failure');
      }
      return {};
    });
    final service = DisplayModeServiceImpl(channel: channel);
    await expectLater(
      service.matchFor(contentFps: 24),
      throwsA(isA<PlatformFailure>()),
    );
    expect(channel.calls, contains(PlatformMethods.displayRestore));
  });

  test('display teardown restores an active lease', () async {
    final channel = FakeChannel((method, _) {
      if (method == PlatformMethods.displayModes) {
        return {
          'supported': true,
          'modes': [
            {'width': 1920, 'height': 1080, 'refreshHz': 60, 'isCurrent': true},
            {
              'width': 1920,
              'height': 1080,
              'refreshHz': 24,
              'isCurrent': false,
            },
          ],
        };
      }
      return {};
    });
    final service = DisplayModeServiceImpl(channel: channel);
    await service.matchFor(contentFps: 24);
    await service.restoreAll();
    expect(channel.calls, contains(PlatformMethods.displayRestore));
  });

  test('all registered platform failure codes map to typed failures', () {
    const codes = {
      'platform.unsupported',
      'platform.permission_denied',
      'platform.display.switch_failed',
      'platform.audio.device_lost',
      'platform.probe.failed',
    };
    for (final code in codes) {
      expect(mapPlatformError(PlatformException(code: code)).code, code);
    }
  });

  test('diagnostics redact URL credentials and paths', () {
    final collector = DiagnosticsCollector(os: 'test', appVersion: '0.0.1');
    collector.collect(
      playback: {
        'url': 'https://user:secret@example.test/video.mkv?token=secret',
        'path': '/Users/name/private/video.mkv',
      },
    );
    final text = collector.toReportText();
    expect(text, isNot(contains('secret')));
    expect(text, contains('video.mkv'));
  });

  test(
    'keep-awake lease releases once and teardown releases active leases',
    () async {
      final channel = FakeChannel((method, _) => {});
      final service = PlaybackLifecycleService(channel: channel);
      final lease = await service.acquireKeepAwake();
      await lease.release();
      await lease.release();
      expect(
        channel.calls.where(
          (call) => call == PlatformMethods.lifecycleKeepAwake,
        ),
        hasLength(1),
      );
      expect(
        channel.calls.where(
          (call) => call == PlatformMethods.lifecycleReleaseAwake,
        ),
        hasLength(1),
      );
      await service.dispose();
    },
  );

  test(
    'media session throttles updates and forwards remote commands',
    () async {
      var now = DateTime(2026, 1, 1);
      final channel = FakeChannel((method, _) => {});
      final service = MediaSessionService(channel: channel, now: () => now);
      const info = MediaSessionInfo(title: 'Test', playing: true);
      await service.updateNowPlaying(info);
      now = now.add(const Duration(milliseconds: 500));
      await service.updateNowPlaying(info);
      expect(
        channel.calls.where(
          (call) => call == PlatformMethods.mediaSessionUpdate,
        ),
        hasLength(1),
      );
      now = now.add(const Duration(milliseconds: 501));
      await service.updateNowPlaying(info);
      expect(
        channel.calls.where(
          (call) => call == PlatformMethods.mediaSessionUpdate,
        ),
        hasLength(2),
      );

      final command = service.commands.first;
      channel.emit({
        'event': 'mediaCommand',
        'command': 'seekTo',
        'positionSeconds': 2.5,
      });
      final received = await command;
      expect(received.type, MediaSessionCommandType.seekTo);
      expect(received.position, const Duration(milliseconds: 2500));
      await service.dispose();
      expect(
        channel.calls.where(
          (call) => call == PlatformMethods.mediaSessionClear,
        ),
        hasLength(1),
      );
    },
  );

  test('media session drops updates after dispose', () async {
    final channel = FakeChannel((method, _) => {});
    final service = MediaSessionService(channel: channel);
    await service.dispose();
    await service.updateNowPlaying(const MediaSessionInfo(title: 'ignored'));
    expect(
      channel.calls.where((call) => call == PlatformMethods.mediaSessionUpdate),
      isEmpty,
    );
  });
}
