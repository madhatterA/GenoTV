import '../../l10n_gen/app_strings.dart';
import '../../l10n/app_text.dart';

import 'package:flutter/material.dart';

import '../../theme/rivulet_tokens.dart';
import '../../theme/stats_colors.dart';
import 'player_stats.dart';
import 'stats_format.dart';

/// The small download-info panel behind the player's "i" button. Refreshes
/// once a second while it is open (via [PlayerStatsController]); the
/// "Advanced" button hands over to the stats overlay.
class StatsPopover extends StatefulWidget {
  const StatsPopover({
    required this.controller,
    required this.onAdvanced,
    super.key,
  });

  final PlayerStatsController controller;
  final VoidCallback onAdvanced;

  @override
  State<StatsPopover> createState() => _StatsPopoverState();
}

class _StatsPopoverState extends State<StatsPopover> {
  @override
  void initState() {
    super.initState();
    widget.controller.start();
  }

  @override
  void didUpdateWidget(covariant StatsPopover oldWidget) {
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
    super.dispose();
  }

  List<(String, String)> _rows(PlayerStatsSnapshot snap) {
    final t = snap.transport;
    if (t == null) return const [];
    final torrent = t.torrent;
    return [
      ('Download speed', formatSpeed(t.downloadBytesPerSecond)),
      if (torrent != null)
        ('Upload speed', formatSpeed(torrent.uploadBytesPerSecond)),
      ('Downloaded', formatProgress(t.downloadedBytes, t.totalBytes)),
      ('Time left', formatEta(t.timeLeft)),
      if (torrent == null)
        ('Connections', formatCount(t.connections))
      else ...[
        ('Seeds connected', '${torrent.seeds}'),
        ('Peers connected', '${torrent.peers}'),
        (
          'Swarm',
          torrent.swarmSeeds == null && torrent.swarmPeers == null
              ? statsUnknown
              : '${formatCount(torrent.swarmSeeds)} seeds / '
                    '${formatCount(torrent.swarmPeers)} peers',
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final rows = _rows(widget.controller.snapshot);
        return Column(
          key: const ValueKey<String>('stats-popover'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(statsUnknown, style: tokens.typeStyles.body),
              ),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: AppText(
                        statsLabel(label, AppStrings.of(context)),
                        style: tokens.typeStyles.caption,
                      ),
                    ),
                    Text(
                      value,
                      key: ValueKey<String>('stats-popover-$label'),
                      style: tokens.typeStyles.body,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey<String>('stats-advanced'),
                onPressed: widget.onAdvanced,
                icon: const Icon(Icons.analytics_outlined, size: 18),
                label: AppText(AppStrings.of(context).player_advanced),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A tiny sparkline of the last [PlayerStatsController.historyLength]
/// one-second speeds, scaled to the biggest value shown.
class SpeedSparkline extends StatelessWidget {
  const SpeedSparkline({required this.values, this.color, super.key});

  final List<double> values;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey<String>('stats-sparkline'),
    height: 28,
    width: double.infinity,
    child: CustomPaint(
      painter: _SparklinePainter(values, color ?? StatsColors.graph),
    ),
  );
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()
      ..color = StatsColors.baseline
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - .5),
      Offset(size.width, size.height - .5),
      base,
    );
    if (values.length < 2) return;
    final peak = values.reduce((a, b) => a > b ? a : b);
    if (peak <= 0) return;
    final step = size.width / (PlayerStatsController.historyLength - 1);
    final start = size.width - step * (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = start + step * i;
      final y = size.height - 2 - (size.height - 4) * (values[i] / peak);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values || old.color != color;
}
