import 'package:ui/src/l10n_gen/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ui/src/browse/year_picker.dart';
import 'package:ui/src/theme/app_theme.dart';

void main() {
  final now = DateTime.now().year;
  YearSelection? result;
  Future<void> open(WidgetTester tester, {int? from, int? to}) async {
    result = null;
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () async =>
                result = await showYearPicker(c, from: from, to: to),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> openWheels(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('year-custom')));
    await tester.pumpAndSettle();
  }

  testWidgets('keyboard/remote: Down steps a year, Select then Apply', (
    tester,
  ) async {
    await open(tester);
    await openWheels(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(result, (from: now - 1, to: now - 1));
  });

  testWidgets('the current choice is checked and holds the first focus', (
    tester,
  ) async {
    await open(tester, from: now - 2, to: now);
    final row = find.byKey(const ValueKey('year-preset-2'));
    expect(
      find.descendant(
        of: row,
        matching: find.byIcon(PhosphorIconsRegular.check),
      ),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(result, (from: now - 2, to: now));
  });

  testWidgets('Any year clears the selection', (tester) async {
    await open(tester, from: now - 2, to: now);
    await tester.tap(find.byKey(const ValueKey('year-clear')));
    await tester.pumpAndSettle();
    expect(result, (from: null, to: null));
  });

  testWidgets('range mode shows two wheels', (tester) async {
    await open(tester, from: now - 3, to: now);
    await openWheels(tester);
    expect(find.byKey(const ValueKey('year-start')), findsOneWidget);
    expect(find.byKey(const ValueKey('year-end')), findsOneWidget);
  });

  testWidgets('preset closes the popup with its range', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('year-preset-5')));
    await tester.pumpAndSettle();
    expect(result, (from: now - 5, to: now));
  });
}
