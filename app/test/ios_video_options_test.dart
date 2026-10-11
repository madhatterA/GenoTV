import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/player_settings.dart';

void main() {
  late SettingsValues values;
  setUp(() {
    values = SettingsValues(MemorySettingsStore());
  });
  tearDown(() => values.dispose());

  // Kodi iOS 2.1: VideoToolbox is on by default; software is the fallback.
  test('iOS applies VideoToolbox at open with software fallback', () {
    final scope = changedEngineSettings(values, os: 'ios');
    expect(scope, contains(settingById('video.hwdec')));
    final options = engineOptionsFor(values, scope: scope, os: 'ios');
    expect(options['hwdec'], 'videotoolbox');
    expect(options['vd-lavc-software-fallback'], 'yes');
    expect(options['vf'], '');
  });

  test('iOS CPU filters use VideoToolbox copy; Off and software are no', () async {
    await values.write(settingById('video.pixelFormat'), 'nv12');
    expect(
      engineOptionsFor(
        values,
        scope: {settingById('video.pixelFormat')},
        os: 'ios',
      )['hwdec'],
      'videotoolbox-copy',
    );
    await values.reset(settingById('video.pixelFormat'));
    await values.write(settingById('video.hwdec'), 'Off');
    expect(
      engineOptionsFor(
        values,
        scope: changedEngineSettings(values, os: 'ios'),
        os: 'ios',
      )['hwdec'],
      'no',
    );
    await values.write(settingById('video.hwdec'), 'Auto');
    await values.write(settingById('video.decoder'), 'software');
    expect(
      engineOptionsFor(
        values,
        scope: changedEngineSettings(values, os: 'ios'),
        os: 'ios',
      )['hwdec'],
      'no',
    );
  });
}
