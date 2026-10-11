// DESIGN_SPEC §9 component sheets (phone / desktop / TV). One real focus
// exists at a time, so every "focused" or "pressed" sample is captured in its
// own stage and pasted onto the idle sheet; the orb is frozen at t = 300 ms.
import 'dart:ui' as ui;

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/fixture_artwork.dart';

const _factors = <String, ({Size size, bool tv})>{
  'phone': (size: Size(400, 3200), tv: false),
  'desktop': (size: Size(1280, 3200), tv: false),
  'tv': (size: Size(960, 3200), tv: true),
};

const _sheet = ValueKey<String>('components-sheet');

Widget _label(String text) => Padding(
  padding: const EdgeInsets.only(top: RivuletSpacing.s16),
  child: Text(
    text,
    style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 11),
  ),
);

Widget _wrap(List<Widget> children) => Wrap(
  spacing: RivuletSpacing.s16,
  runSpacing: RivuletSpacing.s16,
  crossAxisAlignment: WrapCrossAlignment.center,
  children: children,
);

/// Samples that need a real focus or press, by key.
const _focusKeys = <String>[
  'primary-focus',
  'secondary-focus',
  'chip-focus',
  'row-focus',
];

Future<ui.Image> _grab(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_sheet),
  );
  return (await tester.runAsync(() => boundary.toImage()))!;
}

void main() {
  for (final entry in _factors.entries) {
    testWidgets('components ${entry.key}', (tester) async {
      final factor = entry.value;
      debugDefaultTargetPlatformOverride = switch (entry.key) {
        'desktop' => TargetPlatform.macOS,
        _ => TargetPlatform.android,
      };
      tester.view.physicalSize = factor.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final artwork = await loadFixtureArtworkResolver(tester);
      final nodes = {for (final k in _focusKeys) k: FocusNode(debugLabel: k)};
      addTearDown(() {
        for (final n in nodes.values) {
          n.dispose();
        }
      });
      final bg = Image(
        image: artwork('https://example.invalid/art?ar=land'),
        fit: BoxFit.cover,
        width: 260,
        height: 84,
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark(tv: factor.tv),
          home: AdaptiveBehavior(
            capabilities: factor.tv
                ? const PlatformCapabilities.directionalPad()
                : entry.key == 'phone'
                ? const PlatformCapabilities.touch()
                : const PlatformCapabilities(),
            child: Scaffold(
              body: SingleChildScrollView(
                child: RepaintBoundary(
                  key: _sheet,
                  child: ColoredBox(
                    color: RivuletColors.dark().bgBase,
                    child: Padding(
                      padding: const EdgeInsets.all(RivuletSpacing.s24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _label('AppButton.primary  idle / pressed / focused'),
                          _wrap(<Widget>[
                            AppButton.primary(
                              icon: PhosphorIconsFill.play,
                              label: 'Play',
                              onActivate: () {},
                            ),
                            AppButton.primary(
                              key: const ValueKey('primary-press'),
                              icon: PhosphorIconsFill.play,
                              label: 'Play',
                              onActivate: () {},
                            ),
                            AppButton.primary(
                              key: const ValueKey('primary-focus'),
                              focusNode: nodes['primary-focus'],
                              icon: PhosphorIconsFill.play,
                              label: 'Play',
                              onActivate: () {},
                            ),
                          ]),
                          _label('AppButton.secondary  idle / focused'),
                          _wrap(<Widget>[
                            AppButton.secondary(
                              icon: PhosphorIconsFill.play,
                              label: 'Trailer',
                              onActivate: () {},
                            ),
                            AppButton.secondary(
                              key: const ValueKey('secondary-focus'),
                              icon: PhosphorIconsFill.play,
                              focusNode: nodes['secondary-focus'],
                              label: 'Trailer',
                              onActivate: () {},
                            ),
                          ]),
                          _label('AppIconButton  plain / glass / overMedia'),
                          Stack(
                            children: <Widget>[
                              bg,
                              Positioned.fill(
                                child: Padding(
                                  padding: const EdgeInsets.all(
                                    RivuletSpacing.s16,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: <Widget>[
                                      AppIconButton(
                                        icon: PhosphorIconsRegular.heart,
                                        semanticLabel: 'Like',
                                        onActivate: () {},
                                      ),
                                      AppIconButton(
                                        icon: PhosphorIconsRegular.screencast,
                                        semanticLabel: 'Cast',
                                        glass: true,
                                        onActivate: () {},
                                      ),
                                      AppIconButton(
                                        icon: PhosphorIconsRegular.gear,
                                        semanticLabel: 'Settings',
                                        overMedia: true,
                                        onActivate: () {},
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          _label('AppTextButton'),
                          AppTextButton(label: 'See all', onActivate: () {}),
                          _label('AppChip  idle / selected / focused'),
                          _wrap(<Widget>[
                            AppChip(label: 'Drama', onActivate: () {}),
                            AppChip(
                              label: 'Comedy',
                              selected: true,
                              onActivate: () {},
                            ),
                            AppChip(
                              key: const ValueKey('chip-focus'),
                              focusNode: nodes['chip-focus'],
                              label: 'Thriller',
                              onActivate: () {},
                            ),
                          ]),
                          _label(
                            'AppRowGroup  toggle / value + caret / focused',
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: AppRowGroup(
                              children: <Widget>[
                                AppRow(
                                  label: 'Advanced settings',
                                  description: 'Show expert options',
                                  toggle: true,
                                  onActivate: () {},
                                ),
                                AppRow(
                                  label: 'Language',
                                  icon: PhosphorIconsRegular.globe,
                                  value: 'English',
                                  onActivate: () {},
                                ),
                                AppRow(
                                  key: const ValueKey('row-focus'),
                                  focusNode: nodes['row-focus'],
                                  label: 'Diagnostics',
                                  caret: true,
                                  onActivate: () {},
                                ),
                              ],
                            ),
                          ),
                          _label('OrbLoader 24 / 48 / 72 (t = 300 ms)'),
                          _wrap(const <Widget>[
                            OrbLoader.small(),
                            OrbLoader.medium(),
                            OrbLoader.large(),
                          ]),
                          _label('StateSkeleton posters'),
                          const SizedBox(height: 440, child: StateSkeleton()),
                          _label('EmptyState'),
                          const EmptyView(
                            headline: 'Nothing here yet',
                            body: 'Titles you like will show up on this page.',
                          ),
                          _label('ErrorState'),
                          ErrorView(
                            failure: const UnexpectedFailure(cause: 'boom'),
                            onRetry: () {},
                          ),
                          _label('AppToast'),
                          const AppToast(
                            icon: PhosphorIconsFill.check,
                            text: 'Added to Liked',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      final base = await _grab(tester);

      // Keyboard input on phone/desktop so a focused sample shows its ring.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      final stages = <Rect, ui.Image>{};
      for (final k in _focusKeys) {
        nodes[k]!.requestFocus();
        await tester.pump(const Duration(milliseconds: 200));
        stages[tester.getRect(find.byKey(ValueKey(k)))] = await _grab(tester);
      }

      final press = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('primary-press'))),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 200));
      stages[tester.getRect(find.byKey(const ValueKey('primary-press')))] =
          await _grab(tester);
      await press.up();
      await tester.pump(const Duration(milliseconds: 200));
      final origin = tester.getTopLeft(find.byKey(_sheet));
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..drawImage(base, Offset.zero, Paint());
      for (final e in stages.entries) {
        final area = e.key.shift(-origin).inflate(14);
        canvas.drawImageRect(e.value, area, area, Paint());
      }
      final composed = await tester.runAsync(
        () => recorder.endRecording().toImage(base.width, base.height),
      );
      await expectLater(
        composed,
        matchesGoldenFile('goldens/p06/components_${entry.key}.png'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
