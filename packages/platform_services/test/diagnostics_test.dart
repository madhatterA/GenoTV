import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';

void main() {
  test('merges capability, display, audio and playback diagnostics', () {
    final collector = DiagnosticsCollector(os: 'Android 16', appVersion: '0.0.1');
    final capabilities = CapabilityReport(
      hardwareDecode: true,
      decoders: ['c2.goldfish.h264.decoder'],
      hdrOutput: false,
      hdrFormats: [],
      displayModeSwitching: false,
      audioPassthrough: false,
      passthroughFormats: [],
      diagnostics: {'backend': 'codec2'},
    );
    final snapshot = collector.collect(
      capabilities: capabilities,
      display: const {'display.current': '1080x2424@60.000004Hz'},
      audio: const {'audio.device': 'Android SDK built for arm64'},
      playback: const {'fallbackReason': 'passthrough unavailable'},
    );
    expect(snapshot.keys, containsAll(const {
      'backend',
      'display.current',
      'audio.device',
      'fallbackReason',
    }));
    expect(snapshot['backend'], 'codec2');
  });

  test('merged keys are namespaced or declared diagnostic keys', () {
    final collector = DiagnosticsCollector(os: 'test', appVersion: '0.0.1');
    final snapshot = collector.collect(
      capabilities: CapabilityReport(
        hardwareDecode: false,
        decoders: [],
        hdrOutput: false,
        hdrFormats: [],
        displayModeSwitching: false,
        audioPassthrough: false,
        passthroughFormats: [],
        diagnostics: {'apiLevel': '36'},
      ),
      display: const {'display.current': 'unknown'},
      audio: const {'audio.device': 'default'},
      playback: const {'playback.backend': 'mpv'},
    );
    expect(
      snapshot.keys.every(
        (key) => key.contains('.') || const {'apiLevel'}.contains(key),
      ),
      isTrue,
    );
  });

  test('redacts URL credentials/query and reduces paths to basenames', () {
    final collector = DiagnosticsCollector(os: 'test', appVersion: '0.0.1');
    collector.collect(
      playback: const {
        'url': 'https://user:secret@example.test/video.mkv?token=abc123',
        'path': '/Users/name/private/video.mkv',
      },
    );
    final text = collector.toReportText();
    expect(text, isNot(contains('user:secret')));
    expect(text, isNot(contains('token=abc123')));
    expect(text, contains('https://example.test/video.mkv'));
    expect(text, contains('video.mkv'));
  });

  test('report text includes OS/app header and merged values', () {
    final collector = DiagnosticsCollector(os: 'Android 16', appVersion: '0.0.1');
    collector.collect(display: const {'display.current': '1080x2424@60Hz'});
    final text = collector.toReportText();
    expect(text, contains('OS: Android 16'));
    expect(text, contains('App version: 0.0.1'));
    expect(text, contains('display.current: 1080x2424@60Hz'));
  });
}
