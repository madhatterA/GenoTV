import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import 'source_status_row.dart';

/// Renders exactly the source choices and status it is handed — no source
/// resolution, retry policy, or transport implementation lives here (phase
/// non-goal). Selecting a row calls [onSelected]; a retry on a
/// failed/stalled row calls [onRetry] with that same source. The caller
/// (Part 07) owns re-resolving it.
class SourcePickerPanel extends StatefulWidget {
  const SourcePickerPanel({
    required this.sources,
    required this.activeIndex,
    required this.statusOf,
    required this.onSelected,
    this.onRetry,
    super.key,
  });

  final List<SourceSpec> sources;
  final int activeIndex;

  /// Current status for the source at each index, or `null` when none has
  /// arrived yet.
  final SourceStatus? Function(int index) statusOf;
  final ValueChanged<SourceSpec> onSelected;
  final ValueChanged<SourceSpec>? onRetry;

  @override
  State<SourcePickerPanel> createState() => _SourcePickerPanelState();
}

class _SourcePickerPanelState extends State<SourcePickerPanel> {
  int? _pendingIndex;

  @override
  void didUpdateWidget(covariant SourcePickerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeIndex != widget.activeIndex) _pendingIndex = null;
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
    key: const ValueKey<String>('source-picker-list'),
    itemCount: widget.sources.length,
    itemBuilder: (context, index) {
      final source = widget.sources[index];
      final active = index == widget.activeIndex;
      final status = widget.statusOf(index);
      final locked = _pendingIndex != null;
      return KeyedSubtree(
        key: ValueKey<String>('source-$index'),
        child: SourceStatusRow(
          source: source,
          active: active,
          status: status,
          autofocus: active,
          onTap: active || locked ? null : () => _select(index, source),
          onRetry:
              (active ||
                      status?.state == SourceState.failed ||
                      status?.state == SourceState.stalled) &&
                  widget.onRetry != null
              ? () => widget.onRetry!(source)
              : null,
        ),
      );
    },
  );

  void _select(int index, SourceSpec source) {
    setState(() => _pendingIndex = index);
    widget.onSelected(source);
  }
}
