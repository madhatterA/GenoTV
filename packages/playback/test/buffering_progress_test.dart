import 'package:flutter_test/flutter_test.dart';
import 'package:playback/src/controller/buffering_model.dart';

void main() {
  test('mpv cache-buffering-state percent maps to 0..1', () {
    expect(bufferingProgressFromMpv('42'), closeTo(0.42, 1e-9));
    expect(bufferingProgressFromMpv('100'), 1.0);
    expect(bufferingProgressFromMpv('150'), 1.0);
    expect(bufferingProgressFromMpv(''), isNull);
  });
}
