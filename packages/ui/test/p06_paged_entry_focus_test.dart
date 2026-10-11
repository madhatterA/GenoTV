import 'dart:async';

import 'package:contracts/contracts.dart' hide PlatformCapabilities;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/surface_size.dart';

void main() {
  for (final scenario in ['entry', 'moved', 'disabled', 'tv']) {
    testWidgets('delayed paged grid focus: $scenario', (tester) async {
      await setLogicalSize(tester, const Size(1280, 800));
      final pending = Completer<TitlePage>();
      final first = FocusNode();
      final other = FocusNode();
      await tester.pumpWidget(
        AdaptiveBehavior(
          capabilities: PlatformCapabilities(isTv: scenario == 'tv'),
          child: MaterialApp(
            localizationsDelegates: const [AppStrings.delegate],
            theme: AppTheme.dark(tv: scenario == 'tv'),
            home: PagedTitleGrid(
              title: 'Movies',
              initialQuery: TitleQuery(kind: TitleKind.movie),
              source: (_, _) => pending.future,
              firstFocusNode: first,
              autofocus: scenario != 'disabled',
              header: TextButton(
                focusNode: other,
                onPressed: () {},
                child: const Text('Another control'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      if (scenario == 'moved') {
        other.requestFocus();
        await tester.pump();
      }

      pending.complete(
        TitlePage(
          items: [
            MediaItem(id: '1', title: 'First title', kind: MediaKind.movie),
          ],
        ),
      );
      await tester.pumpAndSettle();
      if (scenario == 'entry') {
        expect(first.hasFocus, isTrue);
      } else if (scenario == 'moved') {
        expect(other.hasFocus, isTrue);
        expect(first.hasFocus, isFalse);
      } else if (scenario == 'tv') {
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'filter-first');
        expect(first.hasFocus, isFalse);
      } else {
        expect(first.hasFocus, isFalse);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      first.dispose();
      other.dispose();
    });
  }
}
