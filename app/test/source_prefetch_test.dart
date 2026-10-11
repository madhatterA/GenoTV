import 'package:video_player/play_flow.dart';
import 'package:video_player/source_prefetch.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

final class _Provider implements SourceProvider {
  int calls = 0;
  @override
  String get id => 'p';
  @override
  String get displayName => 'P';
  @override
  Future<MediaPage> browse(BrowseQuery query) async =>
      MediaPage(items: [], hasMore: false);
  @override
  Future<MediaPage> search(String query, {int limit = 50}) async =>
      MediaPage(items: [], hasMore: false);
  @override
  Future<List<SourceSpec>> resolve(MediaItem item) async {
    calls++;
    return <SourceSpec>[
      SourceSpec(kind: SourceKind.httpUrl, uri: Uri.parse('https://a/b.mkv')),
    ];
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  const movie = MediaItem(id: 'm', title: 'M', kind: MediaKind.movie);

  testWidgets('play flow reuses the movie page prefetch; stop cancels', (
    tester,
  ) async {
    final provider = _Provider();
    var cancelled = 0;
    final entries = <PlayProviderEntry>[
      PlayProviderEntry(
        id: 'p',
        name: 'P',
        provider: provider,
        cancel: () => cancelled++,
      ),
    ];
    final prefetch = SourcePrefetch(movie, entries);
    expect(provider.calls, 1);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: PlayFlowRoute(
          media: movie,
          providers: entries,
          prefetch: prefetch,
          onStreamSelected: (_, _) {},
          onBack: () {},
          onPlayLink: (_) async => null,
          onLinkAccepted: () {},
          pickTorrent: () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('provider-row-p')));
    await tester.pumpAndSettle();
    expect(provider.calls, 1);
    expect(
      find.byKey(const ValueKey<String>('play-source-streams')),
      findsOneWidget,
    );
    prefetch.stop();
    prefetch.stop();
    expect(cancelled, 1);
  });
}
