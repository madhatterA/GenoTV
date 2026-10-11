import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/surface_size.dart';

const _viewports = <Size>[
  Size(400, 800),
  Size(844, 390),
  Size(1280, 800),
  Size(1920, 1080),
];

Widget _card(PlatformCapabilities caps, List<String> taps) => MaterialApp(
  localizationsDelegates: const [AppStrings.delegate],
  theme: AppTheme.dark(tv: false),
  home: AdaptiveBehavior(
    capabilities: caps,
    child: Scaffold(
      body: Center(
        child: FocusableCard(
          surfaceId: 's',
          itemId: 'card',
          memory: FocusMemory(),
          onTap: () => taps.add('tap'),
          semanticLabel: 'Card',
          child: const Text('Card'),
        ),
      ),
    ),
  ),
);

double _scale(WidgetTester tester) => tester
    .widget<ScaleTransition>(
      find.descendant(
        of: find.byType(FocusableCard),
        matching: find.byType(ScaleTransition),
      ),
    )
    .scale
    .value;

Future<void> _hover(WidgetTester tester, TestGesture mouse) async {
  await mouse.moveTo(tester.getCenter(find.byType(FocusableCard)));
  await tester.pump();
}

void main() {
  for (final size in _viewports) {
    testWidgets(
      'size classes and default player form factor at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        await setLogicalSize(tester, size);
        late (bool, bool, bool, FormFactor) seen;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [AppStrings.delegate],
            home: Builder(
              builder: (context) {
                seen = (
                  AdaptiveBehavior.isCompactShortestSide(context),
                  AdaptiveBehavior.isShortHeight(context),
                  AdaptiveBehavior.isNarrowWidth(context),
                  AdaptiveBehavior.of(context).formFactor,
                );
                return const SizedBox();
              },
            ),
          ),
        );
        final phone = size.shortestSide < 600;
        expect(seen, (
          phone,
          size.height < 500,
          size.width < 700,
          phone ? FormFactor.phone : FormFactor.desktop,
        ));
      },
    );
  }

  testWidgets('hover scales a card only while the last input was a pointer', (
    tester,
  ) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await tester.pumpWidget(_card(const PlatformCapabilities(), <String>[]));
    expect(_scale(tester), 1);
    await _hover(tester, mouse);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(_scale(tester), closeTo(1.03, 0.0001));

    final touch = await tester.startGesture(const Offset(1, 1));
    await touch.up();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(_scale(tester), 1);
  });

  testWidgets(
    'touch tap, pointer click and keyboard Enter/Select run the same command',
    (tester) async {
      var activated = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: false),
          home: Center(
            child: FocusableAction(
              semanticLabel: 'play',
              onActivate: () => activated++,
              child: const SizedBox(width: 20, height: 20),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(FocusableAction)); // touch
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(
        location: tester.getCenter(find.byType(FocusableAction)),
      );
      await mouse.down(tester.getCenter(find.byType(FocusableAction)));
      await mouse.up();
      await mouse.removePointer();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select); // D-pad centre
      await tester.pump();
      expect(activated, 4);
    },
  );

  test('keyboard Enter and D-pad Select emit identical semantic commands', () {
    final types = <List<UiCommandType>>[];
    for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.select]) {
      final commands = <UiCommand>[];
      final router = InputRouter(onCommand: commands.add);
      router.handleKeyEvent(key, down: true, timestamp: Duration.zero);
      router.handleKeyEvent(
        key,
        down: false,
        timestamp: const Duration(milliseconds: 50),
      );
      types.add(commands.map((c) => c.type).toList());
      router.dispose();
    }
    expect(types[0], [UiCommandType.selectDown, UiCommandType.selectUp]);
    expect(types[1], types[0]);
  });

  testWidgets('disabled action is neither tappable nor keyboard-activatable', (
    tester,
  ) async {
    var activated = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: Center(
          child: FocusableAction(
            enabled: false,
            onActivate: () => activated++,
            child: const SizedBox(width: 20, height: 20),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(FocusableAction));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(activated, 0);
  });

  test(
    'static checks: forbidden imports, direct platform/I/O, skipped tests',
    () {
      String code(File f) => f
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      final lib = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      final forbidden = RegExp(
        r"package:(playback|transport|platform_services|persistence)|media_kit|sqlite|drift/|dart:io|dart:html|\bPlatform\.|defaultTargetPlatform|kIsWeb|HttpClient|\bFile\(|\bprint\(|debugPrint\(",
      );
      // DESIGN_SPEC §6.1: `lib/src/platform/` is the one place allowed to read defaultTargetPlatform.
      // The backup-route image loader is the one widget file that owns real
      // network I/O (its own HttpClient, owner 2026-10-10 backup proxy).
      const networkImageLoader = 'lib/src/components/routed_network_image.dart';
      final libHits = [
        for (final f in lib)
          if (f.path != networkImageLoader &&
              (f.path.contains('lib/src/platform/')
                      ? RegExp(
                          forbidden.pattern.replaceAll(
                            'defaultTargetPlatform|',
                            '',
                          ),
                        )
                      : forbidden)
                  .hasMatch(code(f)))
            f.path,
      ];
      expect(libHits, isEmpty);
      final tests = Directory('test')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) =>
                f.path.endsWith('_test.dart') &&
                !f.path.endsWith('platform_adaptation_test.dart'),
          );
      final skipHits = [
        for (final f in tests)
          if (RegExp(r'\bskip:|@Skip').hasMatch(code(f))) f.path,
      ];
      expect(skipHits, isEmpty);
    },
  );

  // Ratchet: counts outside lib/src/theme may only fall. Lower the constants when
  // you remove raw values; never raise them (use a token instead).
  test('raw color and duration literals outside theme tokens never rise', () {
    const colorBaseline = 154;
    const durationBaseline = 53;
    final color = RegExp(r'Color\(0x|\bColors\.(?!transparent)[a-z]');
    final duration = RegExp(
      r'Duration\(\s*(?:days|hours|minutes|seconds|milliseconds|microseconds)\s*:\s*-?\d',
    );
    var colors = 0;
    var durations = 0;
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.contains('/theme/')) continue;
      for (final line in f.readAsLinesSync()) {
        if (line.trimLeft().startsWith('//')) continue;
        colors += color.allMatches(line).length;
        durations += duration.allMatches(line).length;
      }
    }
    expect(
      colors,
      lessThanOrEqualTo(colorBaseline),
      reason: 'raw colors now $colors',
    );
    expect(
      durations,
      lessThanOrEqualTo(durationBaseline),
      reason: 'raw durations now $durations',
    );
  });
}
