import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/composition.dart';
import 'package:video_player/transport_options.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'play provider list contains Torrents after the existing providers',
    () async {
      // Real composition, with path_provider answering a temp directory so
      // the test never touches the user's app-support folder.
      final root = Directory.systemTemp.createTempSync('torrent_wiring_');
      addTearDown(() => root.deleteSync(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => root.path,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              null,
            ),
      );
      // Dispose talks to the platform_services channel; answer it with null,
      // except the monitor picker the macOS composition selects at start.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('platform_services'),
            (call) async => call.method.startsWith('display.')
                ? {
                    'supported': true,
                    'choices': {'': 'Default'},
                    'selected': '',
                  }
                : null,
          );
      final composition = await AppComposition.create();
      addTearDown(composition.dispose);

      final entries = composition.playProviders;
      expect(entries.map((e) => e.id), [
        'moviejavan',
        'thirtynama',
        'digimoviez',
        'ccloud',
        'playtorrio_direct',
        'torrents',
      ]);
      expect(entries.last.name, 'Torrents');
      // Wrapped so the protocol preference orders its sources.
      expect(entries.last.provider, isA<ProtocolOrderedProvider>());
      expect(entries.last.provider!.id, composition.torrents.id);
    },
  );
}
