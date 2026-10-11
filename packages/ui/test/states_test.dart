import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [AppStrings.delegate],
  theme: AppTheme.dark(tv: false),
  home: child,
);

final class _UnknownFailure extends AppFailure {
  const _UnknownFailure()
    : super(code: 'future.failure.code', message: 'future failure');
}

void main() {
  testWidgets('loading and empty states render inline and full-screen', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(const LoadingView()));
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    await tester.pumpWidget(_app(const LoadingView(fullScreen: true)));
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    handle.dispose();

    var actionCount = 0;
    await tester.pumpWidget(
      _app(
        EmptyView(
          headline: 'Empty',
          body: 'Nothing is available.',
          action: TextButton(
            onPressed: () => actionCount++,
            child: const Text('Retry'),
          ),
        ),
      ),
    );
    expect(find.text('Empty'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(actionCount, 1);
    await tester.pumpWidget(
      _app(const EmptyView(headline: 'Full empty', fullScreen: true)),
    );
    expect(find.text('Full empty'), findsOneWidget);
  });

  testWidgets('error state reveals code and retries once', (tester) async {
    var retries = 0;
    final logger = MemoryLogger();
    await tester.pumpWidget(
      _app(
        ErrorView(
          failure: const _UnknownFailure(),
          logger: logger,
          onRetry: () => retries++,
        ),
      ),
    );
    expect(find.textContaining('future.failure.code'), findsOneWidget);
    expect(logger.records, hasLength(1));
    expect(logger.records.single.level, LogLevel.warn);
    await tester.tap(find.text('Show error code'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('error-code-detail')),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });
}
