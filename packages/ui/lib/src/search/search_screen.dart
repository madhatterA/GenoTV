import '../l10n_gen/app_strings.dart';
import '../components/ambient_background.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:core/core.dart';
import 'package:contracts/contracts.dart';

import '../components/app_chip.dart';
import '../components/app_row.dart';
import '../components/app_text_field.dart';
import '../focus/focus_memory.dart';
import '../l10n/app_text.dart';
import '../navigation/page_entry_focus.dart';
import '../navigation/page_top_inset.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../states/empty_view.dart';
import '../states/error_view.dart';
import '../states/loading_view.dart';
import '../theme/rivulet_tokens.dart';
import 'search_controller.dart';

/// Keeps recent searches, debounce and keyboard input above the shared paged grid.
import '../browse/paged_title_grid.dart';
import '../browse/title_query.dart';

import 'package:phosphor_flutter/phosphor_flutter.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    this.search,
    this.source,
    this.genresByKind = const {},
    this.countries = const [],
    this.controller,
    this.onItemTap,
    super.key,
  }) : assert(search != null || source != null);

  final LibrarySearchFunction? search;
  final TitlePageSource? source;
  final Map<TitleKind, List<TitleFilterOption<int>>> genresByKind;
  final List<TitleFilterOption<String>> countries;
  final LibrarySearchController? controller;
  final ValueChanged<MediaItem>? onItemTap;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final LibrarySearchController _controller =
      widget.controller ??
      LibrarySearchController(search: widget.search ?? _searchPage);
  late final TextEditingController _textController = TextEditingController(
    text: _controller.query,
  );
  late final FocusNode _fieldNode = FocusNode(debugLabel: 'search-field');
  late final FocusNode _firstResultNode = FocusNode(
    debugLabel: 'search-first-result',
  );
  final FocusMemory _memory = FocusMemory();
  TitleKind _kind = TitleKind.movie;
  TitlePage? _firstPage;
  TitleQuery? _firstQuery;

  Future<List<MediaItem>> _searchPage(String text) async {
    final query = TitleQuery(
      kind: _kind,
      base: TitleBase.search,
      searchText: _controller.query,
    );
    final result = await widget.source!(query, 1);
    _firstQuery = query;
    _firstPage = result;
    return result.items;
  }

  Future<TitlePage> _pageSource(TitleQuery query, int page) async {
    if (widget.source != null) {
      if (page == 1 && query == _firstQuery) return _firstPage!;
      return widget.source!(query, page);
    }
    // The existing finite-library callback uses the same grid as the paged catalogue.
    final items = _controller.flatResults
        .where(
          (item) =>
              (query.kind == TitleKind.movie
                  ? item.kind == MediaKind.movie
                  : item.kind == MediaKind.episode) &&
              (query.yearFrom == null ||
                  (item.year != null && item.year! >= query.yearFrom!)) &&
              (query.yearTo == null ||
                  (item.year != null && item.year! <= query.yearTo!)),
        )
        .toList();
    return TitlePage(
      items: items,
      metadata: {
        for (final item in items)
          item.id: TitleMetadata(
            releaseDate: item.year == null ? null : DateTime(item.year!),
          ),
      },
    );
  }

  Widget _grid() => PagedTitleGrid(
    key: const ValueKey('search-results'),
    source: _pageSource,
    initialQuery: TitleQuery(
      kind: _kind,
      base: TitleBase.search,
      searchText: _controller.query,
    ),
    title: AppStrings.of(context).common_search,
    showAppBar: false,
    autofocus: false,
    firstFocusNode: _firstResultNode,
    memory: _memory,
    genres: widget.genresByKind[_kind] ?? const [],
    countries: widget.countries,
    onItemTap: widget.onItemTap,
    empty: _noResults(),
  );

  Widget _noResults() => EmptyView(
    key: const ValueKey<String>('search-no-results'),
    icon: PhosphorIconsRegular.magnifyingGlass,
    headline: AppStrings.of(context).search_noResults,
    body: AppStrings.of(context).search_noResultsBody,
  );

  PageEntry? _entry;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
    _entry = PageEntryFocus.register(context, _fieldNode);
    _entry?.typeAhead = _typeAhead;
  }

  /// DESIGN_SPEC §6.5: typing a printable character while focus is elsewhere
  /// moves focus to the field and inserts it.
  void _typeAhead(String character) {
    _fieldNode.requestFocus();
    final text = _textController.text + character;
    _textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _controller.updateQuery(text);
  }

  @override
  void dispose() {
    _entry?.release(_fieldNode);
    _entry?.typeAhead = null;
    _controller.removeListener(_changed);
    if (widget.controller == null) _controller.dispose();
    _textController.dispose();
    _fieldNode.dispose();
    _firstResultNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formFactor = AdaptiveBehavior.of(context).formFactor;
    final gutter = RivuletSpacing.gutter(formFactor);
    // The field and the recents share one centred column on desktop (§8.4).
    final maxWidth = formFactor == FormFactor.desktop ? 720.0 : double.infinity;
    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Focus(
          canRequestFocus: false,
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowUp &&
                !_fieldNode.hasFocus) {
              _fieldNode.requestFocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  // Start below the floating menu pill row.
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    pageTopInsetOf(context),
                    gutter,
                    RivuletSpacing.s8,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: FocusTraversalOrder(
                        order: const NumericFocusOrder(0),
                        child: Focus(
                          canRequestFocus: false,
                          onKeyEvent: (_, event) {
                            if (event is KeyDownEvent &&
                                event.logicalKey ==
                                    LogicalKeyboardKey.arrowDown &&
                                _controller.status ==
                                    LibrarySearchStatus.results) {
                              _firstResultNode.requestFocus();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: AppTextField(
                            fieldKey: const ValueKey<String>('search-field'),
                            controller: _textController,
                            focusNode: _fieldNode,
                            autofocus: true,
                            icon: PhosphorIconsRegular.magnifyingGlass,
                            hint: AppStrings.of(context).search_hint,
                            onChanged: _controller.updateQuery,
                            onSubmitted: (_) {
                              if (_controller.status ==
                                  LibrarySearchStatus.results) {
                                _firstResultNode.requestFocus();
                              }
                            },
                            onTapOutside: (_) => _fieldNode.unfocus(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: gutter,
                    vertical: RivuletSpacing.s8,
                  ),
                  child: Row(
                    children: <Widget>[
                      for (final kind in TitleKind.values) ...<Widget>[
                        AppChip(
                          key: ValueKey('title-kind-${kind.name}'),
                          label: kind == TitleKind.movie
                              ? AppStrings.of(context).common_movies
                              : AppStrings.of(context).common_tv,
                          selected: _kind == kind,
                          onActivate: () {
                            if (_kind == kind) return;
                            setState(() => _kind = kind);
                            if (widget.source != null) {
                              _controller.retry();
                            }
                          },
                        ),
                        const SizedBox(width: RivuletSpacing.s8),
                      ],
                    ],
                  ),
                ),
                Expanded(child: _body(maxWidth)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(double maxWidth) {
    switch (_controller.status) {
      case LibrarySearchStatus.prompt:
        return EmptyView(
          key: const ValueKey<String>('search-prompt'),
          icon: PhosphorIconsRegular.magnifyingGlass,
          headline: AppStrings.of(context).search_promptTitle,
          body: AppStrings.of(context).search_promptBody,
        );
      case LibrarySearchStatus.recents:
        return _RecentsList(
          key: const ValueKey<String>('search-recents'),
          maxWidth: maxWidth,
          terms: _controller.recents,
          onSelected: (term) {
            _textController.value = TextEditingValue(
              text: term,
              selection: TextSelection.collapsed(offset: term.length),
            );
            _controller.activateRecent(term);
          },
        );
      case LibrarySearchStatus.loading:
        return const LoadingView(key: ValueKey<String>('search-loading'));
      case LibrarySearchStatus.noResults:
        return widget.source != null ? _grid() : _noResults();
      case LibrarySearchStatus.error:
        return ErrorView(
          key: const ValueKey<String>('search-error'),
          failure: _SearchFailure(_controller.error),
          onRetry: _controller.retry,
        );
      case LibrarySearchStatus.results:
        return _grid();
    }
  }

  void _changed() {
    if (mounted && _textController.text != _controller.query) {
      _textController.value = TextEditingValue(
        text: _controller.query,
        selection: TextSelection.collapsed(offset: _controller.query.length),
      );
    }
    if (mounted) setState(() {});
  }
}

/// Up-to-10 recent search terms, shown when the field is empty/under
/// threshold and recents exist (`phase-03` Decisions: "Recent capacity 10"):
/// a "Recent searches" heading over one [AppRowGroup] (DESIGN_SPEC §8.4).
class _RecentsList extends StatelessWidget {
  const _RecentsList({
    required this.terms,
    required this.onSelected,
    required this.maxWidth,
    super.key,
  });

  final List<String> terms;
  final ValueChanged<String> onSelected;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final gutter = RivuletSpacing.gutter(
      AdaptiveBehavior.of(context).formFactor,
    );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: gutter,
            vertical: RivuletSpacing.s8,
          ),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(
                left: RivuletSpacing.s4,
                bottom: RivuletSpacing.s12,
              ),
              child: AppText(
                AppStrings.of(context).search_recent,
                style: tokens.typeStyles.headline.copyWith(
                  color: tokens.colors.textSecondary,
                ),
              ),
            ),
            AppRowGroup(
              children: <Widget>[
                for (var i = 0; i < terms.length; i++)
                  FocusTraversalOrder(
                    order: NumericFocusOrder(i.toDouble()),
                    child: AppRow(
                      key: ValueKey<String>('recent-${terms[i]}'),
                      icon: PhosphorIconsRegular.clockCounterClockwise,
                      label: terms[i],
                      onActivate: () => onSelected(terms[i]),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Preserves a wrapped AppFailure's own code (transport/playback/etc. already
// map to a specific message in `failure_messages.dart`) instead of always
// collapsing to the generic 'app.unexpected' copy Rivulet never shows
// (`SearchCells.swift:354-360` passes the real `message` through).
final class _SearchFailure extends AppFailure {
  _SearchFailure(Object? cause)
    : super(
        code: cause is AppFailure ? cause.code : 'app.unexpected',
        message: cause is AppFailure ? cause.message : 'Search is unavailable',
        cause: cause ?? StateError('search failed'),
      );
}
