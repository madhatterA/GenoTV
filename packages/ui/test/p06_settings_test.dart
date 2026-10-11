import 'package:ui/src/l10n_gen/app_strings_en.dart';

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:ui/src/components/app_switch.dart';
import 'package:ui/src/settings/settings_controls.dart';
import 'package:ui/src/settings/settings_catalog.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/settings_shell_host.dart';
import 'support/surface_size.dart';

Future<void> pumpSettingsWidget(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1280, 800),
  bool tv = false,
  bool reduced = false,
}) async {
  tester.view.physicalSize = size * (tv ? 2 : 1);
  tester.view.devicePixelRatio = tv ? 2 : 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppStrings.localizationsDelegates,
      supportedLocales: AppStrings.supportedLocales,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(tv: tv).copyWith(
        platform: size.width < 600
            ? TargetPlatform.android
            : TargetPlatform.macOS,
      ),
      builder: (context, page) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: AdaptiveBehavior(
          capabilities: tv
              ? const PlatformCapabilities.directionalPad()
              : size.width < 600
              ? const PlatformCapabilities.touch()
              : const PlatformCapabilities(),
          child: page!,
        ),
      ),
      home: Scaffold(backgroundColor: Colors.transparent, body: child),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> focusRow(WidgetTester tester, Finder row) async {
  final text = find.descendant(of: row, matching: find.byType(Text)).first;
  Focus.of(tester.element(text)).requestFocus();
  await tester.pump();
}

String? settingsFocusedKey() {
  String? value;
  FocusManager.instance.primaryFocus?.context?.visitAncestorElements((element) {
    final key = element.widget.key;
    if (key is ValueKey<String>) {
      value = key.value;
      return false;
    }
    return true;
  });
  return value;
}

void main() {
  settingsComponentTests();
  settingsGoldenTests();
  providersLoadingTest();
  testWidgets('root has section and advanced/diagnostics row groups', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1280, 800));
    final settings = AppSettings(MemorySettingsStore());
    await pumpSettings(
      tester,
      settings,
      available: SettingCapability.values.toSet(),
      providersPage: settingsProvidersFixture,
    );
    final groups = tester
        .widgetList<AppRowGroup>(find.byType(AppRowGroup))
        .toList();
    expect(groups, hasLength(2));
    expect(groups.first.children, hasLength(10));
    expect(groups.last.children, hasLength(3));
    expect(find.text('Advanced settings'), findsOneWidget);
    expect(find.text('Diagnostics'), findsOneWidget);
    expect(tester.getSize(find.byType(AppRowGroup).first).width, 720);
    await tester.ensureVisible(find.byKey(const ValueKey('advanced-toggle')));
    await tester.tap(find.byKey(const ValueKey('advanced-toggle')));
    await tester.pumpAndSettle();
    expect(settings.showAdvanced, isTrue);
    expect(find.text('Expert'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('diagnostics-row')));
    await tester.tap(find.byKey(const ValueKey('diagnostics-row')));
    await tester.pumpAndSettle();
    expect(find.byType(DiagnosticsScreen), findsOneWidget);
    expect(find.byType(PageBackButton), findsOneWidget);
  });
}

void settingsComponentTests() {
  for (final (name, size, tv, minHeight) in [
    ('phone', const Size(400, 800), false, 56.0),
    ('desktop', const Size(1280, 800), false, 52.0),
    ('tv', const Size(960, 540), true, 60.0),
  ]) {
    testWidgets('$name section groups and row geometry', (tester) async {
      await pumpSettingsWidget(
        tester,
        SettingsScreen(
          settings: AppSettings(MemorySettingsStore()),
          capabilities: settingsTestReport(),
          available: SettingCapability.values.toSet(),
          section: SettingSection.audio,
        ),
        size: size,
        tv: tv,
      );
      final group = tester.widget<AppRowGroup>(find.byType(AppRowGroup));
      expect(group.children, isNotEmpty);
      final surface = tester.widget<TintedSurface>(
        find
            .descendant(
              of: find.byType(AppRowGroup),
              matching: find.byType(TintedSurface),
            )
            .first,
      );
      expect(surface.radius, RivuletRadius.large);
      for (final divider in tester.widgetList<Divider>(find.byType(Divider))) {
        expect(divider.thickness, 1);
        expect(divider.indent, RivuletSpacing.s16);
        expect(
          divider.color,
          RivuletTokens.of(tester.element(find.byType(AppRowGroup)))
              .colors
              .hairline,
        );
      }
      final row = find.byType(AppRow).first;
      expect(tester.getSize(row).height, greaterThanOrEqualTo(minHeight));
      final label = tester.widget<Text>(
        find.descendant(of: row, matching: find.byType(Text)).first,
      );
      expect(
        label.style,
        RivuletTokens.of(tester.element(row)).typeStyles.label,
      );
      if (tv) {
        await focusRow(
          tester,
          find.byKey(const ValueKey('setting-audio.outputDevice')),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        final ring = find.byWidgetPredicate(
          (w) => w is CustomPaint && w.foregroundPainter is FocusRingPainter,
        );
        expect(ring, findsOneWidget);
        final ringRect = tester
            .getRect(ring)
            .inflate(FocusRingPainter.offset + FocusRingPainter.thickness / 2);
        final viewport = tester.getRect(find.byType(SingleChildScrollView));
        expect(ringRect.left, greaterThanOrEqualTo(viewport.left + 3));
        expect(ringRect.top, greaterThanOrEqualTo(viewport.top + 3));
        expect(ringRect.right, lessThanOrEqualTo(viewport.right - 3));
        expect(ringRect.bottom, lessThanOrEqualTo(viewport.bottom - 3));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name choice selection, focus trap and restoration', (
      tester,
    ) async {
      var value = 'Auto';
      await pumpSettingsWidget(
        tester,
        StatefulBuilder(
          builder: (context, update) => AppRowGroup(
            children: [
              SettingChoiceRow(
                key: const ValueKey('choice-row'),
                title: 'Video decoder',
                value: value,
                options: const ['Auto', 'hardware', 'software'],
                labelOf: (v) => v,
                onChanged: (v) => update(() => value = v),
              ),
            ],
          ),
        ),
        size: size,
        tv: tv,
      );
      await focusRow(tester, find.byKey(const ValueKey('choice-row')));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(GlassSurface), findsOneWidget);
      expect(settingsFocusedKey(), 'choice-option-Auto');
      final checked = tester.widget<Icon>(
        find.byIcon(PhosphorIconsRegular.check),
      );
      expect(
        checked.color,
        RivuletTokens.of(tester.element(find.byType(GlassSurface)))
            .colors
            .accent,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(settingsFocusedKey(), 'choice-option-hardware');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(settingsFocusedKey(), 'choice-option-software');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(settingsFocusedKey(), 'choice-option-Auto');
      await tester.tap(find.byKey(const ValueKey('choice-option-hardware')));
      await tester.pumpAndSettle();
      expect(value, 'hardware');
      expect(find.byType(GlassSurface), findsNothing);
      expect(settingsFocusedKey(), 'choice-row');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(GlassSurface), findsNothing);
      expect(settingsFocusedKey(), 'choice-row');
    });
  }

  testWidgets('switch uses token colors, geometry and moving thumb', (
    tester,
  ) async {
    var value = false;
    await pumpSettingsWidget(
      tester,
      StatefulBuilder(
        builder: (_, update) => SettingToggleRow(
          title: 'Advanced settings',
          value: value,
          onChanged: (v) => update(() => value = v),
        ),
      ),
    );
    final toggle = find.byType(AppSwitch);
    final track = find.descendant(
      of: toggle,
      matching: find.byType(AnimatedContainer),
    );
    final thumb = find
        .descendant(of: toggle, matching: find.byType(DecoratedBox))
        .last;
    final tokens = RivuletTokens.of(tester.element(toggle));
    expect(tester.getSize(toggle), const Size(44, 26));
    expect(tester.getSize(thumb), const Size(20, 20));
    expect(
      (tester.widget<AnimatedContainer>(track).decoration! as BoxDecoration)
          .color,
      tokens.colors.tintFillHover,
    );
    final before = tester.getCenter(thumb).dx;
    await tester.tap(find.byType(SettingToggleRow));
    await tester.pumpAndSettle();
    expect(
      (tester.widget<AnimatedContainer>(track).decoration! as BoxDecoration)
          .color,
      tokens.colors.accent,
    );
    expect(
      (tester.widget<DecoratedBox>(thumb).decoration as BoxDecoration).color,
      tokens.colors.onAccent,
    );
    expect(tester.getCenter(thumb).dx - before, 18);
  });

  testWidgets('reduced motion switch thumb jumps and dialog fade is capped', (
    tester,
  ) async {
    var value = false;
    await pumpSettingsWidget(
      tester,
      StatefulBuilder(
        builder: (_, update) => Column(
          children: [
            SettingToggleRow(
              title: 'Advanced settings',
              value: value,
              onChanged: (v) => update(() => value = v),
            ),
            SettingChoiceRow(
              title: 'Video decoder',
              value: 'Auto',
              options: const ['Auto', 'software'],
              labelOf: (v) => v,
              onChanged: (_) {},
            ),
          ],
        ),
      ),
      reduced: true,
    );
    await tester.tap(find.byType(SettingToggleRow));
    await tester.pump();
    final align = tester.widget<AlignTransition>(find.byType(AlignTransition));
    expect(align.alignment.value, Alignment.centerRight);
    await tester.tap(find.byType(SettingChoiceRow));
    await tester.pump();
    final dialogContext = tester.element(find.byType(GlassSurface));
    final route = ModalRoute.of(dialogContext)!;
    expect(
      route.transitionDuration,
      lessThanOrEqualTo(const Duration(milliseconds: 120)),
    );
    await tester.pumpAndSettle();
    Navigator.of(dialogContext).pop();
    await tester.pumpAndSettle();
  });

  testWidgets('steppers remain readable, change by arrows and clamp', (
    tester,
  ) async {
    var value = 1.0;
    await pumpSettingsWidget(
      tester,
      StatefulBuilder(
        builder: (_, update) => SettingStepperRow(
          title: 'Playback speed',
          value: value,
          min: 0.25,
          max: 4,
          step: 0.25,
          unit: '×',
          onChanged: (v) => update(() => value = v),
        ),
      ),
    );
    final increase = find.byKey(const ValueKey('Playback speed-Increase'));
    Focus.of(
      tester.element(
        find.descendant(of: increase, matching: find.byType(Icon)),
      ),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(value, 1.25);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(value, 1);
    expect(find.text('1 ×'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppRow),
        matching: find.byWidgetPredicate((w) => w is Opacity && w.opacity < 1),
      ),
      findsNothing,
    );
  });

  testWidgets('longest catalogue label and description fit 360 px', (
    tester,
  ) async {
    final labels = [
      for (final def in settingDefs) settingLabel(def, AppStringsEn()),
    ]..sort((a, b) => b.length.compareTo(a.length));
    final descriptions = [
      for (final def in settingDefs) ?applyNote(def, AppStringsEn()),
    ]..sort((a, b) => b.length.compareTo(a.length));
    await pumpSettingsWidget(
      tester,
      Padding(
        padding: const EdgeInsets.all(RivuletSpacing.s16),
        child: SettingChoiceRow(
          title: labels.first,
          description: descriptions.first,
          value: 'Enabled',
          options: const ['Enabled', 'Disabled'],
          labelOf: (v) => v,
          onChanged: (_) {},
        ),
      ),
      size: const Size(360, 800),
    );
    final description = tester.widget<Text>(find.text(descriptions.first));
    expect(description.maxLines, 2);
    expect(description.overflow, TextOverflow.ellipsis);
    expect(
      description.style?.color,
      RivuletTokens.of(tester.element(find.byType(AppRow)))
          .colors
          .textSecondary,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('list settings announce checked and unchecked states', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await pumpSettingsWidget(
      tester,
      SettingListRow(
        labelOf: (value) => value,
        title: 'Prefer best audio',
        options: const ['lossless', 'language'],
        selected: const ['lossless'],
        onChanged: (_) {},
      ),
    );
    final checked = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.checked == true,
    );
    final unchecked = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.checked == false,
    );
    expect(checked, findsOneWidget);
    expect(unchecked, findsOneWidget);
    semantics.dispose();
  });

  testWidgets(
    'Diagnostics values are selectable and never dimmed as disabled',
    (tester) async {
      await pumpSettingsWidget(
        tester,
        DiagnosticsScreen(
          report: settingsTestReport(),
          playbackDiagnostics: const {'Decoder': 'software'},
          copyText: (_) async {},
        ),
      );
      expect(find.text('software'), findsOneWidget);
      expect(find.byType(SelectionArea), findsWidgets);
      for (final row in find.byType(AppRow).evaluate()) {
        expect(
          find.descendant(
            of: find.byWidget(row.widget),
            matching: find.byWidgetPredicate(
              (w) => w is Opacity && w.opacity < 1,
            ),
          ),
          findsNothing,
        );
      }
      final copy = tester.widget<AppButton>(
        find.byKey(const ValueKey('copy-diagnostics')),
      );
      expect(copy.icon, PhosphorIconsRegular.copy);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('copy-diagnostics'))).dy,
        lessThan(tester.getTopLeft(find.byType(AppRow).first).dy),
      );
    },
  );
}

void settingsGoldenTests() {
  for (final (name, size, tv) in [
    ('phone', const Size(400, 800), false),
    ('desktop', const Size(1280, 800), false),
    ('tv', const Size(960, 540), true),
  ]) {
    testWidgets('golden choice dialog $name', (tester) async {
      await pumpSettingsWidget(
        tester,
        AmbientBackground(
          child: Center(
            child: SizedBox(
              width: 720,
              child: AppRowGroup(
                children: [
                  SettingChoiceRow(
                    title: 'Video decoder',
                    value: 'Auto',
                    options: const ['Auto', 'hardware', 'software'],
                    labelOf: (v) => v,
                    onChanged: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
        size: size,
        tv: tv,
      );
      await tester.tap(find.byType(SettingChoiceRow));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/p06/settings_choice_dialog_$name.png'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
    testWidgets('golden Diagnostics $name', (tester) async {
      await pumpSettingsWidget(
        tester,
        DiagnosticsScreen(
          report: settingsTestReport(),
          playbackDiagnostics: const {'Decoder': 'software'},
          copyText: (_) async {},
        ),
        size: size,
        tv: tv,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/p06/diagnostics_$name.png'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('golden Advanced on desktop', (tester) async {
    final settings = AppSettings(MemorySettingsStore());
    await settings.setShowAdvanced(true);
    await pumpSettingsWidget(
      tester,
      SettingsScreen(
        settings: settings,
        capabilities: settingsTestReport(),
        available: SettingCapability.values.toSet(),
        providersPage: settingsProvidersFixture,
      ),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/p06/settings_advanced_on_desktop.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('golden text row desktop', (tester) async {
    await pumpSettingsWidget(
      tester,
      SettingsScreen(
        settings: AppSettings(MemorySettingsStore()),
        capabilities: settingsTestReport(),
        available: SettingCapability.values.toSet(),
        section: SettingSection.subtitles,
      ),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/p06/settings_text_row_desktop.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

void providersLoadingTest() {
  testWidgets(
    'Providers QR uses orbs, glass and cancels polling on dismissal',
    (tester) async {
      final login = Completer<UiQrLogin>();
      var polls = 0;
      await pumpSettingsWidget(
        tester,
        ProvidersScreen(
          load: () async => const [
            UiProviderAccount(
              id: 'qr',
              name: '30nama',
              login: UiProviderLogin.qr,
            ),
          ],
          onCredentials: (_, _, _) async => null,
          onStartQr: (_) => login.future,
          onPollQr: (_, _) async {
            polls++;
            return false;
          },
          onLogout: (_) async {},
          onBuy: (_) async {},
        ),
      );
      await tester.tap(find.byKey(const ValueKey('provider-login-qr')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(OrbLoader), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(OrbLoader),
          matching: find.byType(GlassSurface),
        ),
        findsOneWidget,
      );
      login.complete(
        UiQrLogin(code: '1234', url: Uri.parse('https://example.com/login')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('provider-qr')), findsOneWidget);
      expect(find.byType(OrbLoader), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      expect(polls, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(polls, 1);
      expect(find.byKey(const ValueKey('provider-qr')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
