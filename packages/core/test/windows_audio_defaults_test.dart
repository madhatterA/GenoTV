import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // windows_reference.md 1.2/1.4/1.5: 2.0 layout, 48000 Hz, passthrough off,
  // every receiver tick box on, no AC3 transcode.
  test('Windows audio defaults match Kodi Windows', () {
    const expected = {
      'audio.speakerLayout': 'Stereo',
      'audio.passthrough': 'Disabled',
      'audio.receiver.dolbyDigital': 'Enabled',
      'audio.receiver.ddPlus': 'Enabled',
      'audio.receiver.dts': 'Enabled',
      'audio.receiver.dtsHd': 'Enabled',
      'audio.receiver.trueHd': 'Enabled',
      'audio.ac3Transcode': 'Disabled',
      'audio.sampleRate': '48000',
    };
    for (final entry in expected.entries) {
      expect(
        defaultSettingValue(entry.key, 'Auto', os: 'windows'),
        entry.value,
      );
    }
    expect(
      defaultSettingValue('audio.outputMode', 'Optimized', os: 'windows'),
      'Optimized',
    );
  });
}
