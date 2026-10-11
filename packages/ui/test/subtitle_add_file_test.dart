import 'package:contracts/contracts.dart';
import 'package:contracts/fakes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

/// Adds a subtitle track to its list for every external subtitle.
class _Player extends FakePlaybackController {
  final added = <(Uri, String?)>[];
  @override
  Future<void> addExternalSubtitle(Uri uri, {String? title}) async {
    added.add((uri, title));
    final list = currentState.tracks.subtitle;
    setTracks(
      TrackList(
        audio: currentState.tracks.audio,
        subtitle: [
          ...list,
          Track(
            id: 'ext${list.length + 1}',
            type: TrackType.subtitle,
            title: title,
          ),
        ],
      ),
    );
  }
}

Widget _app(
  _Player player,
  Future<List<({String name, Uri uri})>> Function()? add,
) => MaterialApp(
  localizationsDelegates: const [AppStrings.delegate],
  theme: AppTheme.dark(tv: false),
  home: Scaffold(
    body: StreamBuilder<PlaybackState>(
      stream: player.state,
      initialData: player.currentState,
      builder: (_, snapshot) => TrackPanel(
        controller: player,
        state: snapshot.data!,
        dismiss: () {},
        type: TrackType.subtitle,
        onAddSubtitleFiles: add,
      ),
    ),
  ),
);

void main() {
  testWidgets('no importer: the row is hidden', (tester) async {
    final player = _Player();
    addTearDown(player.dispose);
    await tester.pumpWidget(_app(player, null));
    expect(find.text('Add subtitle file…'), findsNothing);
  });

  testWidgets('adds every file, lists them, first one becomes active', (
    tester,
  ) async {
    final player = _Player();
    addTearDown(player.dispose);
    await tester.pumpWidget(
      _app(
        player,
        () async => [
          (name: 'one.srt', uri: Uri.file('/tmp/one.srt')),
          (name: 'two.srt', uri: Uri.file('/tmp/two.srt')),
        ],
      ),
    );
    await tester.tap(find.text('Add subtitle file…'));
    await tester.pumpAndSettle();
    expect(player.added.map((a) => a.$2), ['one.srt', 'two.srt']);
    expect(find.text('one.srt'), findsOneWidget);
    expect(find.text('two.srt'), findsOneWidget);
    expect(
      player.currentState.selected.subtitle,
      const TrackChoice.specific('ext1'),
    );
  });

  testWidgets('cancel adds nothing; failure is shown inline', (tester) async {
    final player = _Player();
    addTearDown(player.dispose);
    await tester.pumpWidget(_app(player, () async => const []));
    await tester.tap(find.text('Add subtitle file…'));
    await tester.pumpAndSettle();
    expect(player.added, isEmpty);

    await tester.pumpWidget(
      _app(
        player,
        () async => throw StateError('No subtitle files found in the zip.'),
      ),
    );
    await tester.tap(find.text('Add subtitle file…'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No subtitle files found'), findsOneWidget);
  });
}
