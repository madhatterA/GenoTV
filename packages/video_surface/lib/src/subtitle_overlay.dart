import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Android draws text subtitles in Flutter above the SurfaceView: the bundled libass has no
/// fonts (no fontconfig, `sub-font-provider=none`) so mpv draws none itself, and
/// `vo=mediacodec_embed` (HDR) has no OSD at all. Picture subtitles stay mpv's.
///
/// The style is mpv's own subtitle options (the app's Subtitles settings write them), read
/// when a cue arrives. Sizes are mpv's 720-line scaled pixels.
@immutable
final class SubtitleStyle {
  const SubtitleStyle({
    this.font = 'sans-serif',
    this.size = 42,
    this.color = const Color(0xFFFFFFFF),
    this.border = 2.5,
    this.borderColor = const Color(0xFF000000),
    this.shadow = 0,
    this.background = const Color(0x00000000),
    this.position = 100,
    this.marginY = 36,
  });

  /// mpv option names [fromMpv] needs, in the order of [SubtitleStyle.names].
  static const names = <String>[
    'sub-font',
    'sub-font-size',
    'sub-color',
    'sub-border-size',
    'sub-border-color',
    'sub-shadow-offset',
    'sub-back-color',
    'sub-pos',
    'sub-margin-y',
  ];

  final String font;
  final double size;
  final Color color;
  final double border;
  final Color borderColor;
  final double shadow;
  final Color background;

  /// mpv `sub-pos`: 0 top .. 100 bottom.
  final double position;
  final double marginY;

  /// Builds a style from mpv option values; a missing or empty one keeps the default.
  factory SubtitleStyle.fromMpv(Map<String, String> values) {
    const d = SubtitleStyle();
    double number(String name, double fallback) =>
        double.tryParse(values[name] ?? '') ?? fallback;
    Color color(String name, Color fallback) =>
        parseMpvColor(values[name] ?? '') ?? fallback;
    final font = values['sub-font'] ?? '';
    return SubtitleStyle(
      font: font.isEmpty ? d.font : font,
      size: number('sub-font-size', d.size),
      color: color('sub-color', d.color),
      border: number('sub-border-size', d.border),
      borderColor: color('sub-border-color', d.borderColor),
      shadow: number('sub-shadow-offset', d.shadow),
      background: color('sub-back-color', d.background),
      position: number('sub-pos', d.position),
      marginY: number('sub-margin-y', d.marginY),
    );
  }
}

/// mpv colours print as `#RRGGBB` or `#AARRGGBB`.
Color? parseMpvColor(String text) {
  final hex = text.startsWith('#') ? text.substring(1) : text;
  if (hex.length != 6 && hex.length != 8) return null;
  final value = int.tryParse(hex, radix: 16);
  if (value == null) return null;
  return Color(hex.length == 6 ? 0xFF000000 | value : value);
}

/// The cue text, styled by [read] (an mpv property getter), above the video.
class SubtitleOverlay extends StatefulWidget {
  const SubtitleOverlay({super.key, required this.text, required this.read});

  /// mpv `sub-text`: empty when no cue is showing.
  final Stream<String> text;
  final Future<String> Function(String name) read;

  @override
  State<SubtitleOverlay> createState() => _SubtitleOverlayState();
}

class _SubtitleOverlayState extends State<SubtitleOverlay> {
  StreamSubscription<String>? _sub;
  String _cue = '';
  SubtitleStyle _style = const SubtitleStyle();

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(SubtitleOverlay old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      unawaited(_sub?.cancel());
      _cue = '';
      _listen();
    }
  }

  void _listen() => _sub = widget.text.listen(_onCue);

  Future<void> _onCue(String cue) async {
    if (cue.isEmpty) {
      if (mounted) setState(() => _cue = '');
      return;
    }
    try {
      final values = <String, String>{
        for (final name in SubtitleStyle.names) name: await widget.read(name),
      };
      if (!mounted) return;
      setState(() {
        _style = SubtitleStyle.fromMpv(values);
        _cue = cue;
      });
    } catch (error, stack) {
      // The cue still shows with the last style; the failure is reported, not hidden.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'video_surface',
          context: ErrorDescription('while reading the subtitle style'),
        ),
      );
      if (mounted) setState(() => _cue = cue);
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cue.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) {
          final scale = box.maxHeight / 720;
          final s = _style;
          final base = TextStyle(
            fontFamily: s.font,
            fontSize: s.size * scale,
            height: 1.15,
            fontWeight: FontWeight.w600,
          );
          final text = _cue.trim();
          return Padding(
            padding: EdgeInsets.fromLTRB(
              box.maxWidth * 0.05,
              0,
              box.maxWidth * 0.05,
              box.maxHeight * (100 - s.position) / 100 + s.marginY * scale,
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: DecoratedBox(
                decoration: BoxDecoration(color: s.background),
                child: Stack(
                  children: [
                    if (s.border > 0)
                      Text(
                        text,
                        textAlign: TextAlign.center,
                        style: base.copyWith(
                          foreground: Paint()
                            ..style = PaintingStyle.stroke
                            ..strokeJoin = StrokeJoin.round
                            ..strokeWidth = s.border * 2 * scale
                            ..color = s.borderColor,
                        ),
                      ),
                    Text(
                      text,
                      textAlign: TextAlign.center,
                      style: base.copyWith(
                        color: s.color,
                        shadows: s.shadow > 0
                            ? [
                                ui.Shadow(
                                  offset: Offset(s.shadow, s.shadow) * scale,
                                  color: const Color(0xFF000000),
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
