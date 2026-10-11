import 'package:contracts/contracts.dart';

/// media_kit 1.2 does not expose mpv's chapter-list property. Keep this mapper
/// ready for a future media_kit chapter surface; an absent list is represented
/// as an empty list by the controller.
List<Chapter> mapChapters(
  Iterable<({Duration start, String? title})> chapters,
) {
  final result =
      chapters
          .map((chapter) => Chapter(start: chapter.start, title: chapter.title))
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  return List.unmodifiable(result);
}
