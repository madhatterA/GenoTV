import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

void main() {
  testWidgets('free first with Free tag; Buy always; sign in refreshes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var digiSignedIn = false;
    final bought = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: ProvidersScreen(
          load: () async => <UiProviderAccount>[
            UiProviderAccount(
              id: 'digimoviez',
              name: 'DigiMoviez',
              login: UiProviderLogin.credentials,
              buyUrl: Uri.parse('https://digimoviez.com/account/register'),
              loggedIn: digiSignedIn,
            ),
            const UiProviderAccount(id: 'ccloud', name: 'CCloud'),
            UiProviderAccount(
              id: 'moviejavan',
              name: 'MovieJavan',
              login: UiProviderLogin.unavailable,
              buyUrl: Uri.parse('https://moviejavan.com'),
            ),
          ],
          onCredentials: (id, user, password) async {
            if (password == 'network') throw StateError('Login failed');
            if (password != 'right') return 'Wrong password';
            digiSignedIn = true;
            return null;
          },
          onStartQr: (_) async => throw UnimplementedError(),
          onPollQr: (_, _) async => false,
          onLogout: (_) async => digiSignedIn = false,
          onBuy: (url) async => bought.add(url),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final ccloud = tester.getTopLeft(
      find.byKey(const ValueKey('provider-card-ccloud')),
    );
    final digi = tester.getTopLeft(
      find.byKey(const ValueKey('provider-card-digimoviez')),
    );
    expect(ccloud.dy, lessThan(digi.dy));
    expect(find.byKey(const ValueKey('provider-free-ccloud')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('provider-free-digimoviez')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('provider-buy-ccloud')), findsNothing);
    expect(
      find.byKey(const ValueKey('provider-buy-moviejavan')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('provider-login-moviejavan')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('provider-buy-digimoviez')));
    expect(bought.single.host, 'digimoviez.com');

    await tester.tap(find.byKey(const ValueKey('provider-login-digimoviez')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('provider-user')),
        matching: find.byType(EditableText),
      ),
      'me',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('provider-password')),
        matching: find.byType(EditableText),
      ),
      'wrong',
    );
    await tester.tap(find.byKey(const ValueKey('provider-submit')));
    await tester.pumpAndSettle();
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('provider-user')),
        matching: find.byType(GlassSurface),
      ),
      findsOneWidget,
    );
    expect(find.text('Username or email'), findsWidgets);
    expect(find.text('Wrong password'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('provider-password')),
        matching: find.byType(EditableText),
      ),
      'network',
    );
    await tester.tap(find.byKey(const ValueKey('provider-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Bad state: Login failed'), findsOneWidget);
    expect(
      tester
          .widget<AppButton>(find.byKey(const ValueKey('provider-submit')))
          .onActivate,
      isNotNull,
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('provider-password')),
        matching: find.byType(EditableText),
      ),
      'right',
    );
    await tester.tap(find.byKey(const ValueKey('provider-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Signed in'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('provider-logout-digimoviez')),
      findsOneWidget,
    );
    // Buy stays while signed in.
    expect(
      find.byKey(const ValueKey('provider-buy-digimoviez')),
      findsOneWidget,
    );
  });
}
