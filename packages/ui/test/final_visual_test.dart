import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/surface_size.dart';

void main() {
  for (final size in [const Size(400, 800), const Size(1280, 800)]) {
    testWidgets('empty region is centered at $size', (tester) async {
      await setLogicalSize(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(tv: false),
          localizationsDelegates: AppStrings.localizationsDelegates,
          supportedLocales: AppStrings.supportedLocales,
          home: const Scaffold(body: EmptyView(headline: 'Nothing here')),
        ),
      );
      final column = tester.getRect(find.byType(Column).last);
      expect(column.center.dy, closeTo(size.height / 2, 1));
    });
  }

  testWidgets('empty actions remain reachable on a short enlarged screen', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(320, 160));
    var invoked = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(tv: false),
        localizationsDelegates: AppStrings.localizationsDelegates,
        supportedLocales: AppStrings.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: EmptyView(
            headline: 'No titles match this filter',
            body: 'Try another title or clear your filters.',
            fullScreen: true,
            onPrimary: () => invoked = true,
            primaryLabel: 'Clear filters',
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Clear filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear filters'));
    expect(invoked, isTrue);
    expect(tester.takeException(), isNull);
  });
}
