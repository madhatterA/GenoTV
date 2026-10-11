import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

void main() {
  testWidgets(
    'empty chapters render no entry point and populated chapters seek',
    (tester) async {
      final seeks = <Duration>[];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          home: ChaptersOverlay(
            chapters: const <Chapter>[],
            onSeek: seeks.add,
            onClose: () {},
          ),
        ),
      );
      expect(find.byKey(const ValueKey<String>('overlay-shell')), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          home: ChaptersOverlay(
            chapters: <Chapter>[Chapter(start: Duration.zero, title: 'Intro')],
            onSeek: seeks.add,
            onClose: () {},
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey<String>('chapter-0')));
      expect(seeks, <Duration>[Duration.zero]);
    },
  );
}
