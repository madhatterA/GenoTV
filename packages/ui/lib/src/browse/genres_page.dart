import '../l10n_gen/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../components/ambient_background.dart';
import '../components/app_chip.dart';
import '../components/app_text_field.dart';
import '../components/tinted_surface.dart';
import '../focus/focus_memory.dart';
import '../focus/focusable_card.dart';
import '../focus/line_end_stop.dart';
import '../l10n/app_text.dart';
import '../navigation/page_back_button.dart';
import '../navigation/page_entry_focus.dart';
import '../platform/adaptive_behavior.dart';
import '../states/empty_view.dart';
import '../theme/rivulet_tokens.dart';
import 'title_query.dart';

/// The Genres page (DESIGN_SPEC §8.3): a Movies / TV shows switch, then a
/// grid of genre tiles. A tile opens the paged grid filtered by that genre.
import '../navigation/page_top_inset.dart';

import '../platform/form_factor.dart';

class GenresPage extends StatefulWidget {
  const GenresPage({
    required this.genresByKind,
    required this.onSeeAll,
    super.key,
  });
  final Map<TitleKind, List<TitleFilterOption<int>>> genresByKind;

  /// Opens the shared grid for [query]; [title] names the genre.
  final void Function(TitleQuery query, String title) onSeeAll;
  @override
  State<GenresPage> createState() => _GenresPageState();
}

class _GenresPageState extends State<GenresPage> {
  final _memory = FocusMemory();
  final _search = TextEditingController();
  late final FocusNode _firstTile = FocusNode(debugLabel: 'genres-first');
  PageEntry? _entry;
  TitleKind _kind = TitleKind.movie;

  @override
  void initState() {
    super.initState();
    _entry = PageEntryFocus.register(context, _firstTile);
  }

  @override
  void dispose() {
    _entry?.release(_firstTile);
    _firstTile.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sizes = AdaptiveBehavior.sizesOf(context);
    final gutter = RivuletSpacing.gutter(sizes.formFactor);
    final needle = _search.text.trim().toLowerCase();
    final genres = [
      for (final g
          in widget.genresByKind[_kind] ?? const <TitleFilterOption<int>>[])
        if (needle.isEmpty || g.label.toLowerCase().contains(needle)) g,
    ];
    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(pageTopInsetOf(context)),
          child: PageHeader(
            title: AppStrings.of(context).common_genres,
            showBackButton: ModalRoute.of(context)?.canPop ?? false,
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: gutter,
                vertical: RivuletSpacing.s4,
              ),
              child: Row(
                children: [
                  for (final kind in TitleKind.values) ...[
                    AppChip(
                      key: ValueKey('genres-kind-${kind.name}'),
                      label: kind == TitleKind.movie
                          ? AppStrings.of(context).common_movies
                          : AppStrings.of(context).common_tvShows,
                      selected: _kind == kind,
                      onActivate: () => setState(() => _kind = kind),
                    ),
                    const SizedBox(width: RivuletSpacing.s8),
                  ],
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: gutter,
                vertical: RivuletSpacing.s8,
              ),
              child: AppTextField(
                fieldKey: const ValueKey('genres-search'),
                controller: _search,
                icon: PhosphorIconsRegular.magnifyingGlass,
                hint: AppStrings.of(context).genres_search,
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(
              child: genres.isEmpty
                  ? EmptyView(headline: AppStrings.of(context).genres_noMatch)
                  : _tiles(genres, sizes, gutter),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tiles(
    List<TitleFilterOption<int>> genres,
    RivuletSizes sizes,
    double gutter,
  ) {
    final gap = RivuletSpacing.itemGap(sizes.formFactor);
    return LayoutBuilder(
      builder: (context, constraints) {
        // The tiles are 16:9 cards, so they are sized like the 16:9 cards.
        final columns = sizes.columnsFor(
          constraints.maxWidth,
          cardWidth: sizes.continueCardWidth,
        );
        final cellWidth =
            (constraints.maxWidth - 2 * gutter - (columns - 1) * gap) / columns;
        final cellHeight = cellWidth * 9 / 16;
        final room = FocusableCard.focusRoom(cellHeight);
        return FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: GridView.builder(
            key: ValueKey('genres-grid-${_kind.name}'),
            padding: EdgeInsets.fromLTRB(gutter, room, gutter, room),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisExtent: cellHeight,
              crossAxisSpacing: gap,
              mainAxisSpacing: gap,
            ),
            itemCount: genres.length,
            itemBuilder: (context, i) {
              final genre = genres[i];
              return FocusTraversalOrder(
                order: NumericFocusOrder(i.toDouble()),
                child: LineEndStop(
                  active: i % columns == columns - 1 || i == genres.length - 1,
                  child: FocusableCard(
                    focusKey: ValueKey('genre-tile-${genre.label}'),
                    surfaceId: 'genres-${_kind.name}',
                    itemId: 'genre-${genre.value}',
                    memory: _memory,
                    focusNode: i == 0 ? _firstTile : null,
                    // TV lands on the first tile; elsewhere the page entry
                    // (DESIGN_SPEC §6.4 rule 9) decides.
                    autofocus:
                        i == 0 &&
                        (AdaptiveBehavior.of(context).formFactor ==
                            FormFactor.tv),
                    semanticLabel: genre.label,
                    width: double.infinity,
                    height: cellHeight,
                    onTap: () => widget.onSeeAll(
                      TitleQuery(kind: _kind, genreIds: [genre.value]),
                      genre.label,
                    ),
                    child: _GenreTile(name: genre.label),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _GenreTile extends StatelessWidget {
  const _GenreTile({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    return TintedSurface(
      padding: const EdgeInsets.all(RivuletSpacing.s16),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Icon(
              PhosphorIconsRegular.filmSlate,
              size: 26,
              color: tokens.colors.textSecondary,
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: ExcludeSemantics(
              child: AppText.content(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tokens.typeStyles.headline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
