import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/surface_size.dart';

import 'package:ui/src/navigation/page_top_inset.dart';

Widget _host({bool legacyWrapper = false}) => MaterialApp(
  localizationsDelegates: const [AppStrings.delegate],
  theme: AppTheme.dark(tv: false),
  builder: (_, child) => NavigatorBackShortcuts(child: child!),
  home: AppShell(
    activeId: 'settings',
    destinations: [
      AppDestination(
        id: 'settings',
        label: 'Settings',
        icon: Icons.settings,
        builder: (context) => Scaffold(
          appBar: PreferredSize(
            preferredSize: Size.fromHeight(pageTopInsetOf(context)),
            child: PageHeader(
              title: 'Settings',
              showBackButton: ModalRoute.of(context)?.canPop ?? false,
            ),
          ),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final root in [false, true])
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: root).push<void>(
                          MaterialPageRoute<void>(
                            builder: (context) => Scaffold(
                              key: const ValueKey('pushed-page'),
                              appBar: PreferredSize(
                                preferredSize: Size.fromHeight(
                                  pageTopInsetOf(context),
                                ),
                                child: PageHeader(
                                  title: 'Playback',
                                  showBackButton:
                                      ModalRoute.of(context)?.canPop ?? false,
                                ),
                              ),
                              body: _pageBody(legacyWrapper),
                            ),
                          ),
                        ),
                    child: Text(root ? 'Push root' : 'Push tab'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ],
  ),
);

Widget _pageBody(bool legacyWrapper) {
  final body = Column(
    children: [
      const TextField(key: ValueKey('editable')),
      TextButton(
        autofocus: true,
        onPressed: () {},
        child: const Text('Focus here'),
      ),
    ],
  );
  return legacyWrapper ? PopOnEscape(child: body) : body;
}

void main() {
  testWidgets('back button clears sidebar and shares page background', (
    tester,
  ) async {
    for (final size in [const Size(800, 600), const Size(1400, 900)]) {
      await setLogicalSize(tester, size);
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Push tab'));
      await tester.pumpAndSettle();
      final back = find.byKey(const ValueKey('top-back'));
      final pill = find.byKey(const ValueKey('menu-pill'));
      final header = find.byType(PageHeader);
      final scaffold = find
          .ancestor(of: header, matching: find.byType(Scaffold))
          .first;
      expect(
        find
            .descendant(of: scaffold, matching: find.byType(DecoratedBox))
            .evaluate()
            .where(
              (e) => find
                  .ancestor(of: header, matching: find.byWidget(e.widget))
                  .evaluate()
                  .isNotEmpty,
            ),
        isEmpty,
        reason: 'the header draws no background of its own',
      );
      expect(tester.getRect(back).overlaps(tester.getRect(pill)), isFalse);
      expect(
        tester.getRect(back).overlaps(tester.getRect(find.text('Playback'))),
        isFalse,
      );
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pushed-page')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('shared Escape and Backspace pop tab and root pushed pages', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1400, 900));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    for (final route in ['Push tab', 'Push root']) {
      for (final key in [
        LogicalKeyboardKey.escape,
        LogicalKeyboardKey.backspace,
      ]) {
        await tester.tap(find.text(route));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('pushed-page')), findsNothing);
      }
    }
  });

  testWidgets(
    'text editing protects both back shortcuts including old wrappers',
    (tester) async {
      for (final legacyWrapper in [false, true]) {
        await tester.pumpWidget(_host(legacyWrapper: legacyWrapper));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Push tab'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const ValueKey('editable')), 'abc');
        for (final key in [
          LogicalKeyboardKey.escape,
          LogicalKeyboardKey.backspace,
        ]) {
          await tester.sendKeyEvent(key);
          await tester.pump();
          expect(find.byKey(const ValueKey('pushed-page')), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('genres glyph uses ambient icon color and size', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: [AppStrings.delegate],
        home: Center(
          child: IconTheme(
            data: IconThemeData(size: 32, color: Colors.red),
            child: RepaintBoundary(
              key: ValueKey('genres-golden'),
              child: GenresIcon(),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(GenresIcon)), const Size(32, 32));
    await expectLater(
      find.byKey(const ValueKey('genres-golden')),
      matchesGoldenFile('goldens/genres_icon.png'),
    );
  });
}
