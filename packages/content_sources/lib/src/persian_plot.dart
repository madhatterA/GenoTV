/// Plot text in Persian for the detail page (Farsi mode only), first hit wins:
/// TMDB fa-IR, then MovieJavan, then CCloud, then the English TMDB plot.
/// Every step is optional; a step that throws or returns no Persian text
/// falls through to the next one.
Future<String?> persianPlot({
  required Future<String?> Function() tmdbFa,
  required Future<String?> Function() movieJavan,
  required Future<String?> Function() cCloud,
  required String? english,
}) async {
  for (final step in [tmdbFa, movieJavan, cCloud]) {
    try {
      final text = await step();
      if (text != null && isPersianText(text)) return text.trim();
    } on Object {
      // A provider that is down must not hide the plot behind it.
    }
  }
  return english;
}

/// Whether [text] is mostly Arabic-script letters (Persian), not English.
bool isPersianText(String text) {
  final letters = RegExp(r'\p{L}', unicode: true).allMatches(text).length;
  final persian = RegExp(
    r'[\u0600-\u06FF\uFB50-\uFDFF\uFE70-\uFEFF]',
  ).allMatches(text).length;
  return letters > 0 && persian * 2 >= letters;
}

/// The story part of a provider description: the text after [marker]
/// (MovieJavan "خلاصه داستان:", CCloud "درباره فیلم:"); the whole text when
/// the marker is absent. Rating, country and cast lines before it are dropped.
String? storyAfter(String? description, String marker) {
  if (description == null) return null;
  final at = description.indexOf(marker);
  final story = at < 0
      ? description
      : description.substring(at + marker.length);
  final trimmed = story.trim();
  return trimmed.isEmpty ? null : trimmed;
}
