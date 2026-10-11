import 'dart:ui' show SemanticsAction, Tristate;

import 'package:contracts/contracts.dart';
import 'package:contracts/fakes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

Future<void> pump(
  WidgetTester tester,
  Widget child, {
  bool accessible = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [AppStrings.delegate],
      theme: AppTheme.dark(tv: false),
      home: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(accessible ? 2 : 1),
          disableAnimations: accessible,
          highContrast: accessible,
        ),
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'disabled card announces disabled and high contrast keeps focus stroke',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(
        tester,
        FocusableCard(
          surfaceId: 'audit',
          itemId: 'card',
          memory: FocusMemory(),
          enabled: false,
          semanticLabel: 'Movie',
          child: const Text('Movie'),
        ),
        accessible: true,
      );
      final data = tester
          .getSemantics(find.byType(FocusableCard))
          .getSemanticsData();
      expect(data.flagsCollection.isEnabled, isNot(Tristate.none));
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      semantics.dispose();
      final node = FocusNode();
      await pump(
        tester,
        FocusableCard(
          surfaceId: 'audit',
          itemId: 'card',
          memory: FocusMemory(),
          key: const ValueKey('focused-card'),
          focusNode: node,
          onTap: () {},
          child: const Text('Movie'),
        ),
        accessible: true,
      );
      node.requestFocus();
      await tester.pumpAndSettle();
      final border = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(FocusableCard),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.border != null)
          .border!;
      expect((border as Border).top.width, 3);
      await tester.pumpWidget(const SizedBox());
      node.dispose();
    },
  );

  testWidgets('transport ordering retains media meaning in RTL', (
    tester,
  ) async {
    final controller = FakePlaybackController();
    await pump(
      tester,
      Directionality(
        textDirection: TextDirection.rtl,
        child: PlayerPrimaryTransport(
          controller: controller,
          state: PlaybackState.initial(),
        ),
      ),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey<String>('skip-back'))).dx,
      lessThan(
        tester.getCenter(find.byKey(const ValueKey<String>('skip-forward'))).dx,
      ),
    );
    await tester.pumpWidget(const SizedBox());
    await controller.dispose();
  });

  testWidgets('caller reduced transparency removes glass blur', (tester) async {
    await pump(
      tester,
      const UiAccessibility(
        reduceTransparency: true,
        child: GlassSurface(child: Text('Opaque')),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
  });
  testWidgets('commands wrap and grow at large text', (tester) async {
    await pump(
      tester,
      SizedBox(
        width: 240,
        child: FocusButton(
          label: 'Retry downloading the entire selected library',
          variant: FocusButtonVariant.row,
          onActivate: () {},
        ),
      ),
      accessible: true,
    );
    final text = tester.widget<Text>(
      find.text('Retry downloading the entire selected library'),
    );
    expect(text.overflow, isNot(TextOverflow.ellipsis));
    expect(tester.getSize(find.byType(FocusButton)).height, greaterThan(56));
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled transport exposes no activation or keyboard focus', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final node = FocusNode();
    await pump(
      tester,
      TransportControlButton(
        icon: Icons.play_arrow,
        semanticLabel: 'Play',
        focusNode: node,
        autofocus: true,
      ),
    );
    final data = tester
        .getSemantics(find.byType(TransportControlButton))
        .getSemanticsData();
    expect(data.flagsCollection.isEnabled, isNot(Tristate.none));
    expect(data.flagsCollection.isEnabled, Tristate.isFalse);
    expect(data.hasAction(SemanticsAction.tap), isFalse);
    expect(node.canRequestFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpWidget(const SizedBox());
    node.dispose();
    semantics.dispose();
  });

  testWidgets('panel announces selection and disables absent callback', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(
      tester,
      PanelRow(
        tokens: RivuletTokens.dark(tv: false),
        selected: true,
        child: const Text('English'),
      ),
    );
    final data = tester.getSemantics(find.byType(PanelRow)).getSemanticsData();
    expect(data.flagsCollection.isSelected, Tristate.isTrue);
    expect(data.flagsCollection.isEnabled, isNot(Tristate.none));
    expect(data.flagsCollection.isEnabled, Tristate.isFalse);
    semantics.dispose();
  });

  testWidgets('transport target stays at least 44 pixels', (tester) async {
    await pump(
      tester,
      TransportControlButton(
        icon: Icons.play_arrow,
        semanticLabel: 'Play',
        diameter: 24,
        onPress: () {},
      ),
    );
    expect(
      tester.getSize(find.byType(TransportControlButton)).shortestSide,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets(
    'accessible transport snaps motion and glass strengthens border',
    (tester) async {
      await pump(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TransportControlButton(
              icon: Icons.play_arrow,
              semanticLabel: 'Play',
              onPress: () {},
            ),
            const GlassSurface(child: Text('Controls')),
          ],
        ),
        accessible: true,
      );
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration,
        Duration.zero,
      );
      final panel = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(GlassSurface),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final border = (panel.decoration as BoxDecoration).border! as Border;
      expect(border.top.width, greaterThanOrEqualTo(2));
      expect(
        find.descendant(
          of: find.byType(GlassSurface),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
    },
  );
}
