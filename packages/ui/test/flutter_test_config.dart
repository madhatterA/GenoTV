// Test-only font loader so goldens render real type and real icons instead
// of `flutter test`'s default tofu/placeholder-box glyphs.
//
// The app never sets an explicit `fontFamily` (see `lib/src/theme/app_theme.dart`),
// so Material's default `TextTheme` family applies: every role in
// `flutter/packages/flutter/lib/src/material/typography.dart` hardcodes
// `fontFamily: 'Roboto'`. Loading a real font under that exact family name
// makes default `Text` widgets render real glyphs in tests. `Icon` widgets
// default to `IconData.fontFamily == 'MaterialIcons'`, so that family is
// loaded too, from the Flutter SDK's own vendored artifact (same font the
// real app ships), never from `research/` or a new dependency.
//
// Inter (OFL-licensed, vendored in `test/fonts/`) stands in for SF Pro: close
// x-height/weight family, avoids bundling Apple's non-redistributable font.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show FontLoader;
import 'package:ui/src/components/orb_loader.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await _loadFonts();
  OrbLoader.staticFrame = true;
  await testMain();
}

Future<void> _loadFonts() async {
  final fontsDir = Directory('${Directory.current.path}/test/fonts');

  Future<void> load(String family, List<String> fileNames) async {
    final loader = FontLoader(family);
    for (final fileName in fileNames) {
      final bytes = await File('${fontsDir.path}/$fileName').readAsBytes();
      loader.addFont(Future.value(bytes.buffer.asByteData()));
    }
    await loader.load();
  }

  // Roboto is Material's hardcoded default TextTheme family; Inter is the
  // OFL stand-in loaded under that name so default `Text` styles resolve to
  // it. Registering four weights lets bold/medium/semibold text styles pick
  // a distinct real weight instead of every weight faking the same glyphs.
  await load('Roboto', const [
    'Inter-Regular.ttf',
    'Inter-Medium.ttf',
    'Inter-SemiBold.ttf',
    'Inter-Bold.ttf',
  ]);
  // The stats overlay asks for Menlo (macOS monospace); tests have no Menlo,
  // so Inter stands in under that name (proportional, but real glyphs).
  await load('Menlo', const ['Inter-Regular.ttf', 'Inter-Bold.ttf']);
  await load('MaterialIcons', const ['MaterialIcons-Regular.otf']);

  // Package fonts resolve to `packages/<package>/<family>`; register the same
  // names so `TextStyle(package: 'ui')` and Phosphor icons render real glyphs.
  final vazirDir = '${Directory.current.path}/assets/fonts/vazirmatn';
  final vazir = FontLoader('packages/ui/Vazirmatn');
  for (final w in const ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = await File('$vazirDir/Vazirmatn-$w.ttf').readAsBytes();
    vazir.addFont(Future.value(bytes.buffer.asByteData()));
  }
  await vazir.load();

  final phosphorFonts = '${_packageRoot('phosphor_flutter')}/lib/fonts';
  for (final (family, file) in const [
    ('packages/phosphor_flutter/PhosphorRegular', 'Phosphor.ttf'),
    ('packages/phosphor_flutter/PhosphorFill', 'Phosphor-Fill.ttf'),
  ]) {
    final bytes = await File('$phosphorFonts/$file').readAsBytes();
    final loader = FontLoader(family)
      ..addFont(Future.value(bytes.buffer.asByteData()));
    await loader.load();
  }
}

/// Root directory of [package] from `.dart_tool/package_config.json`.
String _packageRoot(String package) {
  final config = File(
    '${Directory.current.path}/.dart_tool/package_config.json',
  );
  final packages =
      (jsonDecode(config.readAsStringSync())
              as Map<String, dynamic>)['packages']
          as List<dynamic>;
  final entry = packages.cast<Map<String, dynamic>>().firstWhere(
    (p) => p['name'] == package,
  );
  // rootUri is relative to the config file for path dependencies.
  return config.uri.resolve(entry['rootUri'] as String).toFilePath();
}
