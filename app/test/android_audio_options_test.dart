import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/player_settings.dart';

void main() {
  late SettingsValues values;
  setUp(() {
    values = SettingsValues(MemorySettingsStore());
  });
  tearDown(() => values.dispose());

  test('Android audio policy restricts formats to the sink with eight PCM channels', () {
    final android = audioPlanOverridesFor(values, os: 'android');
    expect(android.restrictToSinkFormats, isTrue);
    expect(android.pcmChannelLimit, 8);
    for (final os in ['macos']) {
      final other = audioPlanOverridesFor(values, os: os);
      expect(other.restrictToSinkFormats, isFalse);
      expect(other.pcmChannelLimit, isNull);
    }
  });

  test('AudioTrack uses stereo float and multichannel signed 16-bit PCM', () {
    for (final channels in [2, 6, 8]) {
      final options = audioEngineOptionsFor(
        values,
        os: 'android',
        info: MediaInfo(audioChannels: channels),
      );
      expect(options['ao'], 'audiotrack');
      expect(options['audio-format'], channels == 2 ? 'float' : 's16');
      expect(options['audio-device'], 'auto');
    }
  });

  test('Fixed Android sample rate passes the selected rate to mpv', () async {
    await values.write(settingById('audio.outputMode'), 'Fixed');
    await values.write(settingById('audio.sampleRate'), '96000');
    expect(
      audioEngineOptionsFor(values, os: 'android')['audio-samplerate'],
      '96000',
    );
    await values.write(settingById('audio.outputMode'), 'Optimized');
    expect(
      audioEngineOptionsFor(values, os: 'android')['audio-samplerate'],
      '0',
    );
  });

  test(
    'Android resampling quality uses the full swresample filter size',
    () async {
      for (final (quality, size, cutoff) in [
        ('Fast', 32, 0.97),
        ('Balanced', 64, 0.985),
        ('High', 256, 1.0),
      ]) {
        await values.write(settingById('audio.resamplingQuality'), quality);
        expect(
          audioEngineOptionsFor(values, os: 'android')['audio-swresample-o'],
          'filter_size=$size,cutoff=$cutoff',
        );
      }
    },
  );

  test('Android AO options preserve the existing non-Android option map', () {
    final macos = audioEngineOptionsFor(values, os: 'macos');
    for (final os in ['ios']) {
      expect(audioEngineOptionsFor(values, os: os), macos);
    }
    expect(macos, isNot(contains('ao')));
    expect(macos, isNot(contains('audio-format')));
    expect(macos['audio-swresample-o'], isEmpty);
    final android = audioEngineOptionsFor(values, os: 'android');
    expect(
      {
        for (final entry in android.entries)
          if (entry.key != 'ao' &&
              entry.key != 'audio-format' &&
              entry.key != 'audio-swresample-o')
            entry.key: entry.value,
      },
      {
        for (final entry in macos.entries)
          if (entry.key != 'audio-swresample-o') entry.key: entry.value,
      },
    );
  });

  test('iOS plan limits PCM to the AVAudioSession maximum channels', () {
    final six = audioPlanOverridesFor(values, os: 'ios', maxChannels: 6);
    expect(six.pcmChannelLimit, 6);
    expect(six.restrictToSinkFormats, isFalse);
    // Kodi iOS hard-codes a stereo sink until the session says otherwise.
    expect(audioPlanOverridesFor(values, os: 'ios').pcmChannelLimit, 2);
    expect(
      audioPlanOverridesFor(
        values,
        os: 'macos',
        maxChannels: 6,
      ).pcmChannelLimit,
      isNull,
    );
  });
}
