import 'package:contracts/contracts.dart';
import 'package:contracts/fakes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

// break-ui worst case in Farsi: a 120+ character Persian title with a Latin
// name inside, and a Persian overview with English names and a URL inside.
const _title =
    'داستان بسیار طولانی و پرپیچ‌وخم مردی به نام Christopher Nolan که سال‌ها '
    'در بندر کوچک شهر زندگی کرد و هرگز آن‌جا را ترک نکرد، نسخهٔ کارگردان';
const _summary =
    'در شهری بندری، مأموری بازنشسته به نام John McClane پس از ده سال به محله‌ای '
    'بازمی‌گردد که Warner Bros. آن را ساخته بود. جزئیات بیشتر در '
    'https://example.com/film/2024 آمده است. هر شب مه از دریا بالا می‌آید.';

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa'),
      localizationsDelegates: AppStrings.localizationsDelegates,
      supportedLocales: AppStrings.supportedLocales,
      builder: (_, child) =>
          Directionality(textDirection: TextDirection.ltr, child: child!),
      theme: AppTheme.dark(tv: false),
      home: AdaptiveBehavior(
        child: Scaffold(
          body: FavouritesScope(
            repository: FakeFavouritesRepository(),
            child: MovieDetailScreen(
              presentation: const MovieDetailPresentation(
                item: MediaItem(
                  id: 'fa-worst',
                  title: _title,
                  kind: MediaKind.movie,
                ),
                summary: _summary,
                genres: ['درام'],
              ),
              onPlay: () {},
              onRelatedTap: (_) {},
              onTrailerTap: (_) {},
              onLinkTap: (_) {},
              onCastTap: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  for (final (form, size) in [
    ('phone', const Size(400, 800)),
    ('desktop', const Size(1280, 800)),
  ]) {
    testWidgets('golden farsi worst case detail $form', (tester) async {
      await _pump(tester, size);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Christopher Nolan'), findsWidgets);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/p06/farsi_worst_case_detail_${form}_fa.png'),
      );
    });
  }

  test('HomeViewModel keeps a row\'s localized title builder', () {
    final row = HomeRow(
      title: 'Trending Movies',
      titleOf: (s) => s.home_trendingMovies,
      items: const <MediaItem>[],
    );
    final model = HomeViewModel(rows: [row]);
    expect(model.rows.single.titleOf, same(row.titleOf));
    model.replaceRows([row]);
    expect(model.rows.single.titleOf, same(row.titleOf));
  });
}
