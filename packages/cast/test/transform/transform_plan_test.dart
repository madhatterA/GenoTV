import 'package:cast/dart_cast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const streams = [
    RemuxStream(index: 0, type: 'video', codec: 'h264'),
    RemuxStream(index: 1, type: 'audio', codec: 'ac3'),
    RemuxStream(index: 2, type: 'audio', codec: 'aac'),
  ];
  test('unknown DLNA audio preserves every track and surfaces unknown', () {
    final plan = planCastTransform(
      compatibility: CastCompatibility.direct,
      inputType: CastMediaType.mkv,
      streams: streams,
      audioCapability: const AudioCapability.unknown(),
    );
    expect(plan.direct, isTrue);
    expect(plan.keepStreams, [0, 1, 2]);
    expect(plan.droppedAudioStreams, isEmpty);
    expect(plan.audioSupport, AudioSupport.unknown);
  });
  test(
    'known audio list drops only unsupported audio; direct becomes remux',
    () {
      final plan = planCastTransform(
        compatibility: CastCompatibility.direct,
        inputType: CastMediaType.mkv,
        streams: streams,
        audioCapability: AudioCapability.known({'aac'}),
      );
      expect(plan.direct, isFalse);
      expect(plan.outputType, CastMediaType.mkv);
      expect(plan.keepStreams, [0, 2]);
      expect(plan.droppedAudioStreams, [1]);
    },
  );
  test(
    'fragmented MP4/HLS jobs retain playable streams; MKV embeds subtitles',
    () {
      for (final (compatibility, output) in [
        (CastCompatibility.remuxToMp4, CastMediaType.mp4),
        (CastCompatibility.remuxToHls, CastMediaType.hls),
      ]) {
        final plan = planCastTransform(
          compatibility: compatibility,
          inputType: CastMediaType.mkv,
          streams: streams,
          audioCapability: AudioCapability.known({'aac'}),
        );
        expect(plan.outputType, output);
        expect(plan.direct, isFalse);
        expect(plan.keepStreams, [0, 2]);
      }
      final embedded = planCastTransform(
        compatibility: CastCompatibility.direct,
        inputType: CastMediaType.mkv,
        streams: streams,
        audioCapability: const AudioCapability.unknown(),
        embedSubtitles: true,
      );
      expect(embedded.outputType, CastMediaType.mkv);
      expect(embedded.direct, isFalse);
    },
  );
  test(
    'incompatible or all audio unsupported gives typed pick-another-quality',
    () {
      for (final compatibility in [
        CastCompatibility.notCompatible,
        CastCompatibility.remuxToMp4,
      ]) {
        expect(
          () => planCastTransform(
            compatibility: compatibility,
            inputType: CastMediaType.mkv,
            streams: streams,
            audioCapability: AudioCapability.known({'flac'}),
          ),
          throwsA(
            isA<CastTransformFailure>().having(
              (failure) => failure.message,
              'message',
              'Not compatible — pick another quality',
            ),
          ),
        );
      }
    },
  );

  test(
    'attached artwork is not movie video and cannot create a video-only plan',
    () {
      const cover = RemuxStream(
        index: 3,
        type: 'video',
        codec: 'mjpeg',
        attachedPicture: true,
      );
      final plan = planCastTransform(
        compatibility: CastCompatibility.remuxToMp4,
        inputType: CastMediaType.mkv,
        streams: [...streams, cover],
        audioCapability: AudioCapability.known({'aac'}),
      );
      expect(plan.keepStreams, [0, 2]);
      expect(
        () => planCastTransform(
          compatibility: CastCompatibility.remuxToMp4,
          inputType: CastMediaType.mkv,
          streams: [cover],
          audioCapability: const AudioCapability.unknown(),
        ),
        throwsA(isA<CastTransformFailure>()),
      );
    },
  );
}
