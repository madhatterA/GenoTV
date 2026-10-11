import 'package:ui/src/l10n_gen/app_strings.dart';
// Golden of every Phosphor icon the app uses (DESIGN_SPEC §11), Regular and
// Fill, so a missing font shows up as boxes here first.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

const _regular = <String, IconData>{
  'house': PhosphorIconsRegular.house,
  'filmSlate': PhosphorIconsRegular.filmSlate,
  'television': PhosphorIconsRegular.television,
  'squaresFour': PhosphorIconsRegular.squaresFour,
  'heart': PhosphorIconsRegular.heart,
  'magnifyingGlass': PhosphorIconsRegular.magnifyingGlass,
  'link': PhosphorIconsRegular.link,
  'gear': PhosphorIconsRegular.gear,
  'arrowLeft': PhosphorIconsRegular.arrowLeft,
  'caretRight': PhosphorIconsRegular.caretRight,
  'caretLeft': PhosphorIconsRegular.caretLeft,
  'caretDown': PhosphorIconsRegular.caretDown,
  'arrowDown': PhosphorIconsRegular.arrowDown,
  'play': PhosphorIconsRegular.play,
  'playCircle': PhosphorIconsRegular.playCircle,
  'pause': PhosphorIconsRegular.pause,
  'stop': PhosphorIconsRegular.stop,
  'arrowCounterClockwise': PhosphorIconsRegular.arrowCounterClockwise,
  'arrowsClockwise': PhosphorIconsRegular.arrowsClockwise,
  'x': PhosphorIconsRegular.x,
  'check': PhosphorIconsRegular.check,
  'checkSquare': PhosphorIconsRegular.checkSquare,
  'square': PhosphorIconsRegular.square,
  'plus': PhosphorIconsRegular.plus,
  'minus': PhosphorIconsRegular.minus,
  'sortAscending': PhosphorIconsRegular.sortAscending,
  'funnel': PhosphorIconsRegular.funnel,
  'sliders': PhosphorIconsRegular.sliders,
  'info': PhosphorIconsRegular.info,
  'user': PhosphorIconsRegular.user,
  'subtitles': PhosphorIconsRegular.subtitles,
  'closedCaptioning': PhosphorIconsRegular.closedCaptioning,
  'waveform': PhosphorIconsRegular.waveform,
  'globe': PhosphorIconsRegular.globe,
  'gauge': PhosphorIconsRegular.gauge,
  'wifiHigh': PhosphorIconsRegular.wifiHigh,
  'wifiSlash': PhosphorIconsRegular.wifiSlash,
  'cloudSlash': PhosphorIconsRegular.cloudSlash,
  'downloadSimple': PhosphorIconsRegular.downloadSimple,
  'folderOpen': PhosphorIconsRegular.folderOpen,
  'trash': PhosphorIconsRegular.trash,
  'image': PhosphorIconsRegular.image,
  'clockCounterClockwise': PhosphorIconsRegular.clockCounterClockwise,
  'desktop': PhosphorIconsRegular.desktop,
  'sparkle': PhosphorIconsRegular.sparkle,
  'screencast': PhosphorIconsRegular.screencast,
  'airplay': PhosphorIconsRegular.airplay,
  'list': PhosphorIconsRegular.list,
};

const _fill = <String, IconData>{
  'house': PhosphorIconsFill.house,
  'filmSlate': PhosphorIconsFill.filmSlate,
  'television': PhosphorIconsFill.television,
  'heart': PhosphorIconsFill.heart,
  'gear': PhosphorIconsFill.gear,
  'play': PhosphorIconsFill.play,
  'pause': PhosphorIconsFill.pause,
  'stop': PhosphorIconsFill.stop,
  'checkSquare': PhosphorIconsFill.checkSquare,
};

Widget _cell(String name, IconData icon) => SizedBox(
  width: 110,
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 24, color: Colors.white),
      const SizedBox(height: 4),
      Text(
        name,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white70, fontSize: 10),
      ),
    ],
  ),
);

void main() {
  testWidgets('icons sheet golden', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: const Key('sheet'),
          child: Material(
            color: const Color(0xFF121212),
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 12,
                children: [
                  for (final e in _regular.entries)
                    _cell('${e.key} R', e.value),
                  for (final e in _fill.entries) _cell('${e.key} F', e.value),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byKey(const Key('sheet')),
      matchesGoldenFile('goldens/p06/icons_sheet.png'),
    );
  });
}
