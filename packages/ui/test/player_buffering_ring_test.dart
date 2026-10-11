import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

void main() {
  testWidgets('ring shows 42% for 0.42', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: const PlayerBufferingIndicator(progress: 0.42),
      ),
    );
    expect(find.text('42%'), findsOneWidget);
  });
}
