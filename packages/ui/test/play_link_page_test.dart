import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/surface_size.dart';

class _Harness {
  _Harness({this.picked}) {
    recents = RecentLinks(
      MemorySettingsStore(),
      clock: () => DateTime(2026, 10, 3, 0, 0, _tick++),
    );
  }

  int _tick = 0;
  late final RecentLinks recents;
  final String? picked;
  final played = <String>[];
  String? error;
  var pickerOpened = 0;

  Future<String?> onPlay(String link) async {
    played.add(link);
    if (error != null) return error;
    await recents.add(link, kind: 'directFile');
    return null;
  }

  Future<String?> pick() async {
    pickerOpened++;
    return picked;
  }

  Widget app() => MaterialApp(
    localizationsDelegates: const [AppStrings.delegate],
    theme: AppTheme.dark(tv: false),
    home: PlayLinkPage(recents: recents, onPlay: onPlay, pickTorrent: pick),
  );
}

Future<void> _pump(
  WidgetTester tester,
  _Harness h, [
  Size size = const Size(1280, 800),
]) async {
  await setLogicalSize(tester, size);
  await tester.pumpWidget(h.app());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('link action pills stay compact across window sizes', (
    tester,
  ) async {
    final sizes = <Size>[];
    for (final width in [400.0, 1280.0, 1920.0, 3840.0]) {
      await _pump(tester, _Harness(), Size(width, 800));
      sizes.add(
        tester.getSize(find.widgetWithText(AppButton, 'Import .torrent')),
      );
    }
    expect(sizes.first.width, lessThan(190));
    expect(sizes.last.width, lessThan(205));
    expect(sizes.last.height, lessThan(56));
    expect(sizes.last.width / sizes.first.width, lessThan(1.11));
  });
  testWidgets('paste + Play hands the link to the player and clears input', (
    tester,
  ) async {
    final h = _Harness();
    await _pump(tester, h);
    await tester.enterText(find.byType(TextField), ' https://x/a.mp4 ');
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    expect(h.played, ['https://x/a.mp4']);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(
      find.byKey(const ValueKey('recent-https://x/a.mp4')),
      findsOneWidget,
    );
  });

  testWidgets('Enter plays', (tester) async {
    final h = _Harness();
    await _pump(tester, h);
    await tester.enterText(find.byType(TextField), 'magnet:?xt=urn:btih:abc');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(h.played, ['magnet:?xt=urn:btih:abc']);
  });

  testWidgets('invalid link shows the typed error inline and keeps input', (
    tester,
  ) async {
    final h = _Harness()..error = 'Not a playable link.';
    await _pump(tester, h);
    await tester.enterText(find.byType(TextField), 'nonsense');
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    expect(find.text('Not a playable link.'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'nonsense',
    );
    expect(h.recents.entries, isEmpty);
  });

  testWidgets('Import .torrent opens the picker and plays the chosen file', (
    tester,
  ) async {
    final h = _Harness(picked: '/tmp/a.torrent');
    await _pump(tester, h);
    await tester.tap(find.text('Import .torrent'));
    await tester.pumpAndSettle();
    expect(h.pickerOpened, 1);
    expect(h.played, ['/tmp/a.torrent']);
  });

  testWidgets('cancelled picker plays nothing', (tester) async {
    final h = _Harness();
    await _pump(tester, h);
    await tester.tap(find.text('Import .torrent'));
    await tester.pumpAndSettle();
    expect(h.pickerOpened, 1);
    expect(h.played, isEmpty);
  });

  testWidgets('Recent: newest first, max 10, repeat moves to top', (
    tester,
  ) async {
    final h = _Harness();
    await _pump(tester, h);
    for (var i = 1; i <= 11; i++) {
      await tester.enterText(find.byType(TextField), 'https://x/$i.mp4');
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
    }
    await tester.enterText(find.byType(TextField), 'https://x/5.mp4');
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    expect(h.recents.entries.length, 10);
    expect(h.recents.entries.first.link, 'https://x/5.mp4');
    expect(h.recents.entries.map((e) => e.link).toSet().length, 10);
    expect(find.byKey(const ValueKey('recent-https://x/1.mp4')), findsNothing);
    expect(
      find.byKey(const ValueKey('recent-https://x/2.mp4')),
      findsOneWidget,
    );
  });

  testWidgets('tap replays, remove drops one, clear all asks first', (
    tester,
  ) async {
    final h = _Harness();
    await h.recents.add('https://x/a.mp4', kind: 'directFile');
    await h.recents.add('https://x/b.mp4', kind: 'directFile');
    await _pump(tester, h);
    final labels = tester
        .widgetList<AppRow>(find.byType(AppRow))
        .map((b) => b.label)
        .toList();
    expect(labels, ['https://x/b.mp4', 'https://x/a.mp4']);

    await tester.tap(find.byKey(const ValueKey('recent-https://x/a.mp4')));
    await tester.pumpAndSettle();
    expect(h.played, ['https://x/a.mp4']);

    await tester.tap(find.bySemanticsLabel('Remove https://x/b.mp4'));
    await tester.pumpAndSettle();
    expect(h.recents.entries.map((e) => e.link), ['https://x/a.mp4']);

    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(h.recents.entries, hasLength(1));

    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(GlassSurface),
        matching: find.text('Clear all'),
      ),
    );
    await tester.pumpAndSettle();
    expect(h.recents.entries, isEmpty);
  });

  testWidgets('focus order: input, Play, Import, Recent items', (tester) async {
    final h = _Harness();
    await h.recents.add('https://x/a.mp4', kind: 'directFile');
    await _pump(tester, h);
    bool focusIn(Finder f) => find
        .descendant(
          of: f,
          matching: find.byWidgetPredicate(
            (w) => w is Focus && w.focusNode?.hasPrimaryFocus == true,
          ),
        )
        .evaluate()
        .isNotEmpty;
    final input = find.byType(TextField);
    final play = find.widgetWithText(AppButton, 'Play');
    final import = find.widgetWithText(AppButton, 'Import .torrent');
    final recent = find.widgetWithText(AppRow, 'https://x/a.mp4');
    expect(focusIn(input), isTrue);
    for (final next in [play, import, recent]) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focusIn(next), isTrue);
    }
  });

  for (final (name, size) in [
    ('desktop', const Size(1280, 800)),
    ('phone', const Size(400, 800)),
  ]) {
    testWidgets('golden: empty page, $name', (tester) async {
      await _pump(tester, _Harness(), size);
      await expectLater(
        find.byType(PlayLinkPage),
        matchesGoldenFile('goldens/play_link_empty_$name.png'),
      );
    });

    testWidgets('golden: page with Recent, $name', (tester) async {
      final h = _Harness();
      await h.recents.add(
        'https://cdn.example.com/movies/film.mp4',
        kind: 'directFile',
      );
      await h.recents.add(
        'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567',
        kind: 'magnet',
        title: 'Sample Film 2160p',
      );
      await h.recents.add('https://example.com/live/stream.m3u8', kind: 'hls');
      await _pump(tester, h, size);
      await expectLater(
        find.byType(PlayLinkPage),
        matchesGoldenFile('goldens/play_link_recent_$name.png'),
      );
    });
  }
}
