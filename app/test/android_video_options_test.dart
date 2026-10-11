import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/player_settings.dart';

void main() {
  late SettingsValues values;
  setUp(() {
    values = SettingsValues(MemorySettingsStore());
  });
  tearDown(() => values.dispose());

  // media_kit starts every Android emulator with hwdec=no, Kodi's default is
  // MediaCodec on (android_reference 2.1): Android always writes hwdec.
  test('Android always applies the hardware decoding default at open', () {
    final android = changedEngineSettings(values, os: 'android');
    expect(
      android,
      containsAll({
        settingById('video.hwdec'),
        settingById('video.pixelFormat'),
        settingById('video.toneMapping'),
      }),
    );
    expect(
      engineOptionsFor(values, scope: android, os: 'android'),
      containsPair('hwdec', 'mediacodec'),
    );
    final options = engineOptionsFor(values, scope: android, os: 'android');
    expect(options['vd-lavc-software-fallback'], 'yes');
    expect(options['vf'], '');
    expect(options['tone-mapping'], 'auto');
    expect(changedEngineSettings(values, os: 'macos'), {
      settingById('playback.networkTimeout'),
    });
  });

  test(
    'Android CPU filters select hardware copy at open and on live edits',
    () async {
      await values.write(settingById('video.pixelFormat'), 'nv12');
      final open = engineOptionsFor(
        values,
        scope: changedEngineSettings(values, os: 'android'),
        os: 'android',
      );
      expect(open['hwdec'], 'mediacodec-copy');
      expect(open['vf'], 'format=nv12');
      final live = engineOptionsFor(
        values,
        scope: {settingById('video.pixelFormat')},
        os: 'android',
      );
      expect(live['hwdec'], 'mediacodec-copy');
      expect(live['vf'], 'format=nv12');
      expect(
        live.keys.toList().indexOf('hwdec'),
        lessThan(live.keys.toList().indexOf('vf')),
      );

      await values.reset(settingById('video.pixelFormat'));
      final reset = engineOptionsFor(
        values,
        scope: {settingById('video.pixelFormat')},
        os: 'android',
      );
      expect(reset['hwdec'], 'mediacodec');
      expect(reset['vf'], '');
      expect(
        reset.keys.toList().indexOf('vf'),
        lessThan(reset.keys.toList().indexOf('hwdec')),
      );
      await values.write(settingById('video.chroma'), '4:4:4');
      final chroma = engineOptionsFor(
        values,
        scope: {settingById('video.chroma')},
        os: 'android',
      );
      expect(chroma['hwdec'], 'mediacodec-copy');
      expect(chroma['vf'], 'format=yuv444p');
      await values.write(settingById('video.decoder'), 'software');
      expect(
        engineOptionsFor(
          values,
          scope: {settingById('video.chroma')},
          os: 'android',
        )['hwdec'],
        'no',
      );
      expect(
        engineOptionsFor(
          values,
          scope: {settingById('video.chroma')},
          os: 'macos',
        ),
        {'vf': 'format=yuv444p'},
      );
    },
  );

  test('Android hardware decoding choices still map to mpv', () async {
    await values.write(settingById('video.hwdec'), 'Off');
    expect(
      engineOptionsFor(
        values,
        scope: changedEngineSettings(values, os: 'android'),
        os: 'android',
      ),
      containsPair('hwdec', 'no'),
    );
    await values.write(settingById('video.hwdec'), 'Auto');
    await values.write(settingById('video.decoder'), 'software');
    expect(
      engineOptionsFor(
        values,
        scope: changedEngineSettings(values, os: 'android'),
        os: 'android',
      )['hwdec'],
      'no',
    );
  });
}
