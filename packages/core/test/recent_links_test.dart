import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  var tick = 0;
  RecentLinks make(SettingsStore store) =>
      RecentLinks(store, clock: () => DateTime(2026, 10, 3, 0, 0, tick++));

  test('newest first, max 10: the 11th drops the oldest', () async {
    final recents = make(MemorySettingsStore());
    for (var i = 1; i <= 11; i++) {
      await recents.add('https://x/$i.mp4', kind: 'directFile');
    }
    final links = recents.entries.map((e) => e.link).toList();
    expect(links.length, 10);
    expect(links.first, 'https://x/11.mp4');
    expect(links.last, 'https://x/2.mp4');
  });

  test('a repeat moves to the top, no duplicate, title kept', () async {
    final recents = make(MemorySettingsStore());
    await recents.add('a', kind: 'magnet', title: 'Name A');
    await recents.add('b', kind: 'magnet');
    await recents.add('a', kind: 'magnet');
    expect(recents.entries.map((e) => e.link), ['a', 'b']);
    expect(recents.entries.first.title, 'Name A');
    expect(recents.entries.last.label, 'b');
  });

  test('remove one and clear all', () async {
    final recents = make(MemorySettingsStore());
    await recents.add('a', kind: 'hls');
    await recents.add('b', kind: 'hls');
    await recents.remove('a');
    expect(recents.entries.map((e) => e.link), ['b']);
    await recents.clear();
    expect(recents.entries, isEmpty);
  });

  test('entries survive a store reload from disk', () async {
    final dir = await Directory.systemTemp.createTemp('recent_links');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/settings.json');
    final first = JsonSettingsStore(file: file, logger: MemoryLogger());
    await make(first).add('magnet:?xt=urn:btih:x', kind: 'magnet', title: 'T');
    await first.dispose();

    final second = JsonSettingsStore(file: file, logger: MemoryLogger());
    await second.load();
    final entry = make(second).entries.single;
    expect(entry.link, 'magnet:?xt=urn:btih:x');
    expect(entry.kind, 'magnet');
    expect(entry.title, 'T');
  });

  test('corrupt stored data reads as empty', () async {
    final store = MemorySettingsStore();
    await store.write('playLink.recent', 'not json');
    expect(make(store).entries, isEmpty);
  });
}
