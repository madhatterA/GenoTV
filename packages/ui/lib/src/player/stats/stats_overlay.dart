import '../../l10n_gen/app_strings.dart';
import '../../l10n/app_text.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/stats_colors.dart';
import 'player_stats.dart';
import 'stats_popover.dart';

/// "Stats for nerds": a translucent monospace panel drawn over the video,
/// top-left, refreshed once a second while it is shown. It never touches
/// playback. [onClose] hides it (the close button; "i" toggles it too).
class StatsOverlay extends StatefulWidget {
  const StatsOverlay({
    required this.controller,
    required this.onClose,
    super.key,
  });

  final PlayerStatsController controller;
  final VoidCallback onClose;

  @override
  State<StatsOverlay> createState() => _StatsOverlayState();
}

class _StatsOverlayState extends State<StatsOverlay> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.start();
  }

  @override
  void didUpdateWidget(covariant StatsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The player swaps its controller when the stream handle changes; follow it.
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.stop();
      widget.controller.start();
    }
  }

  @override
  void dispose() {
    widget.controller.stop();
    _scroll.dispose();
    super.dispose();
  }

  static const _mono = TextStyle(
    fontFamily: 'Menlo',
    fontFamilyFallback: <String>[
      'Consolas',
      'Roboto Mono',
      'monospace',
      'Roboto',
    ],
    fontSize: 12,
    height: 1.35,
    color: StatsColors.text,
    decoration: TextDecoration.none,
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final source = widget.controller.source;
      final snap = widget.controller.snapshot;
      final groups = buildStatsGroups(source, snap);
      final maxHeight = MediaQuery.sizeOf(context).height - 64 - 16;
      return Container(
        key: const ValueKey<String>('stats-overlay'),
        width: 380,
        constraints: BoxConstraints(maxHeight: maxHeight),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
        decoration: BoxDecoration(
          color: StatsColors.panel,
          borderRadius: BorderRadius.circular(10),
        ),
        child: DefaultTextStyle(
          style: _mono,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: AppText(
                      AppStrings.of(context).player_statsTitle,
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey<String>('stats-copy'),
                    tooltip: AppStrings.of(context).player_copyDebug,
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    color: StatsColors.text,
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: statsAsText(groups)),
                    ),
                    icon: const Icon(Icons.copy_rounded),
                  ),
                  IconButton(
                    key: const ValueKey<String>('stats-close'),
                    tooltip: AppStrings.of(context).common_close,
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    color: StatsColors.text,
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Flexible(
                child: ScrollbarTheme(
                  data: const ScrollbarThemeData(
                    thumbColor: WidgetStatePropertyAll<Color>(
                      StatsColors.heading,
                    ),
                    thickness: WidgetStatePropertyAll<double>(3),
                    radius: Radius.circular(2),
                  ),
                  child: Scrollbar(
                    controller: _scroll,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _scroll,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          for (final group in groups) ...<Widget>[
                            const SizedBox(height: 6),
                            AppText(
                              statsLabel(
                                group.title,
                                AppStrings.of(context),
                              ).toUpperCase(),
                              style: _mono.copyWith(
                                color: StatsColors.heading,
                                fontSize: 11,
                                letterSpacing: 1,
                              ),
                            ),
                            for (final row in group.rows) ...<Widget>[
                              InkWell(
                                onTap: row.copyValue == null
                                    ? null
                                    : () => Clipboard.setData(
                                        ClipboardData(text: row.copyValue!),
                                      ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    SizedBox(
                                      width: 126,
                                      child: AppText(
                                        statsLabel(
                                          row.label,
                                          AppStrings.of(context),
                                        ),
                                        style: _mono.copyWith(
                                          color: StatsColors.label,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        row.value,
                                        key: ValueKey<String>(
                                          'stats-${group.title}-${row.label}',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (row.speedGraph ?? false)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 2,
                                    bottom: 2,
                                  ),
                                  child: SpeedSparkline(
                                    values: snap.downHistory,
                                  ),
                                ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
