/// Production-app proof target for Part 08 ch05 p04; one player, one input.
library;

// The dedicated proof target injects one engine to issue OSD on that same player.
// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:playback/playback.dart';
import 'package:playback/src/controller/media_kit_playback_controller.dart';
import 'package:playback/src/engine/engine_bootstrap.dart';
import 'package:ui/ui.dart';
// Native package is already linked by playback; this target reads its counters.
// ignore: depend_on_referenced_packages
import 'package:video_surface/video_surface.dart' as native;

import 'composition.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final composition = await AppComposition.create();
  EngineBootstrap.ensureInitialised(logger: composition.logger);
  final player = mk.Player(
    configuration: const mk.PlayerConfiguration(
      libass: true,
      logLevel: mk.MPVLogLevel.v,
    ),
  );
  final controller = MediaKitPlaybackController(
    logger: composition.logger,
    player: player,
  );
  await controller.surfaceOutput.prepare();
  runApp(
    MaterialApp(
      theme: AppTheme.dark(tv: true),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: AppStrings.localizationsDelegates,
      home: _SubtitleProof(composition, controller, player),
    ),
  );
}

class _SubtitleProof extends StatefulWidget {
  const _SubtitleProof(this.composition, this.controller, this.player);
  final AppComposition composition;
  final MediaKitPlaybackController controller;
  final mk.Player player;

  @override
  State<_SubtitleProof> createState() => _SubtitleProofState();
}

class _SubtitleProofState extends State<_SubtitleProof> {
  static const fixture = String.fromEnvironment(
    'GENOTV_SUBTITLE_PROOF_FILE',
    defaultValue: '/data/local/tmp/hdr-subtitles.mkv',
  );
  final surface = createVideoSurface();
  String stage = 'BOOT';
  String? failure;
  int osdUpdate = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
  }

  Future<void> _start() => _perform(() async {
    await widget.controller.open(
      Uri.file(fixture),
      engineOptions: {
        'sid': '1',
        'sub-visibility': 'yes',
        'osd-level': '0',
        'hwdec': 'mediacodec',
        'osd-font': 'Vazirmatn',
        'osd-margin-y': '150',
      },
    );
    await widget.controller.play();
    await _snapshot('SRT');
  });

  Future<void> _perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (error, stack) {
      widget.composition.logger.error(
        'HDR subtitle production proof failed',
        error: error,
        stack: stack,
      );
      if (mounted) setState(() => failure = '$error');
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'android_hdr_subtitle_proof',
        ),
      );
    }
  }

  Future<void> _snapshot(String label, {bool track = true}) async {
    final properties = await widget.controller.readProperties([
      'current-vo',
      'hwdec-current',
      'video-params/gamma',
      'video-params/primaries',
      'sid',
      'sub-visibility',
      'time-pos',
      'estimated-frame-number',
      'wid',
      'pause',
      'vo-mediacodec-embed-overlay-surface',
    ]);
    final nativeProbe = await widget.controller.surfaceOutput.nativeSurface
        ?.probe();
    final counters = await native.NativeVideoSurface.nativeCounters();
    final result = {
      'stage': label,
      'fixture': fixture,
      'mode': widget.controller.surfaceOutput.mode.value.kind.name,
      'nativeProbe': nativeProbe,
      'nativeCounters': counters,
      ...properties,
    };
    final payload = jsonEncode(result);
    await File('${Directory.systemTemp.path}/production-$label.json')
        .writeAsString(payload);
    widget.composition.logger.info('HDR_SUBTITLE_PROOF $payload');
    if (track && mounted) setState(() => stage = label);
  }

  Future<void> _select(String label) => _perform(() async {
    final sid = switch (label) {
      'SRT' => '1',
      'ASS' => '2',
      'PGS' => '3',
      'VOB' => '4',
      _ => 'no',
    };
    await widget.controller.applySurfaceProperties([
      ('sid', sid),
      ('sub-visibility', 'yes'),
      ('osd-level', '0'),
    ], reseek: false);
    await (widget.player.platform as mk.NativePlayer).command([
      'show-text',
      label == 'OSD' ? 'MPV OSD — فارسی — ${++osdUpdate}' : '',
      '5000',
    ]);
    await widget.controller.play();
    await _snapshot(label);
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        Positioned.fill(
          child: PlayerScreen(
            controller: widget.controller,
            videoSurface: surface,
            title: 'Production HDR subtitle proof',
          ),
        ),
        Positioned(
          top: 12,
          left: 12,
          child: Material(
            color: Colors.green.shade800,
            child: Row(
              children: [
                for (final label in [
                  'SRT',
                  'ASS',
                  'PGS',
                  'VOB',
                  'OSD',
                  'CLEAR',
                ])
                  TextButton(
                    onPressed: () => unawaited(_select(label)),
                    child: Text(label),
                  ),
                TextButton(
                  onPressed: () => unawaited(
                    _perform(() async {
                      await widget.controller.pause();
                      await _snapshot('PAUSED');
                    }),
                  ),
                  child: const Text('PAUSE'),
                ),
                TextButton(
                  onPressed: () => unawaited(
                    _perform(() async {
                      await widget.controller.play();
                      await _snapshot('RESUMED');
                    }),
                  ),
                  child: const Text('RESUME'),
                ),
                TextButton(
                  onPressed: () => unawaited(_perform(() => _snapshot(stage, track: false))),
                  child: const Text('SNAP'),
                ),
                Text(' $stage ', style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
        const Positioned(
          bottom: 45,
          right: 20,
          child: ColoredBox(
            color: Colors.purple,
            child: Padding(
              padding: EdgeInsets.all(10),
              child: Text('FLUTTER FOREGROUND'),
            ),
          ),
        ),
        if (failure != null)
          Center(
            child: Text(failure!, style: const TextStyle(color: Colors.red)),
          ),
      ],
    ),
  );
}
