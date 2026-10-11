import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

void main() {
  group('InputRouter hold vs tap', () {
    late List<UiCommand> commands;
    late InputRouter router;

    setUp(() {
      commands = <UiCommand>[];
      router = InputRouter(onCommand: commands.add);
    });

    tearDown(() => router.dispose());

    testWidgets('release at 399ms emits a tap (step seek), not a hold', (
      tester,
    ) async {
      router.handleKeyEvent(
        LogicalKeyboardKey.arrowRight,
        down: true,
        timestamp: Duration.zero,
      );
      await tester.pump(const Duration(milliseconds: 399));
      router.handleKeyEvent(
        LogicalKeyboardKey.arrowRight,
        down: false,
        timestamp: const Duration(milliseconds: 399),
      );
      // Let the 50ms seek coalescer flush.
      await tester.pump(const Duration(milliseconds: 60));
      expect(commands, hasLength(1));
      expect(commands.single.type, UiCommandType.stepSeekForward);
    });

    testWidgets('holding past 400ms emits a hold and suppresses the tap', (
      tester,
    ) async {
      router.handleKeyEvent(
        LogicalKeyboardKey.arrowRight,
        down: true,
        timestamp: Duration.zero,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(commands, hasLength(1));
      expect(commands.single.type, UiCommandType.scrubNudgeForward);

      router.handleKeyEvent(
        LogicalKeyboardKey.arrowRight,
        down: false,
        timestamp: const Duration(milliseconds: 450),
      );
      await tester.pump(const Duration(milliseconds: 60));
      // Never emit tap after a completed hold.
      expect(commands, hasLength(1));
    });

    testWidgets(
      'key repeat (down while already down) never restarts the hold timer',
      (tester) async {
        router.handleKeyEvent(
          LogicalKeyboardKey.arrowRight,
          down: true,
          timestamp: Duration.zero,
        );
        await tester.pump(const Duration(milliseconds: 300));
        // Simulated OS auto-repeat: another down for the same still-held key.
        router.handleKeyEvent(
          LogicalKeyboardKey.arrowRight,
          down: true,
          timestamp: const Duration(milliseconds: 300),
        );
        await tester.pump(const Duration(milliseconds: 100));
        // If the repeat had restarted the timer, the hold would not have
        // fired yet at t=400ms from the ORIGINAL down.
        expect(commands, hasLength(1));
        expect(commands.single.type, UiCommandType.scrubNudgeForward);
      },
    );

    testWidgets(
      'opposite direction press is tracked independently, not merged',
      (tester) async {
        router.handleKeyEvent(
          LogicalKeyboardKey.arrowRight,
          down: true,
          timestamp: Duration.zero,
        );
        router.handleKeyEvent(
          LogicalKeyboardKey.arrowLeft,
          down: true,
          timestamp: const Duration(milliseconds: 10),
        );
        router.handleKeyEvent(
          LogicalKeyboardKey.arrowRight,
          down: false,
          timestamp: const Duration(milliseconds: 20),
        );
        router.handleKeyEvent(
          LogicalKeyboardKey.arrowLeft,
          down: false,
          timestamp: const Duration(milliseconds: 30),
        );
        await tester.pump(const Duration(milliseconds: 60));
        expect(commands, hasLength(2));
        expect(commands[0].type, UiCommandType.stepSeekForward);
        expect(commands[1].type, UiCommandType.stepSeekBackward);
      },
    );
  });

  group('InputRouter dedupe windows', () {
    testWidgets(
      'transport dedupe (350ms): 349ms apart dropped, 351ms apart kept',
      (tester) async {
        final commands = <UiCommand>[];
        final router = InputRouter(onCommand: commands.add);
        router.emit(
          UiCommandType.playPause,
          source: CommandSource.keyboard,
          timestamp: Duration.zero,
        );
        router.emit(
          UiCommandType.playPause,
          source: CommandSource.remote,
          timestamp: const Duration(milliseconds: 349),
        );
        expect(
          commands,
          hasLength(1),
          reason: '349ms apart is inside the 350ms window',
        );
        router.emit(
          UiCommandType.playPause,
          source: CommandSource.remote,
          timestamp: const Duration(milliseconds: 700),
        );
        expect(
          commands,
          hasLength(2),
          reason: '351ms after the surviving emission clears the window',
        );
        router.dispose();
      },
    );

    testWidgets('action dedupe (80ms) boundary at 79ms vs 81ms', (
      tester,
    ) async {
      final commands = <UiCommand>[];
      final router = InputRouter(onCommand: commands.add);
      router.emit(
        UiCommandType.info,
        source: CommandSource.keyboard,
        timestamp: Duration.zero,
      );
      router.emit(
        UiCommandType.info,
        source: CommandSource.keyboard,
        timestamp: const Duration(milliseconds: 79),
      );
      expect(commands, hasLength(1));
      router.emit(
        UiCommandType.info,
        source: CommandSource.keyboard,
        timestamp: const Duration(milliseconds: 161),
      );
      expect(commands, hasLength(2));
      router.dispose();
    });

    testWidgets(
      'cross-source scrub-nudge dedupe (250ms) collapses two sources into one',
      (tester) async {
        final commands = <UiCommand>[];
        final router = InputRouter(onCommand: commands.add);
        router.emit(
          UiCommandType.scrubNudgeForward,
          source: CommandSource.gamepad,
          timestamp: Duration.zero,
        );
        router.emit(
          UiCommandType.scrubNudgeForward,
          source: CommandSource.remote,
          timestamp: const Duration(milliseconds: 200),
        );
        expect(
          commands,
          hasLength(1),
          reason: 'two sources reporting the same hold within 250ms coalesce to one',
        );
        router.dispose();
      },
    );

    testWidgets('directional movement is never deduped, however fast', (
      tester,
    ) async {
      final commands = <UiCommand>[];
      final router = InputRouter(onCommand: commands.add);
      for (var i = 0; i < 5; i++) {
        router.emit(
          UiCommandType.directionDown,
          source: CommandSource.keyboard,
          timestamp: const Duration(milliseconds: 1),
        );
      }
      expect(commands, hasLength(5));
      router.dispose();
    });
  });

  group('InputRouter seek coalescing', () {
    testWidgets(
      'a burst of taps inside 50ms coalesces to one command with a repeat count',
      (tester) async {
        final commands = <UiCommand>[];
        final router = InputRouter(onCommand: commands.add);
        for (var i = 0; i < 3; i++) {
          final t = Duration(milliseconds: i * 10);
          router.handleKeyEvent(
            LogicalKeyboardKey.arrowRight,
            down: true,
            timestamp: t,
          );
          router.handleKeyEvent(
            LogicalKeyboardKey.arrowRight,
            down: false,
            timestamp: t + const Duration(milliseconds: 5),
          );
        }
        await tester.pump(const Duration(milliseconds: 60));
        expect(commands, hasLength(1));
        expect(commands.single.repeatCount, 3);
        router.dispose();
      },
    );
  });

  group('InputRouter key mapping and pointer/touch parity', () {
    testWidgets(
      'Enter and a pointer tap both emit selectDown/selectUp for the same action',
      (tester) async {
        final commands = <UiCommand>[];
        final router = InputRouter(onCommand: commands.add);
        router.handleKeyEvent(
          LogicalKeyboardKey.enter,
          down: true,
          timestamp: Duration.zero,
        );
        router.handleKeyEvent(
          LogicalKeyboardKey.enter,
          down: false,
          timestamp: const Duration(milliseconds: 50),
        );
        router.emit(
          UiCommandType.selectDown,
          source: CommandSource.touch,
          timestamp: const Duration(seconds: 1),
        );
        router.emit(
          UiCommandType.selectUp,
          source: CommandSource.touch,
          timestamp: const Duration(seconds: 1, milliseconds: 50),
        );
        expect(commands.map((c) => c.type), <UiCommandType>[
          UiCommandType.selectDown,
          UiCommandType.selectUp,
          UiCommandType.selectDown,
          UiCommandType.selectUp,
        ]);
        expect(commands[0].source, CommandSource.keyboard);
        expect(commands[2].source, CommandSource.touch);
        router.dispose();
      },
    );

    testWidgets('J/L map to jump seek, media key maps to transport', (
      tester,
    ) async {
      final commands = <UiCommand>[];
      final router = InputRouter(onCommand: commands.add);
      router.handleKeyEvent(
        LogicalKeyboardKey.keyJ,
        down: true,
        timestamp: Duration.zero,
      );
      router.handleKeyEvent(
        LogicalKeyboardKey.keyL,
        down: true,
        timestamp: const Duration(milliseconds: 500),
      );
      router.handleKeyEvent(
        LogicalKeyboardKey.mediaPlayPause,
        down: true,
        timestamp: const Duration(milliseconds: 1000),
      );
      expect(commands.map((c) => c.type), <UiCommandType>[
        UiCommandType.jumpSeekBackward,
        UiCommandType.jumpSeekForward,
        UiCommandType.playPause,
      ]);
      router.dispose();
    });
  });

  group('InputRouter Back priority', () {
    testWidgets(
      'overlay-first: the newest registered handler gets first refusal',
      (tester) async {
        final dispatcher = BackDispatcher();
        final order = <String>[];
        final unregisterPage = dispatcher.register(() {
          order.add('page');
          return true;
        });
        dispatcher.register(() {
          order.add('overlay');
          return true;
        });
        final commands = <UiCommand>[];
        final router = InputRouter(
          onCommand: commands.add,
          backDispatcher: dispatcher,
        );

        router.handleKeyEvent(
          LogicalKeyboardKey.escape,
          down: true,
          timestamp: Duration.zero,
        );
        expect(order, <String>['overlay']);
        expect(
          commands,
          isEmpty,
          reason: 'a consumed Back never reaches onCommand',
        );

        unregisterPage();
        router.emit(
          UiCommandType.menuBack,
          source: CommandSource.remote,
          timestamp: const Duration(seconds: 2),
        );
        router.dispose();
      },
    );

    testWidgets('menuBack reaches onCommand when no handler consumes it', (
      tester,
    ) async {
      final dispatcher = BackDispatcher();
      final commands = <UiCommand>[];
      final router = InputRouter(
        onCommand: commands.add,
        backDispatcher: dispatcher,
      );
      router.handleKeyEvent(
        LogicalKeyboardKey.escape,
        down: true,
        timestamp: Duration.zero,
      );
      expect(commands.single.type, UiCommandType.menuBack);
      router.dispose();
    });
  });

  group('FocusableAction', () {
    Widget app(Widget child) => MaterialApp(
      localizationsDelegates: const [AppStrings.delegate],
      theme: AppTheme.dark(tv: false),
      home: Center(child: child),
    );

    testWidgets('activates on tap and reports semantics', (tester) async {
      var activated = 0;
      await tester.pumpWidget(
        app(
          FocusableAction(
            semanticLabel: 'play',
            onActivate: () => activated++,
            child: const SizedBox(width: 20, height: 20),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(FocusableAction)).width,
        greaterThanOrEqualTo(44),
      );
      expect(
        tester.getSize(find.byType(FocusableAction)).height,
        greaterThanOrEqualTo(44),
      );
      await tester.tap(find.byType(FocusableAction));
      await tester.pump();
      expect(activated, 1);
      expect(find.bySemanticsLabel('play'), findsOneWidget);
    });

    testWidgets(
      'disabled control never activates and is skipped by traversal',
      (tester) async {
        var activated = 0;
        await tester.pumpWidget(
          app(
            FocusableAction(
              enabled: false,
              onActivate: () => activated++,
              child: const SizedBox(width: 20, height: 20),
            ),
          ),
        );
        await tester.tap(find.byType(FocusableAction));
        await tester.pump();
        expect(activated, 0);
        final focusWidget = tester.widget<Focus>(
          find.descendant(
            of: find.byType(FocusableAction),
            matching: find.byType(Focus),
          ),
        );
        expect(focusWidget.canRequestFocus, isFalse);
      },
    );

    testWidgets(
      'press-down scales toward pressScale without changing layout size',
      (tester) async {
        await tester.pumpWidget(
          app(const FocusableAction(child: SizedBox(width: 60, height: 60))),
        );
        final sizeBefore = tester.getSize(find.byType(FocusableAction));
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(FocusableAction)),
        );
        await tester.pump(const Duration(milliseconds: 160));
        await tester.pump(const Duration(milliseconds: 160));
        expect(
          tester
              .widget<ScaleTransition>(
                find.descendant(
                  of: find.byType(FocusableAction),
                  matching: find.byType(ScaleTransition),
                ),
              )
              .scale
              .value,
          closeTo(0.97, 0.0001),
        );
        final sizeDuringPress = tester.getSize(find.byType(FocusableAction));
        expect(
          sizeDuringPress,
          sizeBefore,
          reason: 'a focus/press scale must not change layout',
        );
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 160));
      },
    );
  });

  group('RowFocusPolicy', () {
    test('restoration keeps the same id after items are appended', () {
      final policy = RowFocusPolicy(<String>['a', 'b', 'c']);
      policy.select('b');
      policy.updateItems(<String>['a', 'b', 'c', 'd']);
      expect(policy.selectedId, 'b');
      expect(policy.selectedIndex, 1);
    });

    test('removal of the selected item restores the nearest surviving neighbor by old index', () {
      final policy = RowFocusPolicy(<String>['a', 'b', 'c', 'd']);
      policy.select('b');
      // 'b' (old index 1) removed; nearest surviving neighbor at old index 1
      // in the new list is 'c'.
      policy.updateItems(<String>['a', 'c', 'd']);
      expect(policy.selectedId, 'c');
    });

    test(
      'removal of the last item restoration never overruns the new list',
      () {
        final policy = RowFocusPolicy(<String>['a', 'b', 'c']);
        policy.select('c');
        policy.updateItems(<String>['a', 'b']);
        expect(policy.selectedId, 'b');
      },
    );

    test(
      'moveFocus advances by identity and refuses to wrap past either end',
      () {
        final policy = RowFocusPolicy(<String>['a', 'b', 'c']);
        policy.select('a');
        expect(policy.moveFocus(false), isFalse);
        expect(policy.selectedId, 'a');
        expect(policy.moveFocus(true), isTrue);
        expect(policy.selectedId, 'b');
        expect(policy.moveFocus(true), isTrue);
        expect(policy.selectedId, 'c');
        expect(policy.moveFocus(true), isFalse);
        expect(policy.selectedId, 'c');
      },
    );

    test('targetScrollOffset moves in exact multiples of the item pitch', () {
      final policy = RowFocusPolicy(<String>['a', 'b', 'c']);
      policy.select('c');
      expect(policy.targetScrollOffset(304), 608);
    });
  });
}
