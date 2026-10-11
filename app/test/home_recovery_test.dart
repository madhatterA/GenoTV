import 'dart:io';

import 'package:contracts/fakes.dart';

import 'package:content_sources/content_sources.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';
import 'package:video_player/catalogue_views.dart';

void main() {
  testWidgets('home recovers by itself once the network is back', (
    tester,
  ) async {
    HttpOverrides.global = null;
    await tester.runAsync(() async {
      var up = false;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (up) {
          request.response.write('{"page":1,"total_pages":1,"results":[]}');
        } else {
          request.response.statusCode = 503;
        }
        await request.response.close();
      });
      final dir = await Directory.systemTemp.createTemp('home-recovery');
      final http = ProviderHttp();
      final catalogue = TmdbCatalogue(
        client: TmdbClient(
          http: http,
          baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
        ),
        omdb: OmdbRatings(http: http, logger: MemoryLogger()),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: false),
          home: TmdbHomeView(
            catalogue: catalogue,
            favourites: FakeFavouritesRepository(),
            progress: FakeProgressRepository(),
            onItemTap: (_, _) {},
            retryDelay: const Duration(milliseconds: 100),
          ),
        ),
      );
      Future<void> settle(bool Function() done) async {
        for (var i = 0; i < 100 && !done(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
      }

      await settle(() => find.byType(ErrorView).evaluate().isNotEmpty);
      expect(find.byType(ErrorView), findsOneWidget);
      up = true;
      await settle(() => find.byType(HomeScreen).evaluate().isNotEmpty);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(ErrorView), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      http.close();
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
  });
}
