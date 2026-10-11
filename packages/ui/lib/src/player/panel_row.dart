import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/rivulet_tokens.dart';

/// One selectable, focusable row shared by every player panel list (track,
/// source, Up Next): focused and selected states are visually distinct
/// (phase step 2 — "Selected and focused states are distinct"), and a
/// `failed` row gets a danger tint so an optimistic-selection failure is
/// visible on the exact row that caused it.
///
/// Selected-row look: an opaque light pill with dark content — matched to
/// `evidence/part-04-rivulet/infuse-ref/tvos/IMG_8304.jpg` after the
/// owner's ch03-p05 rejection of the previous grey-tint/blue-checkmark
/// treatment (see `evidence/part-04-rivulet/ch03-p05/track_panel_compare.png`).
/// Row content (text/icons) picks up the right color automatically via
/// [PanelRow.foregroundColor] rather than every caller hardcoding it.
class PanelRow extends StatefulWidget {
  const PanelRow({
    required this.child,
    required this.selected,
    required this.tokens,
    this.onTap,
    this.autofocus = false,
    this.failed = false,
    this.compact = false,
    this.focusNode,
    super.key,
  });

  final Widget child;
  final bool selected;
  final bool failed;
  final bool autofocus;

  /// Shorter row (provider cards); default keeps the player-panel height.
  final bool compact;
  final VoidCallback? onTap;
  final RivuletTokens tokens;

  /// External focus node for this row, e.g. so a caller can
  /// `requestFocus()` it directly (arrow-key navigation between panels).
  /// When null, the row manages its own internal node — every existing
  /// caller (`SourceStatusRow`, track/Up-Next rows) is unaffected.
  final FocusNode? focusNode;

  /// Shared theme foreground for selected and idle rows, without changing
  /// text or icon sizes when the selected state changes.
  static Color foregroundColor(
    RivuletTokens tokens, {
    required bool selected,
  }) => selected
      ? tokens.colors.panelRowSelectedForeground
      : tokens.colors.textPrimary;

  @override
  State<PanelRow> createState() => _PanelRowState();
}

class _PanelRowState extends State<PanelRow> {
  FocusNode? _ownedNode;
  bool _focused = false;

  FocusNode get _node => widget.focusNode ?? (_ownedNode ??= FocusNode());

  @override
  void dispose() {
    _ownedNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.tokens.colors;
    final highContrast = MediaQuery.highContrastOf(context);
    final background = widget.failed
        ? colors.danger.withValues(alpha: 0.18)
        : widget.selected
        ? colors.panelRowSelectedFill
        : _focused
        ? colors.railButtonIdle.withValues(alpha: 0.6)
        : Colors.transparent;
    final foreground = PanelRow.foregroundColor(
      widget.tokens,
      selected: widget.selected && !widget.failed,
    );
    return Semantics(
      button: true,
      selected: widget.selected,
      enabled: widget.onTap != null,
      onTap: widget.onTap,
      child: Focus(
        canRequestFocus: widget.onTap != null,
        focusNode: _node,
        autofocus: widget.autofocus,
        onFocusChange: (value) => setState(() => _focused = value),
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent || widget.onTap == null) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onTap!();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          excludeFromSemantics: true,
          onTap: widget.onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: EdgeInsets.symmetric(
              horizontal: 20,
              vertical: widget.compact ? 9 : 16,
            ),
            constraints: BoxConstraints(minHeight: widget.compact ? 44 : 64),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(16),
              border: _focused
                  ? Border.all(
                      color: widget.tokens.colors.accent,
                      width: highContrast ? 3 : 2,
                    )
                  : highContrast
                  ? Border.all(color: colors.textPrimary, width: 2)
                  : null,
            ),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: foreground),
              child: IconTheme.merge(
                data: IconThemeData(color: foreground),
                child: highContrast && widget.selected
                    ? Row(
                        children: [
                          const Icon(Icons.check, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: widget.child),
                        ],
                      )
                    : widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
