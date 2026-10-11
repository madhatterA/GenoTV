import '../l10n_gen/app_strings.dart';
import '../l10n/app_text.dart';

import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../components/app_row.dart';
import '../components/app_button.dart';
import '../components/app_toast.dart';
import '../navigation/page_top_inset.dart';
import '../platform/adaptive_behavior.dart';

import 'package:contracts/contracts.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../components/ambient_background.dart';
import '../navigation/page_back_button.dart';
import '../theme/rivulet_tokens.dart';

String _diagnosticLabel(String key, AppStrings strings) => switch (key) {
  'Resolution' => strings.diagnostics_Resolution,
  'Status' => strings.diagnostics_Status,
  'Log folder' => strings.diagnostics_Log_folder,
  'Hardware decoding' => strings.diagnostics_Hardware_decoding,
  'Decoders' => strings.diagnostics_Decoders,
  'HDR output' => strings.diagnostics_HDR_output,
  'HDR formats' => strings.diagnostics_HDR_formats,
  'Display mode switching' => strings.diagnostics_Display_mode_switching,
  'Audio passthrough' => strings.diagnostics_Audio_passthrough,
  'Passthrough formats' => strings.diagnostics_Passthrough_formats,
  'Decoder fallback' => strings.diagnostics_Decoder_fallback,
  'Video codec' => strings.diagnostics_Video_codec,
  'Decoder' => strings.diagnostics_Decoder,
  'Pixel format' => strings.diagnostics_Pixel_format,
  'Color matrix' => strings.diagnostics_Color_matrix,
  'Transfer function' => strings.diagnostics_Transfer_function,
  'Color primaries' => strings.diagnostics_Color_primaries,
  'HDR signal peak' => strings.diagnostics_HDR_signal_peak,
  'HDR max CLL' => strings.diagnostics_HDR_max_CLL,
  'HDR max FALL' => strings.diagnostics_HDR_max_FALL,
  'Audio codec' => strings.diagnostics_Audio_codec,
  'Audio format' => strings.diagnostics_Audio_format,
  'Audio output' => strings.diagnostics_Audio_output,
  'Audio output format' => strings.diagnostics_Audio_output_format,
  'Playback' => strings.diagnostics_Playback,
  'Position' => strings.diagnostics_Position,
  'Duration' => strings.diagnostics_Duration,
  'Paused' => strings.diagnostics_Paused,
  'Volume' => strings.diagnostics_Volume,
  'Video width' => strings.diagnostics_Video_width,
  'Video height' => strings.diagnostics_Video_height,
  _ => key,
};

class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({
    required this.report,
    this.playbackDiagnostics = const <String, String>{},
    this.copyText,
    this.live,
    this.logDirectory,
    super.key,
  });

  final CapabilityReport report;
  final Map<String, String> playbackDiagnostics;
  final Future<void> Function(String text)? copyText;

  /// Where the app writes its log files; shown (and copied) when set.
  final String? logDirectory;

  /// Replaces [playbackDiagnostics] and follows it while the page is open.
  final ValueListenable<Map<String, String>>? live;

  @override
  Widget build(BuildContext context) {
    final live = this.live;
    if (live == null) return _page(context, playbackDiagnostics);
    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: live,
      builder: (context, rows, _) => _page(context, rows),
    );
  }

  static const _video = <String>{
    'Video codec',
    'Decoder',
    'Pixel format',
    'Color matrix',
    'Transfer function',
    'Color primaries',
    'HDR signal peak',
    'HDR max CLL',
    'HDR max FALL',
  };
  static const _audio = <String>{
    'Audio codec',
    'Audio format',
    'Audio output',
    'Audio output format',
  };
  static const _sizeKeys = <String>{'Video width', 'Video height'};

  static String _yesNo(bool v, AppStrings strings) =>
      v ? strings.diagnostics_supported : strings.diagnostics_unsupported;

  Widget _page(BuildContext context, Map<String, String> playback) {
    final tokens = RivuletTokens.of(context);
    final colors = tokens.colors;
    final styles = tokens.typeStyles;
    final size =
        playback['Video width'] != null && playback['Video height'] != null
        ? '${playback['Video width']} \u00d7 ${playback['Video height']}'
        : null;
    final video = <(String, String)>[
      for (final e in playback.entries)
        if (_video.contains(e.key)) (e.key, e.value),
    ];
    if (size != null) {
      video.insert(video.length < 2 ? video.length : 2, ('Resolution', size));
    }
    final audio = <(String, String)>[
      for (final e in playback.entries)
        if (_audio.contains(e.key)) (e.key, e.value),
    ];
    final play = <(String, String)>[
      for (final e in playback.entries)
        if (!_video.contains(e.key) &&
            !_audio.contains(e.key) &&
            !_sizeKeys.contains(e.key))
          (e.key == 'Playback' ? 'Status' : e.key, e.value),
    ];
    final sep = AppStrings.of(context).localeName == 'fa' ? '\u060c ' : ', ';
    final device = <(String, String)>[
      if (logDirectory != null) ('Log folder', logDirectory!),
      (
        'Hardware decoding',
        _yesNo(report.hardwareDecode, AppStrings.of(context)),
      ),
      ('Decoders', report.decoders.join(sep)),
      ('HDR output', _yesNo(report.hdrOutput, AppStrings.of(context))),
      ('HDR formats', report.hdrFormats.join(sep)),
      (
        'Display mode switching',
        _yesNo(report.displayModeSwitching, AppStrings.of(context)),
      ),
      (
        'Audio passthrough',
        _yesNo(report.audioPassthrough, AppStrings.of(context)),
      ),
      ('Passthrough formats', report.passthroughFormats.join(sep)),
      for (final e in report.diagnostics.entries)
        (e.key == 'fallbackReason' ? 'Decoder fallback' : e.key, e.value),
    ];
    final raw = <String, String>{
      'hardwareDecode': report.hardwareDecode.toString(),
      'decoders': report.decoders.join(', '),
      'hdrOutput': report.hdrOutput.toString(),
      'hdrFormats': report.hdrFormats.join(', '),
      'displayModeSwitching': report.displayModeSwitching.toString(),
      'audioPassthrough': report.audioPassthrough.toString(),
      'passthroughFormats': report.passthroughFormats.join(', '),
      ...report.diagnostics,
      ...playback,
      'logFolder': ?logDirectory,
    };
    final text = raw.entries.map((e) => '${e.key}: ${e.value}').join('\n');

    Widget row((String, String) r) => LayoutBuilder(
      builder: (context, constraints) => SelectionArea(
        child: AppRow(
          key: ValueKey<String>('diagnostic-${r.$1}'),
          label: _diagnosticLabel(r.$1, AppStrings.of(context)),
          trailing: SizedBox(
            width:
                (constraints.maxWidth -
                    2 * RivuletSpacing.s16 -
                    RivuletSpacing.s12) *
                3 /
                5,
            child: AppText(
              r.$2,
              textAlign: TextAlign.right,
              style: styles.caption.copyWith(color: colors.textSecondary),
            ),
          ),
        ),
      ),
    );

    List<Widget> section(String title, List<(String, String)> rows) {
      final shown = rows.where((r) => r.$2.trim().isNotEmpty).toList();
      if (shown.isEmpty) return [];
      return [
        AppText(title, style: styles.headline),
        const SizedBox(height: RivuletSpacing.s16),
        AppRowGroup(children: [for (final r in shown) row(r)]),
        SizedBox(
          height: RivuletSpacing.rowGap(
            AdaptiveBehavior.of(context).formFactor,
          ),
        ),
      ];
    }

    final sizes = AdaptiveBehavior.sizesOf(context);
    final gutter = RivuletSpacing.gutter(
      AdaptiveBehavior.of(context).formFactor,
    );
    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            ListView(
              padding: EdgeInsets.fromLTRB(
                gutter,
                pageTopInsetOf(context),
                gutter,
                gutter,
              ),
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: sizes.settingsContentMaxWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppText(
                          AppStrings.of(context).settings_diagnostics,
                          style: styles.title,
                        ),
                        const SizedBox(height: RivuletSpacing.s24),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: AppButton.secondary(
                            key: const ValueKey<String>('copy-diagnostics'),
                            label: AppStrings.of(context).diagnostics_copy,
                            icon: PhosphorIconsRegular.copy,
                            onActivate: () async {
                              await (copyText ??
                                  (value) => Clipboard.setData(
                                    ClipboardData(text: value),
                                  ))(text);
                              if (context.mounted) {
                                showAppToast(
                                  context,
                                  PhosphorIconsRegular.copy,
                                  AppStrings.of(context).diagnostics_copied,
                                );
                              }
                            },
                          ),
                        ),
                        SizedBox(
                          height: RivuletSpacing.rowGap(
                            AdaptiveBehavior.of(context).formFactor,
                          ),
                        ),
                        ...section(AppStrings.of(context).player_video, video),
                        ...section(
                          AppStrings.of(context).settings_playback_title,
                          play,
                        ),
                        ...section(AppStrings.of(context).player_audio, audio),
                        ...section(
                          AppStrings.of(context).diagnostics_deviceCapabilities,
                          device,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const PageBackButton(),
          ],
        ),
      ),
    );
  }
}
