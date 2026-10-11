import '../l10n_gen/app_strings.dart';
import '../components/ambient_background.dart';
import '../components/app_icon_button.dart';
import '../components/app_text_field.dart';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import '../focus/focus_memory.dart';
import '../states/empty_view.dart';
import 'browse_scope.dart';
import '../navigation/page_back_button.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../theme/rivulet_tokens.dart';
import 'filter_bar.dart';
import 'media_grid.dart';
import 'paged_title_grid.dart';
import 'title_query.dart';

import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../navigation/page_top_inset.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    required this.items,
    required this.scope,
    this.memory,
    this.onItemTap,
    this.onFeaturedOpen,
    this.onLoadMore,
    this.isLoadingMore = false,
    this.source,
    this.initialQuery,
    this.genres = const [],
    this.countries = const [],
    this.metadata = const {},
    super.key,
  });
  final List<MediaItem> items;
  final BrowseScope scope;
  final FocusMemory? memory;
  final ValueChanged<MediaItem>? onItemTap;
  final VoidCallback? onFeaturedOpen, onLoadMore;
  final bool isLoadingMore;
  final TitlePageSource? source;
  final TitleQuery? initialQuery;
  final List<TitleFilterOption<int>> genres;
  final List<TitleFilterOption<String>> countries;
  final Map<String, TitleMetadata> metadata;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final _memory = widget.memory ?? FocusMemory();
  final _scroll = ScrollController();
  final _search = TextEditingController();
  late TitleQuery _query =
      widget.initialQuery ??
      TitleQuery(
        kind: widget.scope == BrowseScope.movies
            ? TitleKind.movie
            : TitleKind.tv,
      );
  String? _focusedId;
  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.scope == BrowseScope.movies
        ? AppStrings.of(context).common_movies
        : AppStrings.of(context).library_series;
    if (widget.source != null) {
      return PagedTitleGrid(
        source: widget.source!,
        initialQuery: widget.initialQuery ?? _query,
        title: title,
        genres: widget.genres,
        countries: widget.countries,
        memory: _memory,
        onItemTap: widget.onItemTap,
      );
    }
    final filtered = widget.items.where((item) {
      final d = widget.metadata[item.id], year = d?.releaseDate?.year;
      return item.title.toLowerCase().contains(
            _search.text.trim().toLowerCase(),
          ) &&
          _query.genreIds.every((id) => d?.genreIds.contains(id) ?? false) &&
          (_query.countryCode == null ||
              (d?.countryCodes.contains(_query.countryCode) ?? false)) &&
          (_query.yearFrom == null ||
              (year != null && year >= _query.yearFrom!)) &&
          (_query.yearTo == null || (year != null && year <= _query.yearTo!));
    }).toList();
    final visible = sortTitles(filtered, _query, widget.metadata);
    // TV: the filter bar is the first focus row (DESIGN_SPEC §8.2).
    final tv = AdaptiveBehavior.of(context).formFactor == FormFactor.tv;
    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(pageTopInsetOf(context)),
          child: PageHeader(
            showBackButton: ModalRoute.of(context)?.canPop ?? false,
            title: title,
            actions: [
              if (widget.onFeaturedOpen != null)
                AppIconButton(
                  key: const ValueKey('open-detail'),
                  semanticLabel: AppStrings.of(context).library_openFeatured,
                  onActivate: widget.onFeaturedOpen,
                  icon: PhosphorIconsRegular.playCircle,
                ),
              AppIconButton(
                key: const ValueKey('library-refresh'),
                semanticLabel: AppStrings.of(context).library_refresh,
                onActivate: () => setState(() {}),
                icon: PhosphorIconsRegular.arrowsClockwise,
              ),
            ],
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: RivuletSpacing.gutter(
                  AdaptiveBehavior.of(context).formFactor,
                ),
                vertical: RivuletSpacing.s4,
              ),
              child: AppTextField(
                fieldKey: const ValueKey('library-query'),
                controller: _search,
                icon: PhosphorIconsRegular.magnifyingGlass,
                hint: AppStrings.of(context).library_searchTitle,
                onChanged: (_) => setState(() {}),
              ),
            ),
            FilterBar(
              query: _query,
              genres: widget.genres,
              countries: widget.countries,
              onChanged: (q) => setState(() => _query = q),
              primary: tv,
              autofocus: tv,
            ),
            Expanded(
              child: visible.isEmpty
                  ? EmptyView(
                      icon: widget.items.isEmpty
                          ? PhosphorIconsRegular.filmSlate
                          : PhosphorIconsRegular.funnel,
                      headline: widget.items.isEmpty
                          ? AppStrings.of(context).library_empty
                          : AppStrings.of(context).library_noMatch,
                      key: ValueKey(
                        widget.items.isEmpty
                            ? 'library-empty'
                            : 'library-filter-empty',
                      ),
                    )
                  : MediaGrid(
                      items: visible,
                      memory: _memory,
                      focusedId: _focusedId,
                      onFocused: (item) => _focusedId = item.id,
                      onItemTap: widget.onItemTap,
                      onLoadMore: widget.onLoadMore,
                      isLoadingMore: widget.isLoadingMore,
                      scrollController: _scroll,
                      autofocus: !tv,
                      pageEntry: !tv,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
