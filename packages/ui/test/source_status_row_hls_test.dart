import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

void main() {
  testWidgets('HLS source has its own label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: Scaffold(
          body: SourceStatusRow(
            source: SourceSpec(
              kind: SourceKind.hlsUrl,
              uri: Uri.parse('https://s.example/playlist.m3u8'),
            ),
            active: false,
          ),
        ),
      ),
    );
    expect(find.text('HLS · s.example'), findsOneWidget);
  });
}
