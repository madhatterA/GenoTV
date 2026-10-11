import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/surface_size.dart';

DeviceProfile? _seen;
int _builds = 0;

Future<void> _pump(
  WidgetTester tester,
  Size size, {
  bool tv = false,
  bool reduceTransparency = false,
}) async {
  await setLogicalSize(tester, size);
  _seen = null;
  _builds = 0;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [AppStrings.delegate],
      builder: (_, child) => UiAccessibility(
        reduceTransparency: reduceTransparency,
        child: AdaptiveBehavior(
          capabilities: tv
              ? const PlatformCapabilities.directionalPad()
              : const PlatformCapabilities(),
          child: child!,
        ),
      ),
      home: Builder(
        builder: (context) {
          _seen = AdaptiveBehavior.of(context);
          _builds++;
          return const SizedBox();
        },
      ),
    ),
  );
}

void _case(
  String name,
  TargetPlatform platform,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  _case('android phone: phone, touch, blur', TargetPlatform.android, (
    tester,
  ) async {
    await _pump(tester, const Size(400, 800));
    expect(_seen!.formFactor, FormFactor.phone);
    expect(_seen!.inputMode, InputMode.touch);
    expect(_seen!.blurAllowed, isTrue);
  });

  _case('android tablet: desktop starts pointer', TargetPlatform.android, (
    tester,
  ) async {
    await _pump(tester, const Size(1280, 800));
    expect(_seen!.formFactor, FormFactor.desktop);
    expect(_seen!.inputMode, InputMode.pointer);
  });

  _case(
    'desktop hit target: 40 pointer, 48 touch, back on mouse',
    TargetPlatform.macOS,
    (tester) async {
      late BuildContext ctx;
      await setLogicalSize(tester, const Size(1280, 800));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          builder: (_, child) => AdaptiveBehavior(child: child!),
          home: Builder(
            builder: (context) {
              ctx = context;
              AdaptiveBehavior.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(AdaptiveBehavior.hitTargetOf(ctx), 40);
      final touch = await tester.createGesture(kind: PointerDeviceKind.touch);
      await touch.down(const Offset(10, 10));
      await touch.up();
      await tester.pump();
      expect(AdaptiveBehavior.hitTargetOf(ctx), 48);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(const Offset(20, 20));
      await tester.pump();
      expect(AdaptiveBehavior.hitTargetOf(ctx), 40);
    },
  );

  _case('macOS: desktop, pointer, blur', TargetPlatform.macOS, (tester) async {
    await _pump(tester, const Size(1280, 800));
    expect(_seen!.formFactor, FormFactor.desktop);
    expect(_seen!.inputMode, InputMode.pointer);
    expect(_seen!.blurAllowed, isTrue);
  });

  _case('tv flag: tv, remote, no blur', TargetPlatform.android, (tester) async {
    await _pump(tester, const Size(960, 540), tv: true);
    expect(_seen!.formFactor, FormFactor.tv);
    expect(_seen!.inputMode, InputMode.remote);
    expect(_seen!.blurAllowed, isFalse);
  });

  _case(
    'desktop: hover, arrow key, touch each rebuild once',
    TargetPlatform.macOS,
    (tester) async {
      await _pump(tester, const Size(1280, 800));
      expect(_seen!.inputMode, InputMode.pointer);

      // Switch away from the initial mode first so hover is a real change.
      await simulateKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_seen!.inputMode, InputMode.keyboard);
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowDown);

      var before = _builds;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(10, 10));
      await mouse.moveTo(const Offset(20, 20));
      await tester.pump();
      expect(_seen!.inputMode, InputMode.pointer);
      expect(_builds, before + 1);
      await mouse.moveTo(const Offset(30, 30));
      await tester.pump();
      expect(_builds, before + 1, reason: 'same mode must not rebuild');

      before = _builds;
      await simulateKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_seen!.inputMode, InputMode.keyboard);
      expect(_builds, before + 1);
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowDown);

      before = _builds;
      final touch = await tester.startGesture(const Offset(5, 5));
      await tester.pump();
      expect(_seen!.inputMode, InputMode.touch);
      expect(_builds, before + 1);
      await touch.up();
    },
  );

  _case('tv: touch and mouse leave remote unchanged', TargetPlatform.android, (
    tester,
  ) async {
    await _pump(tester, const Size(960, 540), tv: true);
    final touch = await tester.startGesture(const Offset(5, 5));
    await touch.up();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 10));
    await mouse.moveTo(const Offset(20, 20));
    await tester.pump();
    expect(_seen!.inputMode, InputMode.remote);
  });

  _case('opaque accessibility: no blur on desktop', TargetPlatform.macOS, (
    tester,
  ) async {
    await _pump(tester, const Size(1280, 800), reduceTransparency: true);
    expect(_seen!.formFactor, FormFactor.desktop);
    expect(_seen!.blurAllowed, isFalse);
  });
}
