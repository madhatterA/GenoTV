import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../theme/rivulet_tokens.dart';

/// Draws a throwaway poster card once, under the opaque pages, so the GPU
/// programs a focused (scaled) card needs are compiled at startup. Their first
/// use on the TV's Mali-G52 cost ~65 ms of raster on the first Down from the
/// hero (Part 08 task 32). Gone after one second.
class ShaderWarmup extends StatefulWidget {
  const ShaderWarmup({super.key});

  // 8x8 solid JPEG: the same decode and upload path as a real poster.
  static final _jpeg = base64Decode(
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDABALDA4MChAODQ4SERATGCgaGBYWGDEjJR0oOjM9PDkzODdASFxOQERXRTc4UG1RV19iZ2hnPk1xeXBkeFxlZ2P/2wBDARESEhgVGC8aGi9jQjhCY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2P/wAARCAAIAAgDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDhaKKKYH//2Q==',
  );

  @override
  State<ShaderWarmup> createState() => _ShaderWarmupState();
}

class _ShaderWarmupState extends State<ShaderWarmup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scale = AnimationController(
    vsync: this,
    lowerBound: 1,
    upperBound: RivuletFocusMetrics.standard.tileFocusScaleTv,
    duration: const Duration(milliseconds: 250),
  );
  Timer? _start;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    // After the first Home frames, so the compile does not delay them.
    _start = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      _scale.forward().whenComplete(() {
        if (mounted) setState(() => _done = true);
      });
    });
  }

  @override
  void dispose() {
    _start?.cancel();
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const SizedBox.shrink();
    final colors = RivuletTokens.of(context).colors;
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 6.3,
            height: 9.1,
            child: ScaleTransition(
              scale: _scale,
              child: RepaintBoundary(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(RivuletRadius.medium),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      ColoredBox(color: colors.tintFill),
                      Image.memory(
                        ShaderWarmup._jpeg,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
