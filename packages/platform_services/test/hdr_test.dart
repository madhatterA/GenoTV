import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';

final class _HdrChannel implements PlatformChannel {
  _HdrChannel(this.payload);

  final Object? payload;

  @override
  Future<Object?> invoke(String method, [Object? arguments]) async => payload;

  @override
  Stream<Object?> get events => const Stream<Object?>.empty();

  @override
  Future<void> dispose() async {}
}

void main() {
  test('no HDR types reports SDR with a fallback reason', () async {
    final output = await HdrOutputService(
      _HdrChannel({'hdrOutput': false, 'hdrFormats': <String>[]}),
    ).probe();
    expect(output.available, isFalse);
    expect(output.formats, isEmpty);
    expect(output.fallbackReason, contains('no HDR formats'));
  });

  test('HDR10 is reported without inventing HDR10+ or Dolby Vision', () async {
    final output = await HdrOutputService(
      _HdrChannel({'hdrOutput': true, 'hdrFormats': ['hdr10']}),
    ).probe();
    expect(output.available, isTrue);
    expect(output.formats, ['hdr10']);
    expect(output.formats, isNot(contains('hdr10plus')));
    expect(output.formats, isNot(contains('dolbyvision')));
    expect(output.fallbackReason, isNull);
  });

  test('an SDR headroom result cannot claim HDR', () async {
    final output = await HdrOutputService(
      _HdrChannel({
        'hdrOutput': false,
        'hdrFormats': ['hdr10'],
        'edrHeadroom': 1.0,
      }),
    ).probe();
    expect(output.available, isFalse);
    expect(output.formats, isEmpty);
    expect(output.fallbackReason, contains('cannot accept HDR'));
  });

  test('OS HDR toggle off is surfaced explicitly', () async {
    final output = await HdrOutputService(
      _HdrChannel({
        'hdrOutput': true,
        'hdrFormats': ['hdr10'],
        'osHdrEnabled': false,
      }),
    ).probe();
    expect(output.available, isFalse);
    expect(output.formats, isEmpty);
    expect(output.fallbackReason, contains('OS HDR toggle'));
  });

  test('HDR availability requires a non-empty format list', () async {
    final output = await HdrOutputService(
      _HdrChannel({'hdrOutput': true, 'hdrFormats': <String>[]}),
    ).probe();
    expect(output.available, isFalse);
    expect(output.formats, isEmpty);
    expect(output.fallbackReason, isNotNull);
  });
}
