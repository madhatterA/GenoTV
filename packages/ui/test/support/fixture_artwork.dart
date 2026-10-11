// Test-only artwork resolver: maps every fixture `https://example.invalid/...`
// artwork URL to a real, already-decoded fixture photo so goldens paint
// posters/backdrops instead of the network-failure placeholder icon.
//
// Why not `Image.network`/`HttpOverrides`, and why not a plain
// `FileImage`/`precacheImage`: both were tried and hung. `Image.network`
// races its real codec against flutter_test's fake-async pump schedule (see
// `decisions.md`, "Sidebar icon size fix; home hero/rows/artwork-seam
// attempted then reverted"). `FileImage` resolved via the standard
// `precacheImage` deadlocks the same way even inside `tester.runAsync` —
// `MultiFrameImageStreamCompleter`'s machinery needs a live frame/pump
// racing the same real-vs-fake-clock boundary, confirmed by a throwaway
// repro (`precacheImage(FileImage(...), context)` inside `runAsync` never
// returns; the `flutter_tester` process sits at 0% CPU).
//
// The pattern that already works in this repo (`shared_components_test.dart`'s
// `_ControlledImageProvider` + `_decodeFixture`): decode the real fixture
// bytes with `ui.instantiateImageCodec` inside `tester.runAsync`, entirely
// BEFORE `pumpWidget`, then hand the finished `ui.Image` to a provider whose
// `loadImage` returns a `OneFrameImageStreamCompleter` wrapping an
// *already-completed* future. That listener fires on a plain microtask
// flush (an ordinary `tester.pump()`), never on the frame-scheduling path
// that deadlocked above.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const List<String> _posterFileNames = <String>[
  'poster_spring.jpg',
  'poster_cosmos.jpg',
  'poster_elephants.jpg',
  'poster_tears.jpg',
  'poster_bigbuck.jpg',
];

const List<String> _landscapeFileNames = <String>[
  'cw_spring.jpg',
  'cw_elephants.jpg',
  'cw_bigbuck.jpg',
  'backdrop_hero.jpg',
  'backdrop_detail.jpg',
  'backdrop_series.jpg',
];

const List<String> fixtureArtworkFileNames = <String>[
  ..._posterFileNames,
  ..._landscapeFileNames,
];

/// Decodes every fixture file once, with the real engine codec, inside
/// `tester.runAsync` — must be called (and awaited) before `pumpWidget`.
/// Returns the resolver to hand to `ArtworkResolverScope`.
///
/// Assignment is deterministic and near-injective per distinct URL: rather
/// than `url.hashCode % length` (which collapsed many different fixture
/// URLs onto the same one or two images — e.g. every poster showing Sintel),
/// each *distinct* URL seen is handed the next fixture in rotation, cycling
/// only after every image has been used once. Two calls with the same URL
/// still get the same image.
Future<ImageProvider Function(String url)> loadFixtureArtworkResolver(
  WidgetTester tester,
) async {
  final images = await tester.runAsync(() async {
    final decoded = <ui.Image>[];
    for (final fileName in fixtureArtworkFileNames) {
      final bytes = await File(
        '${Directory.current.path}/test/fixtures/$fileName',
      ).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      decoded.add(frame.image);
    }
    return decoded;
  });
  final resolved = images!;
  final posters = resolved.sublist(0, _posterFileNames.length);
  final landscapes = resolved.sublist(_posterFileNames.length);
  final assigned = <String, ui.Image>{};
  var nextAny = 0;
  var nextPoster = 0;
  var nextLandscape = 0;
  return (String url) {
    final image = assigned.putIfAbsent(url, () {
      // Content-matched override: a URL naming "sintel" is pinned to a
      // fixed fixture instead of the round-robin below, which was handing
      // Sintel URLs whichever landscape fixture came up next (e.g. the
      // Spring backdrop — the orchestrator-reported wrong-art bug).
      //
      // No fixture in this directory is actually Sintel art: every file
      // was opened and eyeballed. `poster_sintel.jpg` is mislabeled — its
      // pixels are identical to `poster_bigbuck.jpg` (a "Big Buck Bunny"
      // poster, mascot + title text, would read as *more* wrong than a
      // mismatch since it's a visibly different film's branding).
      // `backdrop_detail.jpg`/`backdrop_hero.jpg`/`backdrop_series.jpg` are
      // all the same Tears-of-Steel robot-hand crop, not Sintel either, but
      // carry no competing logo/title text. Per the phase brief ("use
      // backdrop_detail.jpg only if it is Sintel art" — it is not, so this
      // is a fixture-asset gap, not a styling fix; flagged in the report,
      // not silently invented) `backdrop_detail.jpg` is used as the
      // least-wrong placeholder pending a correctly sourced Sintel backdrop
      // fixture being added to this directory.
      if (url.toLowerCase().contains('sintel')) {
        return landscapes[_landscapeFileNames.indexOf('backdrop_detail.jpg')];
      }
      // `?ar=port`/`?ar=land` (set by `fixtureHomeRows`) picks a portrait
      // poster or landscape still/backdrop so poster tiles never receive a
      // stretched landscape crop. A URL with no hint (library/series
      // fixtures) keeps the old combined round-robin so their existing
      // goldens are unaffected.
      if (url.contains('ar=port')) {
        final image = posters[nextPoster % posters.length];
        nextPoster++;
        return image;
      }
      if (url.contains('ar=land')) {
        final image = landscapes[nextLandscape % landscapes.length];
        nextLandscape++;
        return image;
      }
      final image = resolved[nextAny % resolved.length];
      nextAny++;
      return image;
    });
    return _FixtureImageProvider(url, image);
  };
}

/// An [ImageProvider] wrapping an already-decoded [ui.Image]. Two instances
/// for the same [url] are `==`, so `ArtworkView.didUpdateWidget` doesn't
/// treat a rebuild with the same URL as a new request.
class _FixtureImageProvider extends ImageProvider<_FixtureImageProvider> {
  _FixtureImageProvider(this.url, this.image);

  final String url;
  final ui.Image image;

  @override
  Future<_FixtureImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_FixtureImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    _FixtureImageProvider key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    // A clone per load: every image-cache entry disposes its own handle, and
    // the decoded fixture is shared by many entries.
    SynchronousFuture<ImageInfo>(ImageInfo(image: image.clone())),
  );

  @override
  bool operator ==(Object other) =>
      other is _FixtureImageProvider && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
