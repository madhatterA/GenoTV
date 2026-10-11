import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/src/l10n_gen/app_strings.dart';

/// Every string getter returns `⟦<key>⟧`, so a screen built with it shows which
/// text came from [AppStrings] and which is still a literal.
class MarkedStrings extends AppStrings {
  MarkedStrings() : super('en');

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = RegExp(r'Symbol\("(.*)"\)')
        .firstMatch(invocation.memberName.toString())!
        .group(1)!;
    return '⟦$name⟧';
  }
}

class MarkedStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const MarkedStringsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppStrings> load(Locale locale) =>
      SynchronousFuture<AppStrings>(MarkedStrings());

  @override
  bool shouldReload(MarkedStringsDelegate old) => false;
}

/// Technical names that stay Latin in Farsi (DESIGN_SPEC §10.2 exemptions).
const Set<String> kTechAllowlist = <String>{
  'HDR', 'HDR10', 'HDR10+', 'Dolby', 'Vision', 'Atmos', 'HEVC', 'AVC', 'H.264',
  'H.265', 'AV1', 'AAC', 'AC3', 'EAC3', 'E-AC-3', 'DTS', 'TrueHD', 'FLAC',
  'Opus', 'MKV', 'MP4', 'AirPlay', 'Chromecast', 'DLNA', 'TMDB', 'IMDb', 'SDR',
  'PCM', 'FPS', 'Hz', 'kbps', 'Mbps', 'GB', 'MB', 'Video Player',
  'HTTP', 'https', '.torrent', 'zip', 'Rotten Tomatoes', //
};

Iterable<String> _texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '');

final RegExp _latinRun = RegExp(r'[A-Za-z]{2,}');

/// Latin-letter texts on screen that are not `⟦marker⟧` strings: literals that
/// were never moved into the ARB files.
List<String> findUnextractedText(
  WidgetTester tester, {
  Set<String> allow = const <String>{},
}) => [
  for (final text in _texts(tester))
    if (!text.contains('⟦') &&
        !allow.contains(text) &&
        _latinRun.hasMatch(text))
      text,
];

/// Under Farsi: texts that still hold a Latin word after the allowlisted
/// technical names are removed.
List<String> findUntranslatedText(
  WidgetTester tester, {
  Set<String> allow = const <String>{},
}) {
  final terms = allow.toList()..sort((a, b) => b.length.compareTo(a.length));
  return [
    for (final text in _texts(tester))
      if (_latinRun.hasMatch(terms.fold(text, (s, t) => s.replaceAll(t, ''))))
        text,
  ];
}
