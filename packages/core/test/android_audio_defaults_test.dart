import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Kodi 32 kHz sink rate can be saved without changing user choices',
    () async {
      final values = SettingsValues(MemorySettingsStore());
      addTearDown(values.dispose);
      final rate = settingById('audio.sampleRate');
      await values.write(rate, '32000');
      expect(values.read<String>(rate), '32000');
      await values.write(settingById('audio.speakerLayout'), '7.1');
      expect(values.read<String>(settingById('audio.speakerLayout')), '7.1');
    },
  );
  test(
    'Android audio defaults match Kodi without changing other OS defaults',
    () {
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
          defaultSettingValue(entry.key, 'Auto', os: 'android'),
          entry.value,
        );
        expect(defaultSettingValue(entry.key, 'Auto', os: 'macos'), 'Auto');
      }
      expect(
        defaultSettingValue('audio.outputMode', 'Optimized', os: 'android'),
        'Optimized',
      );
    },
  );
  test('iOS audio defaults match Kodi iOS 1.2/1.4/1.5 (2.0, 48000, no passthrough)', () {
    const expected = {
      'audio.speakerLayout': 'Stereo',
      'audio.passthrough': 'Disabled',
      'audio.ac3Transcode': 'Disabled',
      'audio.sampleRate': '48000',
    };
    for (final entry in expected.entries) {
      expect(defaultSettingValue(entry.key, 'Auto', os: 'ios'), entry.value);
    }
    expect(
      defaultSettingValue('audio.outputMode', 'Optimized', os: 'ios'),
      'Optimized',
    );
  });
}
