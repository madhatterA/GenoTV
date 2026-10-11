import 'dart:typed_data';

/// One decoded BIF (Base Index Frame) trickplay tile: a timestamp
/// *multiplier* (real time is `timestamp * intervalMs`) plus its raw JPEG
/// bytes, sliced directly out of the source file with no copy beyond the
/// slice itself.
///
/// Port of `BIFData.BIFFrame`,
/// `research/Rivulet/Rivulet/Services/Plex/PlexThumbnailService.swift:270-273`.
class BifFrame {
  const BifFrame({required this.timestamp, required this.imageData});

  final int timestamp;
  final Uint8List imageData;
}

/// Pure parser + nearest-frame index for a Plex BIF file. Holds no bytes or
/// image beyond the parsed frame slices, does no I/O and decodes no JPEG —
/// per the phase's "Part boundary and BIF service" decision, fetching bytes
/// and turning a frame's raw bytes into a paintable image are both injected
/// elsewhere ([ThumbnailPreviewController]).
///
/// Port of `BIFData`,
/// `research/Rivulet/Rivulet/Services/Plex/PlexThumbnailService.swift:258-416`.
class BifThumbnailIndex {
  const BifThumbnailIndex._({
    required this.intervalMs,
    required this.frames,
    required this.timestampsAreContiguous,
  });

  /// BIF magic: `0x89 'B' 'I' 'F' 0x0D 0x0A 0x1A 0x0A`.
  /// Source: `PlexThumbnailService.swift:277,289`.
  static const List<int> _magic = <int>[
    0x89,
    0x42,
    0x49,
    0x46,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ];

  static const int _headerSize = 64;
  static const int _indexEntrySize = 8;

  /// Timestamp multiplier → real seconds is `timestamp * intervalMs / 1000`.
  final int intervalMs;

  final List<BifFrame> frames;

  /// `false` if the parser dropped one or more malformed frame entries
  /// while extracting frame data, meaning `frames[i]` is no longer
  /// guaranteed to carry timestamp multiplier `i` — [frameIndexAt] falls
  /// back to a binary search on real timestamp when this is false.
  /// Source: `PlexThumbnailService.swift:262-266,333-351`.
  final bool timestampsAreContiguous;

  int get frameCount => frames.length;

  /// Parses a BIF container. Returns `null` (never throws) for a header
  /// shorter than the fixed 64-byte header, a bad magic number, or an index
  /// table the byte array is too short to hold — every offset read is
  /// bounds-checked before use.
  /// Source: `PlexThumbnailService.swift:275-352`.
  static BifThumbnailIndex? parse(Uint8List data) {
    if (data.length < _headerSize) return null;
    for (var i = 0; i < _magic.length; i++) {
      if (data[i] != _magic[i]) return null;
    }

    final header = ByteData.sublistView(data);
    final frameCount = header.getUint32(12, Endian.little);
    var interval = header.getUint32(16, Endian.little);
    // BIF spec: timestamp multiplier of 0 means use the default of 1000ms.
    if (interval == 0) interval = 1000;

    const indexStart = _headerSize;
    // +1 for the end-marker entry. `frameCount` is attacker/file
    // controlled; guard the multiply/add against overflow before trusting
    // it as a byte offset.
    final entryCount = frameCount + 1;
    if (entryCount > (1 << 32)) return null;
    final indexEnd = indexStart + entryCount * _indexEntrySize;
    if (indexEnd < 0 || data.length < indexEnd) return null;

    final frameInfos = <(int timestamp, int offset)>[];
    for (var i = 0; i < frameCount; i++) {
      final entryOffset = indexStart + i * _indexEntrySize;
      final timestamp = header.getUint32(entryOffset, Endian.little);
      final offset = header.getUint32(entryOffset + 4, Endian.little);
      frameInfos.add((timestamp, offset));
    }

    final endOffset = header.getUint32(
      indexStart + frameCount * _indexEntrySize + 4,
      Endian.little,
    );

    final frames = <BifFrame>[];
    var anyFrameDropped = false;
    for (var i = 0; i < frameInfos.length; i++) {
      final (timestamp, offset) = frameInfos[i];
      final nextOffset = i + 1 < frameInfos.length
          ? frameInfos[i + 1].$2
          : endOffset;

      final start = offset;
      final end = nextOffset;

      if (start >= data.length || end > data.length || start >= end) {
        anyFrameDropped = true;
        continue;
      }

      frames.add(
        BifFrame(timestamp: timestamp, imageData: data.sublist(start, end)),
      );
    }

    return BifThumbnailIndex._(
      intervalMs: interval,
      frames: frames,
      timestampsAreContiguous: !anyFrameDropped,
    );
  }

  /// Nearest frame index for a playback [time].
  ///
  /// Fast path (O(1)): valid ONLY when timestamps are dense frame numbers
  /// (`frames[i].timestamp == i`). Fallback path (O(log n)): binary-search
  /// `frames` (timestamp-sorted by construction) by real time, for BIFs
  /// with strided timestamps or a parser-dropped middle frame.
  /// Source: `PlexThumbnailService.swift:369-409`.
  int? frameIndexAt(Duration time) {
    if (frames.isEmpty) return null;
    final interval = intervalMs / 1000.0;
    if (interval <= 0) return 0;

    final seconds = time.inMicroseconds / Duration.microsecondsPerSecond;
    final timestampsAreDense = frames.last.timestamp == frames.length - 1;
    if (timestampsAreContiguous && timestampsAreDense) {
      final idx = (seconds / interval).round();
      return idx.clamp(0, frames.length - 1);
    }

    return _nearestFrameIndexByBinarySearch(seconds, interval);
  }

  int _nearestFrameIndexByBinarySearch(
    double realTimeSeconds,
    double interval,
  ) {
    var low = 0;
    var high = frames.length - 1;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      final midTime = frames[mid].timestamp * interval;
      if (midTime < realTimeSeconds) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    if (low > 0) {
      final lowTime = frames[low].timestamp * interval;
      final prevTime = frames[low - 1].timestamp * interval;
      if ((prevTime - realTimeSeconds).abs() <=
          (lowTime - realTimeSeconds).abs()) {
        return low - 1;
      }
    }
    return low;
  }

  /// Resolves one frame index per requested [times], aligned 1:1.
  ///
  /// `times` may be evenly-spaced samples across the FULL media duration,
  /// but this BIF's index can cover a shorter real-time span than the media
  /// itself. Naively passing every time through [frameIndexAt] doesn't
  /// error for times past the BIF's last real frame — it clamps to
  /// `frames.length - 1` — so every tail sample past that point would
  /// collapse onto the same final frame. Times past coverage are instead
  /// spread evenly across whatever frame indices remain unused between the
  /// last in-range frame and the final frame.
  /// Source: `PlexThumbnailService.swift:92-117`.
  List<int?> frameIndicesForTimes(List<Duration> times) {
    if (frames.isEmpty || times.isEmpty) {
      return List<int?>.filled(times.length, null);
    }
    final interval = intervalMs / 1000.0;
    final lastIndex = frames.length - 1;
    final coverage = interval > 0
        ? frames[lastIndex].timestamp * interval
        : 0.0;

    final seconds = times
        .map((t) => t.inMicroseconds / Duration.microsecondsPerSecond)
        .toList();
    final inRangeCount = coverage > 0
        ? seconds.where((s) => s <= coverage).length
        : seconds.length;
    final overshotCount = seconds.length - inRangeCount;
    if (overshotCount <= 0) {
      return times.map(frameIndexAt).toList();
    }

    final lastInRangeIndex = inRangeCount > 0
        ? (frameIndexAt(times[inRangeCount - 1]) ?? 0)
        : -1;
    final availableStart = (lastInRangeIndex + 1).clamp(0, lastIndex);
    final availableCount = lastIndex - availableStart + 1;

    return List<int?>.generate(times.length, (position) {
      if (position < inRangeCount) return frameIndexAt(times[position]);
      final tailPosition = position - inRangeCount;
      if (overshotCount <= 1 || availableCount <= 1) return lastIndex;
      final fraction = tailPosition / (overshotCount - 1);
      final offset = ((availableCount - 1) * fraction).round();
      return (availableStart + offset).clamp(0, lastIndex);
    });
  }
}
