import 'dart:convert';
import 'dart:io';

import 'package:contracts/contracts.dart' hide PlatformCapabilities;
import 'package:contracts/fakes.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/src/settings/settings_controls.dart';
import 'package:ui/ui.dart';

import '../support/fixture_artwork.dart';
import '../support/state_screen_registry.dart';

// DESIGN_SPEC §6.3 / §6.4 / §7.4 on the TV profile (960x540 @ dpr 2, remote
// mode). Every walk
// presses real keys and asserts the primary focus's contract key after each
// one. Widgets ch03 builds (hero Details, detail Like/Cast, filter chips,
// settings sections) are walked by the ch03 phases that build them; this
// file uses today's keys for those places.

final _log = <Map<String, Object?>>[];

/// The contract key of the primary focus: the first matching `ValueKey` on
/// the focus node's widget or one of its ancestors.
final _contract = RegExp(
  r'^(hero-focus-play|hero-focus-details|row-\d+-(item-\d+|see-all|arrow-left|arrow-right)|'
  r'menu-pill|menu-item-.+|top-search|top-back|grid-item-\d+|'
  r'detail-play-action|detail-trailer|detail-like|detail-watched-action|'
  r'detail-watchlist-action|detail-info-action|people-item-\d+|'
  r'detail-related-item-\d+|detail-trailers-item-\d+|season-chip-\d+|'
  r'episode-\d+|library-query|library-refresh|'
  r'section-.+|setting-.+|skip-forward-setting|verbose-logging-switch|'
  r'advanced-toggle|expert-toggle|search-field|'
  r'filter-chip-\d+|title-kind-.+)$',
);

String? _focusedKey() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  String? found;
  void check(Element element) {
    final key = element.widget.key;
    if (found == null &&
        key is ValueKey<String> &&
        _contract.hasMatch(key.value)) {
      found = key.value;
    }
  }

  check(context as Element);
  context.visitAncestorElements((ancestor) {
    check(ancestor);
    return found == null;
  });
  return found;
}

const _tvSize = Size(1920, 1080);

/// Android delivers the remote's Back as a system pop route (the key event
/// also arrives, but the pop is what the app acts on).
Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  int times = 1,
}) async {
  for (var i = 0; i < times; i++) {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }
}

/// Holds [key] down for [hold], with key repeats like a real remote, then
/// releases it.
Future<void> _hold(
  WidgetTester tester,
  LogicalKeyboardKey key,
  Duration hold,
) async {
  await tester.sendKeyDownEvent(key);
  for (
    var t = Duration.zero;
    t < hold;
    t += const Duration(milliseconds: 100)
  ) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyRepeatEvent(key);
  }
  await tester.sendKeyUpEvent(key);
  await tester.pumpAndSettle();
}

void _expectKey(String walk, String step, String expected) {
  final actual = _focusedKey();
  _log.add(<String, Object?>{
    'walk': walk,
    'step': step,
    'expected': expected,
    'actual': actual,
    'pass': actual == expected,
  });
  expect(actual, expected, reason: '$walk / $step');
}

void _expectThat(String walk, String step, bool pass, Object? actual) {
  _log.add(<String, Object?>{
    'walk': walk,
    'step': step,
    'expected': true,
    'actual': actual,
    'pass': pass,
  });
  expect(pass, isTrue, reason: '$walk / $step: $actual');
}

AppDestination _destination(String id, String label, WidgetBuilder builder) =>
    AppDestination(
      id: id,
      label: label,
      icon: PhosphorIconsRegular.house,
      activeIcon: PhosphorIconsFill.house,
      builder: builder,
    );

/// A TV shell showing [first] straight away (a TV has no keyboard to switch
/// into; the app opens in remote mode).
Future<void> _pump(
  WidgetTester tester,
  String first,
  Map<String, WidgetBuilder> pages,
) async {
  tester.view.physicalSize = _tvSize;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  final resolver = await loadFixtureArtworkResolver(tester);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppStrings.localizationsDelegates,
      supportedLocales: AppStrings.supportedLocales,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(tv: true),
      home: AdaptiveBehavior(
        capabilities: const PlatformCapabilities.directionalPad(),
        child: ArtworkResolverScope(
          resolver: resolver,
          child: AppShell(
            activeId: first,
            destinations: <AppDestination>[
              for (final entry in pages.entries)
                _destination(entry.key, entry.key, entry.value),
              if (!pages.containsKey('search'))
                _destination('search', 'search', (_) => const SizedBox()),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Rect _rect(WidgetTester tester, String key) =>
    tester.getRect(find.byKey(ValueKey<String>(key)).first);

double _offsetOf(WidgetTester tester, int row) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byWidgetPredicate(
              (w) => w is MediaRow && w.rowIndex == row,
            ),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position
    .pixels;

double _maxOf(WidgetTester tester, int row) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byWidgetPredicate(
              (w) => w is MediaRow && w.rowIndex == row,
            ),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position
    .maxScrollExtent;

/// Fixed-focus target: the item index times the pitch, clamped at the row end.
double _fixed(WidgetTester tester, int row, int index, double pitch) =>
    (index * pitch).clamp(0.0, _maxOf(tester, row));

bool get _panelOpen =>
    find.byKey(const ValueKey<String>('menu-panel')).evaluate().isNotEmpty;

void main() {
  tearDownAll(() {
    final dir = Directory.systemTemp.createTempSync('tv-keywalk-');
    try {
      File('${dir.path}/tv_steps.json')
          .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_log));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  for (final shelf in <bool>[false, true]) {
    testWidgets('${shelf ? 'Detail shelf' : 'Genres row'} title inset', (
      tester,
    ) async {
      final memory = FocusMemory();
      final items = keywalkHomeRows()[0].items;
      await _pump(tester, 'home', <String, WidgetBuilder>{
        'home': (_) => ListView(
          children: <Widget>[
            const SizedBox(height: 300),
            if (shelf)
              MediaShelf(
                title: 'Section title',
                items: items,
                memory: memory,
                autofocus: false,
                keyPrefix: 'section',
                onFocused: (_) {},
              )
            else
              MediaRow(
                title: 'Section title',
                items: items,
                memory: memory,
                onFocused: (_) {},
              ),
            const SizedBox(height: 600),
          ],
        ),
      });
      tester
          .widget<Focus>(
            find
                .byKey(
                  ValueKey<String>(shelf ? 'section-item-0' : 'row-0-item-0'),
                )
                .first,
          )
          .focusNode!
          .requestFocus();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      final title = tester.getRect(find.text('Section title'));
      expect(title.top, greaterThanOrEqualTo(88));
      expect(title.top, closeTo(88, 1));
      expect(_rect(tester, 'menu-pill').overlaps(title), isFalse);
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey<String>('top-scrim')),
            )
            .opacity,
        greaterThan(0),
      );
      // Moving horizontally keeps the page's title anchored.
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(
        tester.getRect(find.text('Section title')).top,
        closeTo(title.top, 1),
      );
    });
  }

  testWidgets('Detail cast section title inset', (tester) async {
    await _pump(tester, 'home', <String, WidgetBuilder>{
      'home': (_) => ListView(
        children: <Widget>[
          const SizedBox(height: 300),
          DetailSections(
            presentation: MovieDetailPresentation(
              item: keywalkHomeRows()[0].items[0],
              cast: const <CastMember>[CastMember(id: 1, name: 'Person')],
            ),
            memory: FocusMemory(),
            onCastTap: (_) {},
          ),
          const SizedBox(height: 600),
        ],
      ),
    });
    Focus.of(tester.element(find.text('Person'))).requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    final title = tester.getRect(find.text('Cast'));
    expect(title.top, closeTo(88, 1));
    expect(_rect(tester, 'menu-pill').overlaps(title), isFalse);
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey<String>('top-scrim')),
          )
          .opacity,
      greaterThan(0),
    );
  });

  testWidgets('Home walk', (tester) async {
    final model = HomeViewModel(
      rows: keywalkHomeRows(),
      firstDeferredSectionReady: true,
      secondDeferredSectionReady: true,
    );
    addTearDown(model.dispose);
    final related = <MediaItem>[];
    await _pump(tester, 'home', <String, WidgetBuilder>{
      'home': (context) => HomeScreen(
        viewModel: model,
        onSeeAll: (_) {},
        onItemTap: (item) => pushAndRestoreFocus<void>(
          Navigator.of(context),
          AppPageRoute<void>(
            builder: (_) => Material(
              child: MovieDetailScreen(
                presentation: MovieDetailPresentation(
                  item: item,
                  year: '2024',
                  summary: 'A journey through a changing world.',
                  related: related,
                ),
                onPlay: () {},
                onToggleWatched: () {},
                onInfo: () {},
                onRelatedTap: (_) {},
              ),
            ),
          ),
        ),
      ),
    });
    const w = 'home';
    _expectKey(w, '0 entry', 'hero-focus-play');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectKey(w, '1 Right to Details', 'hero-focus-details');
    final firstSlide = model.hero;
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectKey(
      w,
      '2 Right shows slide 2, focus on its Play',
      'hero-focus-play',
    );
    expect(model.hero, isNot(firstSlide), reason: 'slide 2 is showing');
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    _expectKey(
      w,
      '3 Left on the first hero button opens the panel',
      'menu-item-home',
    );
    _expectThat(w, '3 panel open', _panelOpen, _panelOpen);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectKey(w, '4 Right closes the panel', 'hero-focus-play');
    _expectThat(w, '4 panel closed', !_panelOpen, _panelOpen);

    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectKey(w, '5 Down', 'row-0-item-0');
    _expectThat(
      w,
      '5 row 0 offset 0',
      _offsetOf(tester, 0) == 0,
      _offsetOf(tester, 0),
    );
    final pitch =
        _rect(tester, 'row-0-item-1').left - _rect(tester, 'row-0-item-0').left;
    await _press(tester, LogicalKeyboardKey.arrowRight, times: 2);
    _expectKey(w, '6 Right x2', 'row-0-item-2');
    _expectThat(
      w,
      '6 row 0 fixed-focus offset = 2 x pitch',
      (_offsetOf(tester, 0) - _fixed(tester, 0, 2, pitch)).abs() < 1,
      <double>[_offsetOf(tester, 0), _fixed(tester, 0, 2, pitch)],
    );

    final fromX = _rect(tester, 'row-0-item-2').center.dx;
    await _press(tester, LogicalKeyboardKey.arrowDown);
    final title = tester.getRect(find.text(model.rows[1].title).first);
    final pill = _rect(tester, 'menu-pill');
    final scrim = tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey<String>('top-scrim')),
    );
    expect(
      <bool>[title.top >= 88, !pill.overlaps(title), scrim.opacity > 0],
      <bool>[true, true, true],
      reason: 'row 1 title=$title, pill=$pill, scrim=${scrim.opacity}',
    );
    final landed = _focusedKey()!;
    expect(landed, startsWith('row-1-item-'));
    var nearest = '';
    var best = double.infinity;
    for (var i = 0; i < 8; i++) {
      final finder = find.byKey(ValueKey<String>('row-1-item-$i'));
      if (finder.evaluate().isEmpty) continue;
      // The row scrolled to its fixed-focus slot after the move; undo that.
      final d =
          (tester.getRect(finder.first).center.dx +
                  _offsetOf(tester, 1) -
                  fromX)
              .abs();
      if (d < best) {
        best = d;
        nearest = 'row-1-item-$i';
      }
    }
    _expectKey(w, '7 Down lands on the nearest item', nearest);
    final index = int.parse(nearest.split('-').last);
    final pitch1 =
        _rect(tester, 'row-1-item-${index + 1}').left -
        _rect(tester, 'row-1-item-$index').left;
    _expectThat(
      w,
      '7 row 1 fixed-focus offset = index x pitch',
      (_offsetOf(tester, 1) - _fixed(tester, 1, index, pitch1)).abs() < 1,
      <double>[_offsetOf(tester, 1), index * pitch1, _maxOf(tester, 1), pitch1],
    );

    await _press(tester, LogicalKeyboardKey.arrowUp);
    _expectKey(w, '8 Up returns to the row memory', 'row-0-item-2');
    await _press(tester, LogicalKeyboardKey.arrowLeft, times: 2);
    _expectKey(w, '9 Left x2', 'row-0-item-0');
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    _expectThat(
      w,
      '9 Left at the line start opens the panel',
      _panelOpen,
      _panelOpen,
    );
    await _back(tester);
    _expectThat(w, '9 Back closes the panel', !_panelOpen, _panelOpen);
    _expectKey(w, '9 focus restored', 'row-0-item-0');

    await _press(tester, LogicalKeyboardKey.contextMenu);
    _expectThat(w, '10 Menu key opens the panel', _panelOpen, _panelOpen);
    await _back(tester);
    _expectThat(w, '10 Back closes the panel', !_panelOpen, _panelOpen);
    _expectKey(w, '10 focus restored', 'row-0-item-0');

    await _press(tester, LogicalKeyboardKey.arrowUp);
    _expectKey(w, '11 Up to the hero', 'hero-focus-play');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    _expectKey(w, '11 Up to the pill', 'menu-pill');
    await _press(tester, LogicalKeyboardKey.select);
    _expectThat(w, '11 Select opens the panel', _panelOpen, _panelOpen);
    await _back(tester);
    _expectKey(w, '11 Back restores the pill', 'menu-pill');

    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectKey(w, '11 Down returns to the hero', 'hero-focus-play');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectKey(w, '12 Down', 'row-0-item-0');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    final row1 = _focusedKey()!;
    expect(row1, startsWith('row-1-item-'));
    for (var i = 0; i < 8 && _focusedKey() != 'row-1-item-0'; i++) {
      await _press(tester, LogicalKeyboardKey.arrowLeft);
    }
    _expectKey(w, '12 reach row-1-item-0', 'row-1-item-0');

    // A held D-pad key repeats focus moves but never opens the menu.
    await _hold(
      tester,
      LogicalKeyboardKey.arrowRight,
      const Duration(milliseconds: 300),
    );
    final afterRepeat = _focusedKey();
    _expectThat(
      w,
      '12 held Right moves focus, no dialog',
      afterRepeat != 'row-1-item-0' && find.text('Details').evaluate().isEmpty,
      afterRepeat,
    );
    for (var i = 0; i < 8 && _focusedKey() != 'row-1-item-0'; i++) {
      await _press(tester, LogicalKeyboardKey.arrowLeft);
    }
    _expectKey(w, '12 back at the first item', 'row-1-item-0');

    await _hold(
      tester,
      LogicalKeyboardKey.select,
      const Duration(milliseconds: 700),
    );
    _expectThat(
      w,
      '12 held Select opens the context menu',
      find.text('Details').evaluate().isNotEmpty,
      null,
    );
    final menu = tester.getCenter(
      find
          .ancestor(
            of: find.text('Details'),
            matching: find.byType(GlassSurface),
          )
          .first,
    );
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    _expectThat(
      w,
      '12 menu is centred',
      (menu - Offset(screen.width / 2, screen.height / 2)).distance < 80,
      <String>[menu.toString(), screen.toString()],
    );
    await _back(tester);
    _expectThat(
      w,
      '12 Back closes the menu',
      find.text('Details').evaluate().isEmpty,
      null,
    );
    _expectKey(w, '12 focus restored', 'row-1-item-0');

    await _press(tester, LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    _expectKey(w, '13 Select pushes the detail', 'detail-play-action');
    await _back(tester);
    await tester.pumpAndSettle();
    _expectKey(w, '13 Back returns to the poster', 'row-1-item-0');

    // Android delivers Back as a system pop, not as a key: same result.
    await _press(tester, LogicalKeyboardKey.contextMenu);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    _expectThat(w, '14 system Back closes the panel', !_panelOpen, _panelOpen);
    _expectKey(w, '14 focus restored', 'row-1-item-0');
    await _press(tester, LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    _expectKey(
      w,
      '14 Select right after opens the detail',
      'detail-play-action',
    );
  });

  testWidgets('Movie detail walk', (tester) async {
    final item = MediaItem(
      id: 'rel-0',
      title: 'Related 0',
      kind: MediaKind.movie,
      artwork: Uri.parse('https://example.invalid/rel-0.jpg?ar=port'),
    );
    await _pump(tester, 'movie', <String, WidgetBuilder>{
      'movie': (context) => Center(
        child: FocusableAction(
          key: const ValueKey<String>('section-opener'),
          onActivate: () => pushAndRestoreFocus<void>(
            Navigator.of(context),
            AppPageRoute<void>(
              builder: (_) => Material(
                child: FavouritesScope(
                  repository: FakeFavouritesRepository(),
                  child: MovieDetailScreen(
                    presentation: keywalkMoviePresentation(item),
                    onPlay: () {},
                    onToggleWatched: () {},
                    onInfo: () {},
                    onRelatedTap: (_) {},
                    onTrailerTap: (_) {},
                    onCastTap: (_) {},
                  ),
                ),
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    });
    const w = 'movie detail';
    _expectKey(w, 'opener', 'section-opener');
    await _press(tester, LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    _expectKey(w, '0 entry', 'detail-play-action');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectKey(w, '1 Right to Trailer', 'detail-trailer');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectKey(w, '2 Right to Like', 'detail-like');
    await _press(tester, LogicalKeyboardKey.arrowLeft, times: 2);
    _expectKey(w, '3 Left Left back to Play', 'detail-play-action');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectKey(w, '4 Down to the first person', 'people-item-0');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectKey(w, '5 Down to More like this', 'detail-related-item-0');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    _expectKey(w, '6 Up to Cast', 'people-item-0');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    _expectKey(w, '7 Up returns to the action row', 'detail-play-action');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    _expectKey(w, '8 Up to Back', 'top-back');
    await _press(tester, LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    _expectKey(w, '9 Select pops, focus back on the opener', 'section-opener');
  });

  testWidgets('Movies grid walk', (tester) async {
    final items = fixtureLibraryItems(count: 24);
    await _pump(tester, 'movies', <String, WidgetBuilder>{
      'movies': (_) => LibraryScreen(
        items: items,
        scope: BrowseScope.movies,
        onItemTap: (_) {},
      ),
    });
    const w = 'movies';
    // §8.2: on TV the filter bar is the first focus row.
    _expectKey(w, '0 entry', 'filter-chip-0');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectKey(w, '1 Right to the next chip', 'filter-chip-1');
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    _expectKey(w, '1 Left back to the first chip', 'filter-chip-0');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectKey(w, '1 Down to the first poster', 'grid-item-0');
    final top0 = _rect(tester, 'grid-item-0').top;
    var perLine = 0;
    while (find
            .byKey(ValueKey<String>('grid-item-$perLine'))
            .evaluate()
            .isNotEmpty &&
        _rect(tester, 'grid-item-$perLine').top == top0) {
      perLine++;
    }
    _log.add(<String, Object?>{
      'walk': w,
      'step': 'columns',
      'actual': perLine,
      'pass': perLine > 1,
    });
    expect(perLine, greaterThan(1));
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectKey(w, '2 Down keeps the column', 'grid-item-$perLine');
    await _press(tester, LogicalKeyboardKey.arrowRight, times: perLine);
    _expectKey(
      w,
      '2 Right stops at the line end',
      'grid-item-${2 * perLine - 1}',
    );
    await _press(tester, LogicalKeyboardKey.arrowLeft, times: perLine - 1);
    _expectKey(w, '2 Left to the line start', 'grid-item-$perLine');
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    _expectThat(
      w,
      '3 Left at the line start opens the panel',
      _panelOpen,
      _panelOpen,
    );
    await _back(tester);
    _expectThat(w, '3 Back closes it', !_panelOpen, _panelOpen);
    _expectKey(w, '3 focus restored', 'grid-item-$perLine');
  });

  testWidgets('Settings walk', (tester) async {
    final settings = AppSettings(MemorySettingsStore());
    await _pump(tester, 'settings', <String, WidgetBuilder>{
      'settings': (_) => SettingsScreen(
        settings: settings,
        capabilities: keywalkCapabilityReport(),
        available: const <SettingCapability>{},
      ),
    });
    const w = 'settings';
    final entry = _focusedKey();
    expect(entry, startsWith('section-'));
    _log.add(<String, Object?>{
      'walk': w,
      'step': '0 entry',
      'actual': entry,
      'pass': true,
    });
    await _press(tester, LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    final inSection = _focusedKey();
    _expectThat(
      w,
      '1 Select enters the section',
      inSection != null && !inSection.startsWith('section-'),
      inSection,
    );
    // Select on a choice row opens a dialog; Back closes it, focus returns.
    final rowKey = _focusedKey();
    await _press(tester, LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 600));
    final dialog = find.byElementPredicate(
      (element) =>
          element.widget is GlassSurface &&
          ModalRoute.of(element) is PopupRoute,
    );
    _expectThat(
      w,
      '2 Select opens the choice dialog',
      dialog.evaluate().isNotEmpty,
      rowKey,
    );
    await _back(tester);
    _expectThat(
      w,
      '2 Back closes the dialog',
      dialog.evaluate().isEmpty,
      rowKey,
    );
    _expectKey(w, '2 focus back on the row', rowKey!);

    // Right/Left on a stepper row change its value.
    SettingStepperRow? stepper() => FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<SettingStepperRow>();
    for (var i = 0; i < 25 && stepper() == null; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    final before = stepper();
    expect(before, isNotNull, reason: 'a stepper row in the first section');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    final up = stepper();
    _expectThat(
      w,
      '3 Right increases the stepper',
      up != null &&
          up.value ==
              (before!.value + before.step).clamp(before.min, before.max) &&
          up.value != before.value,
      <double?>[before?.value, up?.value],
    );
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    _expectThat(
      w,
      '3 Left decreases it',
      stepper()?.value == before!.value,
      stepper()?.value,
    );

    await _back(tester);
    await tester.pumpAndSettle();
    _expectKey(w, '4 Back returns to the section list', entry!);
  });

  testWidgets('Search walk', (tester) async {
    final controller = LibrarySearchController(
      search: (_) async => fixtureLibraryItems(count: 24),
    );
    addTearDown(controller.dispose);
    await _pump(tester, 'search', <String, WidgetBuilder>{
      'search': (_) => SearchScreen(
        search: controller.search,
        controller: controller,
        onItemTap: (_) {},
      ),
    });
    const w = 'search';
    _expectKey(w, '0 entry', 'search-field');
    final field = tester.widget<TextField>(find.byType(TextField).first);
    _expectThat(w, '0 field read-only', field.readOnly, field.readOnly);
    await _press(tester, LogicalKeyboardKey.select);
    final editable = tester.widget<TextField>(find.byType(TextField).first);
    _expectThat(
      w,
      '1 Select makes the field editable',
      !editable.readOnly,
      editable.readOnly,
    );
    await _back(tester);
    final back = tester.widget<TextField>(find.byType(TextField).first);
    _expectThat(
      w,
      '2 Back makes it read-only again',
      back.readOnly,
      back.readOnly,
    );
    _expectKey(w, '2 focus kept', 'search-field');
  });
}
