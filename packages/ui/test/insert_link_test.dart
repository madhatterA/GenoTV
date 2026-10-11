import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/surface_size.dart';

const _providers = <UiProviderOption>[
  UiProviderOption(id: 'a', name: '30nama', state: UiProviderState.ready),
  UiProviderOption(id: 'b', name: 'DigiMoviez', state: UiProviderState.ready),
];

final _insertRow = find.byKey(
  const ValueKey<String>('provider-row-insert-link'),
);

Widget _picker({
  required String title,
  String? subtitle,
  List<UiProviderOption> providers = _providers,
  VoidCallback? onInsertLink,
  List<String>? tapped,
}) => MaterialApp(
  localizationsDelegates: const [AppStrings.delegate],
  debugShowCheckedModeBanner: false,
  theme: AppTheme.dark(tv: false),
  home: PlaySourceScreen(
    title: title,
    subtitle: subtitle,
    providers: providers,
    streams: const UiStreamListNone(),
    onProviderSelected: (id) => tapped?.add(id),
    onStreamSelected: (_) {},
    onBack: () {},
    onInsertLink: onInsertLink,
  ),
);

/// Presses Tab until the Insert-link row holds focus (fails after 12 presses).
Future<void> _focusByTab(WidgetTester tester) async {
  bool onRow() {
    final context = FocusManager.instance.primaryFocus?.context;
    var found = false;
    context?.visitAncestorElements((e) {
      found = e.widget.key == _insertRow.evaluate().single.widget.key;
      return !found;
    });
    return found;
  }

  for (var i = 0; i < 12 && !onRow(); i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  expect(onRow(), isTrue, reason: 'Insert link… reachable by keyboard focus');
}

void main() {
  for (final item in const [
    ('movie', 'Inception', '2010 · Movie'),
    ('episode', 'Pilot', 'S01E01'),
  ]) {
    testWidgets(
      '${item.$1}: Insert link… is the last row and opens by keyboard',
      (tester) async {
        await setLogicalSize(tester, const Size(1280, 800));
        var opened = 0;
        await tester.pumpWidget(
          _picker(
            title: item.$2,
            subtitle: item.$3,
            onInsertLink: () => opened++,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Insert link…'), findsOneWidget);
        final bottoms = [
          for (final key in ['provider-row-a', 'provider-row-b'])
            tester.getTopLeft(find.byKey(ValueKey<String>(key))).dy,
        ];
        expect(tester.getTopLeft(_insertRow).dy, greaterThan(bottoms.last));

        await _focusByTab(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(opened, 1);
      },
    );
  }

  testWidgets('a title with no sources still shows Insert link…, focused', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1280, 800));
    var opened = 0;
    await tester.pumpWidget(
      _picker(
        title: 'Inception',
        providers: const [],
        onInsertLink: () => opened++,
      ),
    );
    await tester.pumpAndSettle();
    expect(_insertRow, findsOneWidget);
    await _focusByTab(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets('without onInsertLink the row is absent', (tester) async {
    await tester.pumpWidget(_picker(title: 'Inception'));
    await tester.pumpAndSettle();
    expect(_insertRow, findsNothing);
  });

  testWidgets('picker golden with Insert link… row', (tester) async {
    await setLogicalSize(tester, const Size(1280, 800));
    await tester.pumpWidget(
      _picker(
        title: 'Inception',
        subtitle: '2010 · Movie',
        onInsertLink: () {},
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(PlaySourceScreen),
      matchesGoldenFile('goldens/insert_link_picker.png'),
    );
  });

  group('dialog', () {
    Future<void> open(
      WidgetTester tester,
      Future<String?> Function(String) onPlay,
      List<bool?> results,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: false),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => results.add(
                await showPlayLinkDialog(
                  context,
                  onPlay: onPlay,
                  pickTorrent: () async => null,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('same input as the page, no Recent; playable link closes', (
      tester,
    ) async {
      await setLogicalSize(tester, const Size(1280, 800));
      final played = <String>[];
      final results = <bool?>[];
      await open(tester, (link) async {
        played.add(link);
        return null;
      }, results);
      expect(find.text('Torrent / https link'), findsOneWidget);
      expect(find.text('Import .torrent'), findsOneWidget);
      expect(find.text('Recent'), findsNothing);
      await expectLater(
        find.ancestor(
          of: find.text('Insert link'),
          matching: find.byType(GlassSurface),
        ),
        matchesGoldenFile('goldens/insert_link_dialog.png'),
      );
      await tester.enterText(find.byType(TextField), ' http://x/y.mkv ');
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(played, ['http://x/y.mkv']);
      expect(results, [true]);
      expect(find.text('Insert link'), findsNothing);
    });

    testWidgets('a bad link stays open with the message', (tester) async {
      final results = <bool?>[];
      await open(tester, (_) async => 'Not a playable link.', results);
      await tester.enterText(find.byType(TextField), 'nope');
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(find.text('Not a playable link.'), findsOneWidget);
      expect(results, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(results, [false]);
    });
  });
}
