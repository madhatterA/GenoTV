import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

void main() {
  testWidgets('countdown pauses, resumes, and plays next once', (tester) async {
    var plays = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: PostVideoOverlay(
          nextTitle: 'Next episode',
          countdown: const Duration(seconds: 3),
          onPlayNext: () => plays++,
          onDismiss: () {},
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('countdown-toggle')));
    await tester.pump(const Duration(seconds: 4));
    expect(plays, 0);
    await tester.tap(find.byKey(const ValueKey('countdown-toggle')));
    await tester.pump(const Duration(seconds: 2));
    expect(plays, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(plays, 1);
  });

  testWidgets('Back cancels countdown before dismissing', (tester) async {
    var dismissed = 0;
    final key = GlobalKey<PostVideoOverlayState>();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: PostVideoOverlay(
          key: key,
          nextTitle: 'Next episode',
          onPlayNext: () {},
          onDismiss: () => dismissed++,
        ),
      ),
    );
    key.currentState!.handleBack();
    await tester.pump();
    expect(dismissed, 0);
    key.currentState!.handleBack();
    expect(dismissed, 1);
  });

  testWidgets('canceled countdown cannot resume or auto-play', (tester) async {
    var plays = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: PostVideoOverlay(
          nextTitle: 'Next episode',
          countdown: const Duration(seconds: 2),
          onPlayNext: () => plays++,
          onDismiss: () {},
        ),
      ),
    );
    await tester.tap(find.text('Cancel countdown'));
    await tester.pump();
    expect(find.byTooltip('Countdown canceled'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(plays, 0);
  });

  testWidgets('loading, retry, season, and show actions stay distinct', (
    tester,
  ) async {
    var next = 0;
    var retry = 0;
    var season = 0;
    var show = 0;
    Widget overlay({bool loading = false, String? error}) => MaterialApp(
      localizationsDelegates: const [AppStrings.delegate],
      theme: AppTheme.dark(tv: false),
      home: PostVideoOverlay(
        nextTitle: 'Next episode',
        isLoading: loading,
        errorMessage: error,
        onRetry: () => retry++,
        onPlayNext: () => next++,
        onDismiss: () {},
        onOpenSeason: () => season++,
        onOpenShow: () => show++,
      ),
    );
    await tester.pumpWidget(overlay(loading: true));
    await tester.pump(const Duration(milliseconds: 1));
    expect(
      tester
          .widget<ElevatedButton>(
            find.byKey(const ValueKey('post-video-play-next')),
          )
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(overlay(error: 'Unavailable'));
    await tester.tap(find.text('Retry'));
    expect(retry, 1);
    await tester.pumpWidget(overlay());
    await tester.tap(find.text('Season'));
    await tester.tap(find.text('Show'));
    expect((next, season, show), (0, 1, 1));
  });

  testWidgets('tap and double tap are exclusive; center double does nothing', (
    tester,
  ) async {
    var toggles = 0;
    var left = 0;
    var right = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: Scaffold(
          body: PlayerGestureSurface(
            chromeVisible: true,
            onToggleChrome: () => toggles++,
            onRevealChrome: () {},
            onPlayPause: () {},
            onSeekBackward: () => left++,
            onSeekForward: () => right++,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(40, 100));
    await tester.pump(const Duration(milliseconds: 350));
    expect(toggles, 1);
    await tester.tapAt(const Offset(40, 100));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(40, 100));
    await tester.pump(const Duration(milliseconds: 350));
    expect(left, 1);
    expect(toggles, 1);
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final center = Offset(size.width / 2, 100);
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 350));
    expect(toggles, 1);
    expect(right, 0);
    await tester.dragFrom(const Offset(40, 100), const Offset(100, 0));
    await tester.pump(const Duration(milliseconds: 350));
    expect(toggles, 1);
    expect(left, 1);
  });

  testWidgets('space controls playback and hidden arrows reveal chrome', (
    tester,
  ) async {
    var plays = 0;
    var reveals = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: PlayerGestureSurface(
          chromeVisible: false,
          onToggleChrome: () {},
          onRevealChrome: () => reveals++,
          onPlayPause: () => plays++,
          onSeekBackward: () {},
          onSeekForward: () {},
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(plays, 1);
    expect(reveals, 1);
  });
}
