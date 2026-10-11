import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

const _cardKey = ValueKey<String>('ring-card');

Widget _host({
  required FocusNode button,
  required FocusNode card,
  bool tv = false,
}) => MaterialApp(
  localizationsDelegates: const [AppStrings.delegate],
  theme: AppTheme.dark(tv: tv),
  home: MediaQuery(
    data: MediaQueryData(
      size: tv ? const Size(960, 540) : const Size(1280, 800),
    ),
    child: AdaptiveBehavior(
      capabilities: tv
          ? const PlatformCapabilities.directionalPad()
          : const PlatformCapabilities(),
      child: Scaffold(
        body: Column(
          children: <Widget>[
            AppButton.primary(
              label: 'Play',
              focusNode: button,
              onActivate: () {},
            ),
            FocusableCard(
              surfaceId: 'ring',
              itemId: 'ring-card',
              memory: FocusMemory(),
              focusNode: card,
              width: 100,
              height: 150,
              child: const SizedBox.expand(),
            ),
          ],
        ),
      ),
    ),
  ),
);

Finder get _ring => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.foregroundPainter is FocusRingPainter,
);

double _scaleOf(WidgetTester tester, Finder inside) => tester
    .widget<ScaleTransition>(
      find.descendant(of: inside, matching: find.byType(ScaleTransition)).first,
    )
    .scale
    .value;

void main() {
  late FocusNode button;
  late FocusNode card;

  setUp(() {
    button = FocusNode();
    card = FocusNode();
  });
  tearDown(() {
    button.dispose();
    card.dispose();
  });

  testWidgets('desktop + pointer: focused button paints no ring', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(_host(button: button, card: card));
    button.requestFocus();
    await tester.pumpAndSettle();
    expect(button.hasFocus, isTrue);
    expect(_ring, findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop + keyboard: ring 2 px accent 3 px out, card 1.04', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(_host(button: button, card: card));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    button.requestFocus();
    await tester.pumpAndSettle();
    expect(_ring, findsOneWidget);
    final painter =
        tester.widget<CustomPaint>(_ring).foregroundPainter!
            as FocusRingPainter;
    expect(painter.color, RivuletColors.dark().accent);
    expect(FocusRingPainter.thickness, 2);
    expect(FocusRingPainter.offset, 3);
    expect(_scaleOf(tester, find.byType(AppButton)), 1.0);

    card.requestFocus();
    await tester.pumpAndSettle();
    expect(_scaleOf(tester, find.byKey(_cardKey)), closeTo(1.04, 0.0001));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('tv: ring, card 1.06, button 1.0, no shadow on the card', (
    tester,
  ) async {
    await tester.pumpWidget(_host(button: button, card: card, tv: true));
    button.requestFocus();
    await tester.pumpAndSettle();
    expect(_ring, findsOneWidget);
    expect(_scaleOf(tester, find.byType(AppButton)), 1.0);

    card.requestFocus();
    await tester.pumpAndSettle();
    expect(_ring, findsOneWidget);
    expect(_scaleOf(tester, find.byKey(_cardKey)), closeTo(1.06, 0.0001));
    final shadows = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byKey(_cardKey),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((d) => d.decoration)
        .whereType<BoxDecoration>()
        .expand((d) => d.boxShadow ?? const <BoxShadow>[]);
    expect(shadows, isEmpty);
  });

  testWidgets('no frame callback stays registered while idle', (tester) async {
    await tester.pumpWidget(_host(button: button, card: card, tv: true));
    card.requestFocus();
    await tester.pumpAndSettle();
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });
}
