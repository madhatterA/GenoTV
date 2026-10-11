import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

void main() {
  // A route pushed without a Scaffold has no Material ancestor; ErrorView
  // must still render styled (no underline, themed text).
  testWidgets('full-screen ErrorView is styled outside a Scaffold', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: Builder(
          builder: (_) =>
              const ErrorView(failure: CancelledFailure(), fullScreen: true),
        ),
      ),
    );
    final style = DefaultTextStyle.of(
      tester.element(find.text('Unable to continue')),
    ).style;
    expect(style.decoration, isNot(TextDecoration.underline));
    expect(style.fontSize, lessThan(30));
  });
}
