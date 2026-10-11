import 'dart:io';

import 'package:cast/dart_cast.dart';
import 'package:flutter_test/flutter_test.dart';

CastDevice _device(CastProtocol protocol) => CastDevice(
  id: 'transform',
  name: 'Transform',
  protocol: protocol,
  address: InternetAddress.loopbackIPv4,
  port: 1,
  metadata: const {'md': 'Chromecast Ultra'},
);

void main() {
  test('Chromecast native input decodes file URI as a filesystem path', () {
    expect(
      DeviceMediaTransformer.localInputPath(
        const CastMedia(
          url: 'file:///tmp/cast%20input.mp4',
          type: CastMediaType.mp4,
        ),
      ),
      '/tmp/cast input.mp4',
    );
    expect(
      DeviceMediaTransformer.localInputPath(
        const CastMedia(
          url: 'https://example.com/video.mp4',
          type: CastMediaType.mp4,
        ),
      ),
      isNull,
    );
  });

  for (final defaultOnly in [false, true]) {
    test(
      'DLNA rejects requested subtitles without MKV, defaultOnly=$defaultOnly',
      () async {
        const subtitle = CastSubtitle(
          url: '/tmp/subtitle.srt',
          label: 'English',
          language: 'en',
          format: 'srt',
        );
        final transformer = DeviceMediaTransformer(
          device: _device(CastProtocol.dlna),
          dlnaSink: () async => ['http-get:*:video/mp4:*'],
        );
        await expectLater(
          transformer.transform(
            CastMedia(
              url: '/tmp/input.mkv',
              type: CastMediaType.mkv,
              subtitles: defaultOnly ? [] : [subtitle],
              defaultSubtitle: defaultOnly ? subtitle : null,
            ),
            MediaProxy(),
          ),
          throwsA(isA<CastTransformFailure>()),
        );
      },
    );
  }
}
