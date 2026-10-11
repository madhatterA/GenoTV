import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/surface_size.dart';

Widget _host(
  ConnectionOutageController controller,
  Future<void> Function() retry,
) => MaterialApp(
  localizationsDelegates: const [AppStrings.delegate],
  theme: AppTheme.dark(tv: false),
  home: Scaffold(
    body: Column(
      children: <Widget>[
        ConnectionOutageBanner(controller: controller, onRetry: retry),
        const Expanded(child: Center(child: Text('Home'))),
      ],
    ),
  ),
);

Widget _shell(ConnectionOutageController controller, VoidCallback onExit) =>
    MaterialApp(
      localizationsDelegates: const [AppStrings.delegate],
      theme: AppTheme.dark(tv: false),
      home: AppShell(
        activeId: 'home',
        onExitRequested: onExit,
        destinations: <AppDestination>[
          AppDestination(
            id: 'home',
            label: 'Home',
            icon: Icons.home,
            builder: (_) => Column(
              children: <Widget>[
                ConnectionOutageBanner(
                  controller: controller,
                  onRetry: () async {},
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
          AppDestination(
            id: 'other',
            label: 'Other',
            icon: Icons.settings,
            builder: (_) => const SizedBox(),
          ),
        ],
      ),
    );

void main() {
  test(
    'Retry logs the original failure and stack while retaining outage state',
    () async {
      final logger = MemoryLogger();
      final controller = ConnectionOutageController(logger: logger);
      addTearDown(controller.dispose);
      controller.updateConnection(healthy: false);
      final error = StateError('offline');
      final stack = StackTrace.fromString('original retry stack');
      await controller.retry(() => Future<void>.error(error, stack));
      expect(logger.records, hasLength(1));
      final record = logger.records.single;
      expect(record.level, LogLevel.error);
      expect(record.message, 'Connection outage retry failed');
      expect(record.error, same(error));
      expect(record.stack, same(stack));
      expect(controller.retryFailed, isTrue);
      expect(controller.retrying, isFalse);
      expect(controller.isDown, isTrue);
      expect(controller.visible, isTrue);
    },
  );

  testWidgets(
    'shell Back dismisses its active outage before exit, other tabs are unaffected',
    (tester) async {
      await setLogicalSize(tester, const Size(400, 800));
      final controller = ConnectionOutageController();
      addTearDown(controller.dispose);
      var exits = 0;
      await tester.pumpWidget(_shell(controller, () => exits++));
      controller.updateConnection(healthy: false);
      await tester.pump();
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(controller.visible, isFalse);
      expect(controller.isDown, isTrue);
      expect(exits, 0);
      await tester.binding.handlePopRoute();
      expect(exits, 1);
      controller.updateConnection(healthy: true);
      controller.updateConnection(healthy: false);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('menu-pill')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('menu-item-other')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      expect(exits, 2);
      expect(controller.visible, isTrue);
    },
  );

  testWidgets('healthy down down recover down shows exactly two alerts', (
    tester,
  ) async {
    final controller = ConnectionOutageController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller, () async {}));
    var shown = 0;
    expect(find.byType(EmptyView), findsNothing);
    controller.updateConnection(healthy: false);
    await tester.pump();
    shown += find.byType(EmptyView).evaluate().length;
    controller.dismiss();
    controller.updateConnection(healthy: false);
    await tester.pump();
    expect(find.byType(EmptyView), findsNothing);
    expect(controller.isDown, isTrue);
    controller.updateConnection(healthy: true);
    await tester.pump();
    controller.updateConnection(healthy: false);
    await tester.pump();
    shown += find.byType(EmptyView).evaluate().length;
    expect(shown, 2);
    expect(controller.outageEpoch, 2);
    controller.updateConnection(healthy: true);
    await tester.pump();
    expect(find.byType(EmptyView), findsNothing);
  });

  testWidgets('Back and Escape dismiss without resetting the outage', (
    tester,
  ) async {
    final controller = ConnectionOutageController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller, () async {}));
    controller.updateConnection(healthy: false);
    await tester.pump();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(controller.visible, isFalse);
    controller.updateConnection(healthy: false);
    await tester.pump();
    expect(find.byType(EmptyView), findsNothing);
    controller.updateConnection(healthy: true);
    controller.updateConnection(healthy: false);
    await tester.pump();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(EmptyView), findsNothing);
    expect(controller.isDown, isTrue);
  });

  testWidgets(
    'keyboard Retry calls caller once, shows progress and failure, then clears',
    (tester) async {
      final controller = ConnectionOutageController();
      addTearDown(controller.dispose);
      var calls = 0;
      var result = Completer<void>();
      await tester.pumpWidget(
        _host(controller, () {
          calls++;
          return result.future;
        }),
      );
      controller.updateConnection(healthy: false);
      await tester.pump();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(calls, 1);
      expect(find.text('Reconnecting…'), findsOneWidget);
      expect(find.byType(OrbLoader), findsOneWidget);
      await controller.retry(() async {
        calls++;
      });
      expect(calls, 1);
      result.completeError(StateError('private network detail'));
      await tester.pump();
      expect(find.text("Still offline. Try again."), findsOneWidget);
      expect(find.textContaining('private network detail'), findsNothing);
      expect(controller.isDown, isTrue);
      result = Completer<void>();
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(calls, 2);
      result.complete();
      await tester.pump();
      expect(find.byType(EmptyView), findsNothing);
      expect(controller.isDown, isFalse);
    },
  );

  test(
    'stale retry cannot clear a new outage or notify after disposal',
    () async {
      final controller = ConnectionOutageController();
      controller.updateConnection(healthy: false);
      final result = Completer<void>();
      final pending = controller.retry(() => result.future);
      controller.updateConnection(healthy: true);
      controller.updateConnection(healthy: false);
      result.complete();
      await pending;
      expect(controller.visible, isTrue);
      expect(controller.isDown, isTrue);
      final disposedResult = Completer<void>();
      final disposedRetry = controller.retry(() => disposedResult.future);
      controller.dispose();
      disposedResult.completeError(StateError('closed'));
      await disposedRetry;
    },
  );

  testWidgets('dismiss during Retry and its failure never reopens the banner', (
    tester,
  ) async {
    final controller = ConnectionOutageController();
    addTearDown(controller.dispose);
    final result = Completer<void>();
    await tester.pumpWidget(_host(controller, () => result.future));
    controller.updateConnection(healthy: false);
    await tester.pump();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.tap(find.text('Dismiss'));
    await tester.pump();
    result.completeError(StateError('offline'));
    await tester.pump();
    controller.updateConnection(healthy: false);
    await tester.pump();
    expect(find.byType(EmptyView), findsNothing);
    expect(controller.isDown, isTrue);
  });

  testWidgets('offline message is a live region with accessible actions', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final controller = ConnectionOutageController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller, () async {}));
    controller.updateConnection(healthy: false);
    await tester.pump();
    final node = tester.getSemantics(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.liveRegion == true,
      ),
    );
    expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    for (final label in ['Retry', 'Dismiss']) {
      expect(
        tester
            .getSemantics(find.widgetWithText(AppButton, label))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
    }
    expect(
      tester.getSize(find.widgetWithText(AppButton, 'Retry')).height,
      greaterThanOrEqualTo(44),
    );
    handle.dispose();
  });

  for (final width in <double>[400, 1400]) {
    testWidgets('offline banner golden at ${width.toInt()}', (tester) async {
      await setLogicalSize(tester, Size(width, 800));
      final controller = ConnectionOutageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(controller, () async {}));
      controller.updateConnection(healthy: false);
      await tester.pump();
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/connection_outage_${width.toInt()}.png'),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
