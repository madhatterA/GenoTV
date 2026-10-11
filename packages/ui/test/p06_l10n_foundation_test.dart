import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/l10n_tools.dart';
import 'support/settings_shell_host.dart';

/// The app's root wiring (composition.dart `_app`) around [home].
Widget _app(AppSettings settings, Widget home) => StreamBuilder<SettingDef>(
  stream: settings.values.changes,
  builder: (_, _) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: localeForLanguage(settings.language),
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: AppStrings.localizationsDelegates,
    theme: AppTheme.dark(tv: false),
    builder: (_, child) => keepLayoutLtr(
      AdaptiveBehavior(
        capabilities: const PlatformCapabilities(),
        child: child!,
      ),
    ),
    home: home,
  ),
);

Widget _settingsScreen(AppSettings settings) => SettingsScreen(
  settings: settings,
  capabilities: settingsTestReport(),
  available: const <SettingCapability>{},
);

Future<void> _size(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Builds [builder] under a locale and returns its text widget.
Future<void> _pumpLocale(
  WidgetTester tester,
  String code,
  WidgetBuilder builder,
) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(code),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: AppStrings.localizationsDelegates,
      theme: AppTheme.dark(tv: false),
      home: Material(child: Builder(builder: builder)),
    ),
  );
}

Text _text(WidgetTester tester, String s) =>
    tester.widget<Text>(find.text(s).first);

void main() {
  testWidgets('fa keeps the layout LTR and shows the Farsi Language row', (
    tester,
  ) async {
    await _size(tester);
    final settings = AppSettings(MemorySettingsStore());
    await settings.setLanguage('fa');
    await tester.pumpWidget(_app(settings, _settingsScreen(settings)));
    await tester.pumpAndSettle();
    final directionality = tester.widget<Directionality>(
      find
          .ancestor(
            of: find.byType(SettingsScreen),
            matching: find.byType(Directionality),
          )
          .first,
    );
    expect(directionality.textDirection, TextDirection.ltr);
    expect(
      Directionality.of(tester.element(find.byType(SettingsScreen))),
      TextDirection.ltr,
    );
    expect(find.text('زبان'), findsOneWidget);
    final row = tester.getRect(
      find.byKey(const ValueKey('setting-app.language')),
    );
    expect(row.left, lessThan(640), reason: 'rows do not mirror');
  });

  testWidgets('language switches live: en -> fa -> system', (tester) async {
    await _size(tester);
    final settings = AppSettings(MemorySettingsStore());
    await settings.setLanguage('en');
    await tester.pumpWidget(_app(settings, _settingsScreen(settings)));
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);
    await tester.runAsync(() => settings.setLanguage('fa'));
    await tester.pumpAndSettle();
    expect(find.text('زبان'), findsOneWidget);
    expect(find.text('Language'), findsNothing);
    await tester.runAsync(() => settings.setLanguage('system'));
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);
  });

  testWidgets('system resolves to fa for a fa_IR device, else en', (
    tester,
  ) async {
    await _size(tester);
    final settings = AppSettings(MemorySettingsStore());
    tester.platformDispatcher.localesTestValue = const [Locale('fa', 'IR')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(_app(settings, _settingsScreen(settings)));
    await tester.pumpAndSettle();
    expect(find.text('زبان'), findsOneWidget);
    tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
    await tester.pumpWidget(_app(settings, _settingsScreen(settings)));
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);
  });

  testWidgets('AppText direction, height and alignment', (tester) async {
    final bodyFa = RivuletTypeStyles.bodyHeightFa;
    late TextStyle body;
    await _pumpLocale(tester, 'fa', (context) {
      body = RivuletTokens.of(context).typeStyles.body;
      return Column(
        children: [
          AppText('زبان', style: body),
          AppText('پاراگراف', style: body, paragraph: true),
          const AppText.content('The Matrix'),
        ],
      );
    });
    final fa = _text(tester, 'زبان');
    expect(fa.textDirection, TextDirection.rtl);
    expect(fa.style!.height, bodyFa);
    expect(_text(tester, 'پاراگراف').textAlign, TextAlign.right);
    expect(_text(tester, 'The Matrix').textDirection, TextDirection.ltr);

    await _pumpLocale(
      tester,
      'en',
      (_) => const Column(
        children: [AppText('Language'), AppText.content('ماتریکس')],
      ),
    );
    expect(_text(tester, 'Language').textDirection, TextDirection.ltr);
    expect(_text(tester, 'ماتریکس').textDirection, TextDirection.rtl);
  });

  testWidgets('formatters in fa and en', (tester) async {
    final out = <String, String>{};
    for (final code in ['fa', 'en']) {
      await _pumpLocale(tester, code, (c) {
        out['$code count'] = formatCount(c, 1250);
        out['$code duration'] = formatDuration(c, const Duration(minutes: 102));
        out['$code size'] = formatFileSize(c, 1503238553);
        out['$code percent'] = formatPercent(c, 0.42);
        out['$code year'] = formatYear(c, 2024);
        out['$code date'] = formatDate(c, DateTime(2026, 9, 20));
        out['$code rel'] = formatRelative(
          c,
          DateTime(2026, 9, 20, 10),
          now: DateTime(2026, 9, 20, 12),
        );
        return const SizedBox();
      });
    }
    expect(out, {
      'fa count': '۱٬۲۵۰',
      'fa duration': '۱ ساعت و ۴۲ دقیقه',
      'fa size': '۱٫۴ گیگابایت',
      'fa percent': '۴۲٪',
      'fa year': '۲۰۲۴',
      'fa date': '۲۹ شهریور ۱۴۰۵',
      'fa rel': '۲ ساعت پیش',
      'en count': '1,250',
      'en duration': '1h 42m',
      'en size': '1.4 GB',
      'en percent': '42%',
      'en year': '2024',
      'en date': 'Sep 20, 2026',
      'en rel': '2h ago',
    });
  });

  testWidgets('MarkedStrings detector reports only the literal', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [MarkedStringsDelegate()],
        home: Builder(
          builder: (context) => Column(
            children: [
              Text(AppStrings.of(context).settings_language_title),
              const Text('Literal English'),
            ],
          ),
        ),
      ),
    );
    expect(findUnextractedText(tester), ['Literal English']);
  });

  testWidgets('untranslated detector under fa honours the allowlist', (
    tester,
  ) async {
    await _pumpLocale(
      tester,
      'fa',
      (_) => const Column(children: [Text('پخش'), Text('Play'), Text('HDR10')]),
    );
    expect(findUntranslatedText(tester, allow: kTechAllowlist), ['Play']);
  });
}
