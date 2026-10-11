import '../l10n_gen/app_strings.dart';
import '../l10n/formatters.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../components/app_chip.dart';
import '../focus/line_end_stop.dart';
import '../navigation/page_entry_focus.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../theme/rivulet_tokens.dart';
import 'choice_dialog.dart';
import 'title_query.dart';
import 'year_picker.dart';

/// The filter and sort bar of the paged grids (DESIGN_SPEC §8.2): a row of
/// [AppChip]s that scrolls sideways — year, country, one chip per genre, then
/// a `Clear` chip while any filter is active, and the sort chip with its
/// `sortAscending` icon at the end. Chips are keyed
/// `filter-chip-<i>` in that order.
class FilterBar extends StatefulWidget {
  const FilterBar({
    required this.query,
    required this.onChanged,
    this.genres = const [],
    this.countries = const [],
    this.primary = false,
    this.autofocus = false,
    super.key,
  });
  final TitleQuery query;
  final ValueChanged<TitleQuery> onChanged;
  final List<TitleFilterOption<int>> genres;
  final List<TitleFilterOption<String>> countries;

  /// Registers the first chip as the page's primary focus element (TV,
  /// DESIGN_SPEC §8.2: the bar is the first focus row).
  final bool primary;

  /// Takes focus on mount (TV lands on the first chip).
  final bool autofocus;

  @override
  State<FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<FilterBar> {
  late final FocusNode _first = FocusNode(debugLabel: 'filter-first');
  PageEntry? _entry;

  TitleQuery get query => widget.query;
  ValueChanged<TitleQuery> get onChanged => widget.onChanged;
  List<TitleFilterOption<int>> get genres => widget.genres;
  List<TitleFilterOption<String>> get countries => widget.countries;

  @override
  void initState() {
    super.initState();
    if (widget.primary) _entry = PageEntryFocus.register(context, _first);
  }

  @override
  void dispose() {
    _entry?.release(_first);
    _first.dispose();
    super.dispose();
  }

  static String _sortLabel(AppStrings s, TitleSort sort) => switch (sort) {
    TitleSort.popularity => s.sort_popularity,
    TitleSort.rating => s.sort_rating,
    TitleSort.releaseDate => s.sort_releaseDate,
    TitleSort.title => s.sort_titleAz,
  };

  Future<void> _pickYear(BuildContext context) async {
    final r = await showYearPicker(
      context,
      from: query.yearFrom,
      to: query.yearTo,
    );
    if (r == null) return;
    onChanged(
      r.from == null
          ? query.copyWith(clearYears: true)
          : query.copyWith(yearFrom: r.from, yearTo: r.to),
    );
  }

  Future<void> _pickCountry(BuildContext context) async {
    final picked = await showChoiceDialog<String>(
      context,
      title: AppStrings.of(context).filter_country,
      current: query.countryCode ?? '',
      options: [
        (value: '', label: AppStrings.of(context).filter_allCountries),
        for (final o in countries) (value: o.value, label: o.label),
      ],
    );
    if (picked == null) return;
    onChanged(
      picked == ''
          ? query.copyWith(clearCountry: true)
          : query.copyWith(countryCode: picked),
    );
  }

  Future<void> _pickSort(BuildContext context) async {
    final picked = await showChoiceDialog<TitleSort>(
      context,
      title: AppStrings.of(context).filter_sort,
      current: query.sort,
      options: [
        for (final e in TitleSort.values)
          (value: e, label: _sortLabel(AppStrings.of(context), e)),
      ],
    );
    if (picked != null) onChanged(query.copyWith(sort: picked));
  }

  @override
  Widget build(BuildContext context) {
    final q = query;
    final formFactor = AdaptiveBehavior.of(context).formFactor;
    final chips = <AppChip Function(Key key)>[
      (key) => AppChip(
        key: key,
        focusNode: _first,
        autofocus: widget.autofocus,
        label: q.yearFrom == null
            ? AppStrings.of(context).common_anyYear
            : q.yearFrom == q.yearTo
            ? formatYear(context, q.yearFrom!)
            : AppStrings.of(context).filter_yearRange(
                formatYear(context, q.yearFrom!),
                formatYear(context, q.yearTo ?? q.yearFrom!),
              ),
        selected: q.yearFrom != null,
        onActivate: () => _pickYear(context),
      ),
      if (countries.isNotEmpty)
        (key) => AppChip(
          key: key,
          label: q.countryCode == null
              ? AppStrings.of(context).filter_allCountries
              : countries
                    .firstWhere(
                      (o) => o.value == q.countryCode,
                      orElse: () =>
                          TitleFilterOption(q.countryCode!, q.countryCode!),
                    )
                    .label,
          selected: q.countryCode != null,
          onActivate: () => _pickCountry(context),
        ),
      for (final o in genres)
        (key) => AppChip(
          key: key,
          label: o.label,
          selected: q.genreIds.contains(o.value),
          onActivate: () => onChanged(
            q.copyWith(
              genreIds: q.genreIds.contains(o.value)
                  ? q.genreIds.where((id) => id != o.value).toList()
                  : [...q.genreIds, o.value],
            ),
          ),
        ),
      if (q.genreIds.isNotEmpty || q.countryCode != null || q.yearFrom != null)
        (key) => AppChip(
          key: key,
          icon: PhosphorIconsRegular.x,
          label: AppStrings.of(context).common_clear,
          onActivate: () => onChanged(
            q.copyWith(genreIds: [], clearCountry: true, clearYears: true),
          ),
        ),
      (key) => AppChip(
        key: key,
        icon: PhosphorIconsRegular.sortAscending,
        label: AppStrings.of(context)
            .filter_sortBy(_sortLabel(AppStrings.of(context), q.sort)),
        onActivate: () => _pickSort(context),
      ),
    ];
    // The ring and hover growth of a chip sit outside its box.
    const room = RivuletSpacing.s4;
    final chipHeight = formFactor == FormFactor.tv ? 44.0 : 36.0;
    final height =
        math.max(chipHeight, AdaptiveBehavior.hitTargetOf(context)) + 2 * room;
    return SizedBox(
      width: double.infinity,
      height: height,
      // Every chip is built so directional focus can reach the far end.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: RivuletSpacing.gutter(formFactor),
          vertical: room,
        ),
        child: Row(
          children: [
            for (var i = 0; i < chips.length; i++) ...[
              if (i > 0) const SizedBox(width: RivuletSpacing.s8),
              LineEndStop(
                active: i == chips.length - 1,
                child: chips[i](ValueKey<String>('filter-chip-$i')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
