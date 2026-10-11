import '../l10n/app_text.dart';

import 'package:flutter/material.dart';

import '../theme/rivulet_tokens.dart';
import 'panel_row.dart';

/// Where one Up Next row sits relative to what's currently playing.
enum UpNextState { watched, nowPlaying, upNext, future }

/// One row's display data. `contracts`/`content_sources` own no episode/
/// queue model (Part 06 is intentionally empty per `CLAUDE.md`) — this is a
/// plain UI-local value type, the same pattern `PlayerMetadata` already uses
/// for its title/rating/runtime strings.
class UpNextItem {
  const UpNextItem({
    required this.id,
    required this.title,
    required this.state,
    this.subtitle,
  });

  final String id;
  final String title;
  final String? subtitle;
  final UpNextState state;
}

/// Fixed row height so the initial scroll-to-current offset (step 6:
/// "scroll to current on open") can be computed without a layout pass.
const double upNextRowExtent = 108;

/// Up Next panel: watched rows are dimmed, the now-playing row is marked,
/// upcoming rows are selectable, and the list opens already scrolled so the
/// now-playing (or, if none, the first upNext) row is visible.
class UpNextPanel extends StatefulWidget {
  const UpNextPanel({required this.items, required this.onSelected, super.key});

  final List<UpNextItem> items;
  final ValueChanged<UpNextItem> onSelected;

  @override
  State<UpNextPanel> createState() => _UpNextPanelState();
}

class _UpNextPanelState extends State<UpNextPanel> {
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: _currentOffset(),
  );

  double _currentOffset() {
    var index = widget.items.indexWhere(
      (item) => item.state == UpNextState.nowPlaying,
    );
    if (index < 0) {
      index = widget.items.indexWhere(
        (item) => item.state == UpNextState.upNext,
      );
    }
    return index < 0 ? 0 : index * upNextRowExtent;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    return ListView.builder(
      key: const ValueKey<String>('up-next-list'),
      controller: _scroll,
      itemExtent: upNextRowExtent,
      itemCount: widget.items.length,
      itemBuilder: (context, index) {
        final item = widget.items[index];
        final selectable =
            item.state == UpNextState.upNext ||
            item.state == UpNextState.future;
        final selected = item.state == UpNextState.nowPlaying;
        final fg = PanelRow.foregroundColor(tokens, selected: selected);
        final titleColor = item.state == UpNextState.watched
            ? fg.withValues(alpha: 0.5)
            : fg;
        return KeyedSubtree(
          key: ValueKey<String>('up-next-${item.id}'),
          child: PanelRow(
            tokens: tokens,
            selected: selected,
            autofocus:
                item.state == UpNextState.nowPlaying ||
                (item.state == UpNextState.upNext &&
                    !widget.items.any(
                      (i) => i.state == UpNextState.nowPlaying,
                    )),
            onTap: selectable ? () => widget.onSelected(item) : null,
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 28,
                  child: item.state == UpNextState.watched
                      ? Icon(Icons.check_circle, size: 20, color: titleColor)
                      : item.state == UpNextState.nowPlaying
                      ? Icon(Icons.play_circle_fill, size: 22, color: fg)
                      : null,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      AppText.content(
                        item.title,
                        style: tokens.typeStyles.panelRow.copyWith(
                          color: titleColor,
                        ),
                      ),
                      if (item.subtitle case final subtitle?)
                        AppText.content(
                          subtitle,
                          style: tokens.typeStyles.panelRowCaption.copyWith(
                            color: fg.withValues(alpha: 0.7),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
