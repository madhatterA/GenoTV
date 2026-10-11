import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/main.dart';

void main() {
  testWidgets('boot screen renders the app name and a platform string', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BootApp());

    expect(find.text(BootApp.appName), findsOneWidget);

    final platform = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('boot-platform')),
        matching: find.byType(Text),
      ),
    );
    expect(platform.data, isNotNull);
    expect(platform.data, isNotEmpty);
  });
}
