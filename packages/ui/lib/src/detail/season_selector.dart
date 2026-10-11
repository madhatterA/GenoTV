import 'package:flutter/material.dart';

import '../components/app_chip.dart';
import '../theme/rivulet_tokens.dart';
import 'series_view_model.dart';

/// The season chips row above the episode list (DESIGN_SPEC §8.5, §9.7): one
/// [AppChip] per season, the selected one filled with `accent`. Choosing a
/// chip swaps the episodes in place.
class SeasonSelector extends StatelessWidget {
  const SeasonSelector({
    required this.seasons,
    required this.selected,
    required this.onSelected,
    required this.padding,
    this.groupNode,
    super.key,
  });

  final List<SeriesSeason> seasons;
  final int? selected;
  final ValueChanged<int> onSelected;

  /// The page gutter on both sides.
  final EdgeInsetsGeometry padding;

  /// A node that is an ancestor of every chip, so the page can find the
  /// selected chip's focus (Down from the hero enters on it).
  final FocusNode? groupNode;

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: groupNode,
    canRequestFocus: false,
    skipTraversal: true,
    includeSemantics: false,
    child: SizedBox(
      key: const ValueKey<String>('season-selector'),
      height: RivuletSizes.touchHitTarget,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: seasons.length,
        separatorBuilder: (_, _) => const SizedBox(width: RivuletSpacing.s8),
        itemBuilder: (_, index) {
          final season = seasons[index];
          return Center(
            child: AppChip(
              key: ValueKey<String>('season-chip-$index'),
              label: season.title,
              selected: season.number == selected,
              onActivate: () => onSelected(season.number),
            ),
          );
        },
      ),
    ),
  );
}
