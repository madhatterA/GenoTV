import 'package:contracts/contracts.dart' show MediaItem, MediaKind;
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/settings_shell_host.dart';
import 'support/surface_size.dart';

Widget _shell(Widget page) => MaterialApp(
  localizationsDelegates: const [AppStrings.delegate],
  theme: AppTheme.dark(tv: false),
  home: AdaptiveBehavior(
    capabilities: const PlatformCapabilities.directionalPad(),
    child: AppShell(
      activeId: 'home',
      destinations: <AppDestination>[
        AppDestination(
          id: 'home',
          label: 'Home',
          icon: Icons.home,
          builder: (_) => page,
        ),
      ],
    ),
  ),
);

void main() {
  testWidgets('TV shell adds no top padding: pages bleed under the pill', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1920, 1080));
    await tester.pumpWidget(
      _shell(const SizedBox.expand(key: ValueKey('page'))),
    );
    await tester.pumpAndSettle();
    final page = tester.getRect(find.byKey(const ValueKey('page')));
    expect(page.top, 0);
  });

  testWidgets('TV Home keeps every focused row header visible down and up', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1920, 1080));
    final model = HomeViewModel(
      firstDeferredSectionReady: true,
      secondDeferredSectionReady: true,
      rows: <HomeRow>[
        for (var i = 0; i < 6; i++)
          HomeRow(
            title: 'Row $i',
            items: <MediaItem>[
              MediaItem(id: 'item-$i', title: 'Item $i', kind: MediaKind.movie),
            ],
          ),
      ],
    );
    await tester.pumpWidget(_shell(HomeScreen(viewModel: model)));
    await tester.pumpAndSettle();
    final cards = tester
        .widgetList<Focus>(
          find.descendant(
            of: find.byType(FocusableCard),
            matching: find.byType(Focus),
          ),
        )
        .map((f) => f.focusNode!)
        .toList();
    cards.first.requestFocus();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    Future<void> checkRow(int i) async {
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'item-$i');
      final header = tester.getRect(find.text('Row $i'));
      final viewport = tester.getRect(
        find.byKey(const ValueKey('home-screen')),
      );
      expect(
        header.top,
        greaterThanOrEqualTo(viewport.top),
        reason: 'Row $i header top',
      );
      expect(header.bottom, lessThanOrEqualTo(viewport.bottom));
    }

    await checkRow(0);
    for (var i = 1; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await checkRow(i);
    }
    for (var i = 4; i >= 0; i--) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await checkRow(i);
    }

    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });

  testWidgets('TV Settings rows and ring fit inside the glass clip', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1920, 1080));
    await pumpSettings(
      tester,
      AppSettings(MemorySettingsStore()),
      platform: const PlatformCapabilities.directionalPad(),
    );
    final section = find.byKey(const ValueKey('section-video'));
    final focus = tester.widget<Focus>(
      find.descendant(of: section, matching: find.byType(Focus)).first,
    );
    focus.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    final rect = FocusManager.instance.primaryFocus!.rect;
    final glass = tester.getRect(
      find.ancestor(of: section, matching: find.byType(TintedSurface)).first,
    );
    final ring = rect.inflate(
      FocusRingPainter.offset + FocusRingPainter.thickness,
    );
    final viewport = tester.getRect(find.byType(SingleChildScrollView));
    expect(ring.left, greaterThanOrEqualTo(viewport.left + 3));
    expect(ring.right, lessThanOrEqualTo(viewport.right - 3));
    expect(ring.top, greaterThanOrEqualTo(viewport.top + 3));
    expect(ring.bottom, lessThanOrEqualTo(viewport.bottom - 3));
    final icon = tester.getRect(
      find.descendant(of: section, matching: find.byType(Icon)).first,
    );
    expect(glass.contains(icon.topLeft), isTrue);
    expect(glass.contains(icon.bottomRight), isTrue);
  });
}
