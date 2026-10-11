import 'dart:io';
import 'dart:ui' as ui;

import 'package:contracts/contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/surface_size.dart';

/// Counts how many times the image cache had to load a picture; a cache hit
/// never reaches [loadImage].
class _CountingProvider extends ImageProvider<_CountingProvider> {
  _CountingProvider(this.url, this.image, this.loads);

  final String url;
  final ui.Image image;
  final Map<String, int> loads;

  @override
  Future<_CountingProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_CountingProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    _CountingProvider key,
    ImageDecoderCallback decode,
  ) {
    loads[url] = (loads[url] ?? 0) + 1;
    return OneFrameImageStreamCompleter(
      SynchronousFuture<ImageInfo>(ImageInfo(image: image)),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _CountingProvider && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

void main() {
  testWidgets('hero items are cached at startup; paging fetches nothing and '
      'paints the backdrop on the first frame', (tester) async {
    const count = 5;
    final images = (await tester.runAsync(() async {
      final bytes = await File(
        '${Directory.current.path}/test/fixtures/backdrop_hero.jpg',
      ).readAsBytes();
      return <ui.Image>[
        for (var i = 0; i < count; i++)
          (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image,
      ];
    }))!;
    final loads = <String, int>{};
    final byUrl = <String, ui.Image>{
      for (var i = 0; i < count; i++)
        'https://example.invalid/b$i.jpg': images[i],
    };
    final items = <MediaItem>[
      for (var i = 0; i < count; i++)
        MediaItem(
          id: 'hero-$i',
          title: 'Hero $i',
          kind: MediaKind.movie,
          artwork: Uri.parse('https://example.invalid/p$i.jpg'),
        ),
    ];
    final model = HomeViewModel(
      rows: <HomeRow>[HomeRow(title: 'Trending', items: items)],
      heroArtwork: <String, Uri>{
        for (var i = 0; i < count; i++)
          'hero-$i': Uri.parse('https://example.invalid/b$i.jpg'),
      },
    );
    await setLogicalSize(tester, const Size(1400, 900));
    PaintingBinding.instance.imageCache.clear();
    await tester.pumpWidget(
      ArtworkResolverScope(
        resolver: (url) =>
            _CountingProvider(url, byUrl[url] ?? images[0], loads),
        child: MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: false),
          home: Scaffold(body: HomeScreen(viewModel: model)),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    // Every hero picture was fetched once during startup, none else.
    expect(byUrl.keys.every((url) => loads[url] == 1), isTrue);
    final afterStartup = Map<String, int>.of(loads);

    // The newest picture is the last child of the hero's crossfade stack.
    ui.Image? hero() => tester
        .widgetList<RawImage>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('hero-image-switcher')),
            matching: find.byType(RawImage),
          ),
        )
        .last
        .image;

    final timing = StringBuffer(
      'item | key press -> first frame with backdrop (test clock ms | wall ms)\n',
    );
    Finder dot(int index) => find.byKey(ValueKey<String>('hero-dot-$index'));
    expect(hero()!.isCloneOf(images[0]), isTrue);
    for (var step = 1; step <= count; step++) {
      final index = step % count;
      final clock = tester.binding.clock.stopwatch()..start();
      final wall = Stopwatch()..start();
      await tester.tap(dot(index));
      await tester.pump(); // exactly one frame after the key press
      final fake = clock.elapsedMilliseconds;
      final real = wall.elapsedMilliseconds;
      expect(
        hero()!.isCloneOf(images[index]),
        isTrue,
        reason: 'item $index first frame',
      );
      timing.writeln('$index | $fake | $real');
      if (index == 1) {
        await tester.pump(const Duration(milliseconds: 700));
        await expectLater(
          find.byKey(const ValueKey<String>('home-screen')),
          matchesGoldenFile('goldens/home_precache_item2.png'),
        );
      }
      await tester.pump(const Duration(milliseconds: 700));
    }
    for (var step = 1; step <= count; step++) {
      final index = (count - step) % count;
      await tester.tap(dot(index));
      await tester.pump();
      expect(hero()!.isCloneOf(images[index]), isTrue);
      await tester.pump(const Duration(milliseconds: 700));
    }

    expect(loads, afterStartup, reason: 'paging must not fetch anything');
    final dir = Directory.systemTemp.createTempSync('home-precache-');
    try {
      File('${dir.path}/timing.txt').writeAsStringSync(timing.toString());
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
