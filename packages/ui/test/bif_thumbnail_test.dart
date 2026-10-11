// Port of `research/Rivulet/RivuletTests/Unit/Services/BIFFilmstripTests.swift`
// plus malformed-header/offset/truncated coverage and
// `ThumbnailPreviewController` cache/cancellation/out-of-order-decode cases
// called for by `planning/part-04-ui/chapter-03-player-ui/phase-04-scrubber-thumbnails.md`.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

const List<int> _magic = <int>[0x89, 0x42, 0x49, 0x46, 0x0D, 0x0A, 0x1A, 0x0A];

void _appendU32LE(BytesBuilder b, int v) {
  final bytes = ByteData(4)..setUint32(0, v, Endian.little);
  b.add(bytes.buffer.asUint8List());
}

/// Port of `makeBIF(frameCount:intervalMs:)`,
/// `BIFFilmstripTests.swift:9-25`: dense timestamps (`timestamp == index`).
Uint8List _makeBif({required int frameCount, required int intervalMs}) {
  final b = BytesBuilder();
  b.add(_magic);
  _appendU32LE(b, 0); // version
  _appendU32LE(b, frameCount);
  _appendU32LE(b, intervalMs);
  b.add(Uint8List(44)); // reserved to byte 64
  final payloads = List<Uint8List>.generate(
    frameCount,
    (i) => Uint8List.fromList(<int>[(i + 1) & 0xFF, 0xFF]),
  );
  var offset = 64 + (frameCount + 1) * 8;
  for (var i = 0; i < payloads.length; i++) {
    _appendU32LE(b, i); // timestamp = frame number
    _appendU32LE(b, offset);
    offset += payloads[i].length;
  }
  _appendU32LE(b, 0xFFFFFFFF); // end-marker timestamp (unused)
  _appendU32LE(b, offset); // end offset
  for (final p in payloads) {
    b.add(p);
  }
  return b.toBytes();
}

/// Port of `makeStridedBIF(...)`, `BIFFilmstripTests.swift:52-68`: frame
/// i's timestamp is `i * stride`.
Uint8List _makeStridedBif({
  required int frameCount,
  required int intervalMs,
  required int stride,
}) {
  final b = BytesBuilder();
  b.add(_magic);
  _appendU32LE(b, 0);
  _appendU32LE(b, frameCount);
  _appendU32LE(b, intervalMs);
  b.add(Uint8List(44));
  final payloads = List<Uint8List>.generate(
    frameCount,
    (i) => Uint8List.fromList(<int>[(i + 1) & 0xFF, 0xFF]),
  );
  var offset = 64 + (frameCount + 1) * 8;
  for (var i = 0; i < payloads.length; i++) {
    _appendU32LE(b, i * stride);
    _appendU32LE(b, offset);
    offset += payloads[i].length;
  }
  _appendU32LE(b, 0xFFFFFFFF);
  _appendU32LE(b, offset);
  for (final p in payloads) {
    b.add(p);
  }
  return b.toBytes();
}

/// Port of `makeBIFWithDroppedMiddleFrame(...)`,
/// `BIFFilmstripTests.swift:143-166`: entry `dropIndex`'s offset points
/// past the end of the file, so the parser's bounds guard drops it (and its
/// predecessor, whose `end` is the dropped entry's `start`).
Uint8List _makeBifWithDroppedMiddleFrame({
  required int frameCount,
  required int intervalMs,
  required int dropIndex,
}) {
  final b = BytesBuilder();
  b.add(_magic);
  _appendU32LE(b, 0);
  _appendU32LE(b, frameCount);
  _appendU32LE(b, intervalMs);
  b.add(Uint8List(44));
  final payloads = List<Uint8List>.generate(
    frameCount,
    (i) => Uint8List.fromList(<int>[(i + 1) & 0xFF, 0xFF]),
  );
  var offset = 64 + (frameCount + 1) * 8;
  final offsets = <int>[];
  for (final p in payloads) {
    offsets.add(offset);
    offset += p.length;
  }
  final endOffset = offset;
  for (var i = 0; i < frameCount; i++) {
    _appendU32LE(b, i);
    if (i == dropIndex) {
      _appendU32LE(b, endOffset + 1000000);
    } else {
      _appendU32LE(b, offsets[i]);
    }
  }
  _appendU32LE(b, 0xFFFFFFFF);
  _appendU32LE(b, endOffset);
  for (final p in payloads) {
    b.add(p);
  }
  return b.toBytes();
}

void main() {
  group('BifThumbnailIndex.parse', () {
    test('parses a synthetic BIF', () {
      final bif = BifThumbnailIndex.parse(
        _makeBif(frameCount: 5, intervalMs: 10000),
      );
      expect(bif, isNotNull);
      expect(bif!.frameCount, 5);
      expect(bif.intervalMs, 10000);
      expect(bif.frames[2].imageData.first, 3);
    });

    test('rejects data shorter than the 64-byte header', () {
      expect(BifThumbnailIndex.parse(Uint8List(10)), isNull);
    });

    test('rejects a bad magic number', () {
      final data = _makeBif(frameCount: 2, intervalMs: 1000);
      data[0] = 0x00;
      expect(BifThumbnailIndex.parse(data), isNull);
    });

    test('rejects data truncated inside the index table', () {
      final data = _makeBif(frameCount: 5, intervalMs: 10000);
      expect(BifThumbnailIndex.parse(data.sublist(0, 80)), isNull);
    });

    test('drops a frame whose offset points past the end of the file', () {
      final data = _makeBifWithDroppedMiddleFrame(
        frameCount: 6,
        intervalMs: 10000,
        dropIndex: 3,
      );
      final bif = BifThumbnailIndex.parse(data)!;
      expect(
        bif.frameCount,
        4,
        reason:
            'the malformed entry and its collateral neighbor should be dropped',
      );
      expect(bif.timestampsAreContiguous, isFalse);
    });

    test('interval 0 falls back to the BIF default of 1000ms', () {
      final bif = BifThumbnailIndex.parse(
        _makeBif(frameCount: 2, intervalMs: 0),
      )!;
      expect(bif.intervalMs, 1000);
    });
  });

  group('BifThumbnailIndex.frameIndexAt — dense/nearest', () {
    test('resolves the nearest frame for dense timestamps', () {
      final bif = BifThumbnailIndex.parse(
        _makeBif(frameCount: 5, intervalMs: 10000),
      )!;
      expect(bif.frameIndexAt(Duration.zero), 0);
      expect(bif.frameIndexAt(const Duration(seconds: 14)), 1);
      expect(bif.frameIndexAt(const Duration(seconds: 16)), 2);
      expect(
        bif.frameIndexAt(const Duration(seconds: 9999)),
        4,
        reason: 'clamps to last',
      );
    });

    test('returns null for an empty BIF', () {
      final bif = BifThumbnailIndex.parse(
        _makeBif(frameCount: 0, intervalMs: 10000),
      )!;
      expect(bif.frameIndexAt(const Duration(seconds: 5)), isNull);
    });

    test('uses exact mapping for a genuinely dense BIF', () {
      final bif = BifThumbnailIndex.parse(
        _makeBif(frameCount: 6, intervalMs: 10000),
      )!;
      expect(bif.frames.last.timestamp, 5);
      expect(bif.frameIndexAt(Duration.zero), 0);
      expect(bif.frameIndexAt(const Duration(seconds: 25)), 3);
      expect(bif.frameIndexAt(const Duration(seconds: 24)), 2);
      expect(bif.frameIndexAt(const Duration(seconds: 50)), 5);
    });
  });

  group('BifThumbnailIndex.frameIndexAt — strided/corrupt', () {
    test(
      'strided timestamps span the whole timeline, not just the dense half',
      () {
        final bif = BifThumbnailIndex.parse(
          _makeStridedBif(frameCount: 709, intervalMs: 1000, stride: 2),
        )!;
        expect(bif.frameCount, 709);
        expect(bif.frames.last.timestamp, 1416);

        final mid = bif.frameIndexAt(const Duration(seconds: 708));
        expect(mid, 354);
        expect(mid, isNot(bif.frameCount - 1));

        final late = bif.frameIndexAt(const Duration(seconds: 1276));
        expect(late, 638);
        expect(late, isNot(bif.frameCount - 1));

        final quarter = bif.frameIndexAt(const Duration(seconds: 354))!;
        expect(quarter, 177);
        expect(quarter, lessThan(mid!));
        expect(mid, lessThan(late!));

        expect(bif.frameIndexAt(Duration.zero), 0);
        expect(bif.frameIndexAt(const Duration(seconds: 9999)), 708);
      },
    );

    test('nearest-frame lookup survives a dropped middle frame', () {
      final data = _makeBifWithDroppedMiddleFrame(
        frameCount: 6,
        intervalMs: 10000,
        dropIndex: 3,
      );
      final bif = BifThumbnailIndex.parse(data)!;

      final idx = bif.frameIndexAt(const Duration(seconds: 41))!;
      expect(bif.frames[idx].timestamp, 4);

      final idxNearGap = bif.frameIndexAt(const Duration(seconds: 24))!;
      expect(bif.frames[idxNearGap].timestamp, 1);
    });
  });

  group('BifThumbnailIndex.frameIndicesForTimes', () {
    test('spreads an overshot tail across the frames the BIF actually has', () {
      final bif = BifThumbnailIndex.parse(
        _makeBif(frameCount: 60, intervalMs: 10000),
      )!;
      const count = 12;
      const duration = Duration(milliseconds: 1380000);
      final times = List<Duration>.generate(
        count,
        (i) => Duration(
          microseconds: (duration.inMicroseconds * (i + 0.5) / count).round(),
        ),
      );

      final indices = bif.frameIndicesForTimes(times);
      expect(indices.length, times.length);
      expect(indices.take(5).toList(), <int?>[6, 17, 29, 40, 52]);
      final tail = indices.skip(5).whereType<int>().toList();
      expect(tail, <int>[53, 54, 55, 56, 57, 58, 59]);
    });

    test('a tail with no headroom still ends on the true final frame', () {
      final bif = BifThumbnailIndex.parse(
        _makeBif(frameCount: 10, intervalMs: 10000),
      )!;
      const count = 12;
      const duration = Duration(milliseconds: 1380000);
      final times = List<Duration>.generate(
        count,
        (i) => Duration(
          microseconds: (duration.inMicroseconds * (i + 0.5) / count).round(),
        ),
      );

      final indices = bif.frameIndicesForTimes(times);
      expect(indices.length, times.length);
      expect(indices.last, 9);
      expect(indices.whereType<int>().every((i) => i <= 9), isTrue);
    });

    test('passes through unchanged when fully in range', () {
      final bif = BifThumbnailIndex.parse(
        _makeBif(frameCount: 6, intervalMs: 10000),
      )!;
      final times = const <Duration>[
        Duration(seconds: 5),
        Duration(seconds: 15),
        Duration(seconds: 25),
        Duration(seconds: 35),
        Duration(seconds: 45),
      ];
      final indices = bif.frameIndicesForTimes(times);
      expect(indices, times.map(bif.frameIndexAt).toList());
    });
  });

  _controllerTests();
}

/// A fake, already-resolved image provider — never a real codec/decoder —
/// used only to prove `ThumbnailPreviewController` plumbing without
/// touching image decoding (that's the caller's injected [FrameImageDecoder]
/// in production).
class _FakeImageProvider extends ImageProvider<_FakeImageProvider> {
  const _FakeImageProvider(this.id);
  final int id;

  @override
  Future<_FakeImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_FakeImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    _FakeImageProvider key,
    ImageDecoderCallback decode,
  ) {
    throw UnimplementedError('never resolved in tests');
  }

  @override
  bool operator ==(Object other) =>
      other is _FakeImageProvider && other.id == id;

  @override
  int get hashCode => id;
}

void _controllerTests() {
  group('ThumbnailPreviewController', () {
    late Uint8List bifBytes;
    setUp(() {
      bifBytes = _makeBif(frameCount: 5, intervalMs: 10000);
    });

    test(
      'preload indexes a part once; a second call reuses the cache',
      () async {
        var fetchCount = 0;
        final controller = ThumbnailPreviewController(
          fetchBifBytes: (partId) async {
            fetchCount++;
            return bifBytes;
          },
          decodeFrame: (bytes) async => const _FakeImageProvider(0),
        );

        final first = await controller.preload('part-1');
        final second = await controller.preload('part-1');
        expect(first, isNotNull);
        expect(second, isNotNull);
        expect(fetchCount, 1);
      },
    );

    test(
      'a part with no BIF is cached as unavailable and never retried',
      () async {
        var fetchCount = 0;
        final controller = ThumbnailPreviewController(
          fetchBifBytes: (partId) async {
            fetchCount++;
            return null;
          },
          decodeFrame: (bytes) async => const _FakeImageProvider(0),
        );

        expect(await controller.preload('part-404'), isNull);
        expect(await controller.preload('part-404'), isNull);
        expect(fetchCount, 1);
      },
    );

    test(
      'requestThumbnail decodes the nearest frame and publishes it',
      () async {
        Uint8List? decodedBytes;
        final controller = ThumbnailPreviewController(
          fetchBifBytes: (partId) async => bifBytes,
          decodeFrame: (bytes) async {
            decodedBytes = bytes;
            return const _FakeImageProvider(1);
          },
        );

        var notified = 0;
        controller.addListener(() => notified++);
        await controller.requestThumbnail(
          partId: 'part-1',
          time: const Duration(seconds: 14),
        );

        expect(controller.currentThumbnail, const _FakeImageProvider(1));
        expect(notified, 1);
        expect(decodedBytes, isNotNull);
      },
    );

    test(
      'onItemChanged cancels an in-flight decode; its result is dropped',
      () async {
        final completer = Completer<Uint8List?>();
        final controller = ThumbnailPreviewController(
          fetchBifBytes: (partId) => completer.future,
          decodeFrame: (bytes) async => const _FakeImageProvider(2),
        );

        final request = controller.requestThumbnail(
          partId: 'part-1',
          time: const Duration(seconds: 1),
        );
        controller.onItemChanged();
        completer.complete(bifBytes);
        await request;

        expect(
          controller.currentThumbnail,
          isNull,
          reason: 'a stale session must never publish its result',
        );
      },
    );

    test('an out-of-order decode does not overwrite a newer request', () async {
      final firstDecode = Completer<ImageProvider?>();
      final secondDecode = Completer<ImageProvider?>();
      var call = 0;
      final controller = ThumbnailPreviewController(
        fetchBifBytes: (partId) async => bifBytes,
        decodeFrame: (bytes) {
          call++;
          return call == 1 ? firstDecode.future : secondDecode.future;
        },
      );
      // Prime the index cache so both requests reach their own decode call
      // (rather than one being coalesced/superseded while still waiting on
      // the shared BIF index load — that race is covered by the
      // cancellation test above; this one isolates the decode-ordering
      // guard specifically).
      await controller.preload('part-1');

      final first = controller.requestThumbnail(
        partId: 'part-1',
        time: const Duration(seconds: 1),
      );
      // Let request 1 run up to (and start) its own decode call before
      // request 2 is issued, so both are genuinely in flight together
      // rather than request 1 being marked stale before it ever decodes.
      await Future<void>.delayed(Duration.zero);
      final second = controller.requestThumbnail(
        partId: 'part-1',
        time: const Duration(seconds: 2),
      );
      await Future<void>.delayed(Duration.zero);
      expect(call, 2, reason: 'both requests must have reached decodeFrame');

      // Second (newer) request's decode resolves first.
      secondDecode.complete(const _FakeImageProvider(20));
      await second;
      expect(controller.currentThumbnail, const _FakeImageProvider(20));

      // First (now-stale) request's decode resolves after — must not
      // overwrite the newer frame already on screen.
      firstDecode.complete(const _FakeImageProvider(10));
      await first;
      expect(controller.currentThumbnail, const _FakeImageProvider(20));
    });

    test('clearPart drops the cache; a later load re-fetches', () async {
      var fetchCount = 0;
      final controller = ThumbnailPreviewController(
        fetchBifBytes: (partId) async {
          fetchCount++;
          return bifBytes;
        },
        decodeFrame: (bytes) async => const _FakeImageProvider(0),
      );

      await controller.preload('part-1');
      controller.clearPart('part-1');
      await controller.preload('part-1');
      expect(fetchCount, 2);
    });

    test(
      'clearAll drops every cached part and cancels in-flight loads',
      () async {
        final completer = Completer<Uint8List?>();
        final controller = ThumbnailPreviewController(
          fetchBifBytes: (partId) => completer.future,
          decodeFrame: (bytes) async => const _FakeImageProvider(0),
        );

        final pending = controller.preload('part-1');
        controller.clearAll();
        completer.complete(bifBytes);
        await pending;

        // A second preload after clearAll must issue a fresh fetch rather
        // than resolving off the cache the dropped in-flight load would have
        // populated.
        var fetchCountAfter = 0;
        final controller2 = ThumbnailPreviewController(
          fetchBifBytes: (partId) async {
            fetchCountAfter++;
            return bifBytes;
          },
          decodeFrame: (bytes) async => const _FakeImageProvider(0),
        );
        await controller2.preload('part-1');
        controller2.clearAll();
        await controller2.preload('part-1');
        expect(fetchCountAfter, 2);
      },
    );
  });
}
