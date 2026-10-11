import 'package:cast/src/transform/audio_capability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('absent audio advertising is unknown and preserves every codec', () {
    for (final sink in <List<String>>[
      [],
      ['http-get:*:video/mp4:*'],
      ['http-get:*:audio/mp4:*', 'http-get:*:audio/ogg:*'],
      ['http-get:*:video/mp4:DLNA.ORG_PN=FAKE_AAC_PROFILE'],
      ['http-get:*:video/mp4:DLNA.ORG_PN=NOTAC3'],
      ['malformed audio/ac3'],
    ]) {
      final capability = AudioCapability.dlna(sink);
      expect(capability.support, AudioSupport.unknown);
      expect(capability.codecs, isEmpty);
      expect(capability.supports('truehd'), isTrue);
    }
  });

  test('codec audio MIMEs form a known union', () {
    final capability = AudioCapability.dlna([
      'http-get:*:audio/aac:*',
      'http-get:*:audio/ac3:*',
      'http-get:*: AUDIO/EAC3 ; rate=48000 :*',
      'http-get:*:audio/flac:*',
      'http-get:*:audio/opus:*',
      'http-get:*:audio/vorbis:*',
    ]);
    expect(capability.support, AudioSupport.known);
    expect(capability.codecs, {'aac', 'ac3', 'eac3', 'flac', 'opus', 'vorbis'});
    expect(capability.supports('AAC'), isTrue);
    expect(capability.supports('truehd'), isFalse);
  });

  test('audio/mpeg without a profile advertises MPEG audio layers', () {
    final capability = AudioCapability.dlna(['http-get:*:audio/mpeg:*']);
    expect(capability.codecs, {'mp1', 'mp2', 'mp3'});
  });

  test('recognized profiles narrow container MIME and MPEG audio', () {
    expect(
      AudioCapability.dlna([
        'http-get:*:audio/mpeg:DLNA.ORG_PN=MP3;DLNA.ORG_OP=01',
      ]).codecs,
      {'mp3'},
    );
    expect(
      AudioCapability.dlna([
        'http-get:*:audio/mp4:DLNA.ORG_PN=AAC_ISO_320',
        'http-get:*:video/mp4:DLNA.ORG_PN=AVC_MP4_MP_SD_AC3',
        'http-get:*:video/mp4:DLNA.ORG_PN=AVC_MP4_HP_HD_EAC3',
      ]).codecs,
      {'aac', 'ac3', 'eac3'},
    );
  });

  test(
    'unknown profiles cannot invent audio but explicit MIME remains known',
    () {
      final capability = AudioCapability.dlna([
        'http-get:*:video/mp4:DLNA.ORG_PN=FAKE_AAC_PROFILE',
        'http-get:*:audio/ac3:DLNA.ORG_PN=VENDOR_UNKNOWN',
      ]);
      expect(capability.codecs, {'ac3'});
      expect(capability.supports('aac'), isFalse);
    },
  );

  test('L16 and LPCM advertise only their 16-bit big-endian PCM codec', () {
    for (final entry in [
      'http-get:*:audio/L16;rate=48000;channels=2:*',
      'http-get:*:audio/L16:DLNA.ORG_PN=LPCM',
    ]) {
      final capability = AudioCapability.dlna([entry]);
      expect(capability.codecs, {'pcm_s16be'});
      expect(capability.supports('pcm_s24le'), isFalse);
    }
  });

  test('known codec list is an immutable snapshot including known-empty', () {
    final original = {'aac'};
    final capability = AudioCapability.known(original);
    original.add('ac3');
    expect(capability.codecs, {'aac'});
    expect(() => capability.codecs.add('ac3'), throwsUnsupportedError);
    expect(AudioCapability.known({}).supports('aac'), isFalse);
    expect(const AudioCapability.unknown().supports('dts'), isTrue);
  });
}
