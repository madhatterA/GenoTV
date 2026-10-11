import '../l10n_gen/app_strings.dart';

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../components/ambient_background.dart';
import '../components/app_button.dart';
import '../focus/focus_memory.dart';
import '../states/empty_view.dart';
import '../navigation/page_back_button.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import 'filter_bar.dart';
import 'media_grid.dart';
import 'title_query.dart';

import '../navigation/page_top_inset.dart';

class PagedTitleGrid extends StatefulWidget {
  const PagedTitleGrid({
    required this.source,
    required this.initialQuery,
    required this.title,
    this.genres = const [],
    this.countries = const [],
    this.onItemTap,
    this.memory,
    this.header,
    this.showAppBar = true,
    this.firstFocusNode,
    this.autofocus = true,
    this.showFilters = true,
    this.empty,
    super.key,
  });
  final TitlePageSource source;
  final TitleQuery initialQuery;
  final String title;
  final List<TitleFilterOption<int>> genres;
  final List<TitleFilterOption<String>> countries;
  final ValueChanged<MediaItem>? onItemTap;
  final FocusMemory? memory;
  final Widget? header;
  final bool showAppBar, autofocus;

  /// False for fixed lists (e.g. Liked) that the filter controls cannot apply to.
  final bool showFilters;

  /// Shown when nothing matches (an [EmptyView]); the default says no title
  /// matches the filter.
  final Widget? empty;
  final FocusNode? firstFocusNode;
  @override
  State<PagedTitleGrid> createState() => _PagedTitleGridState();
}

class _PagedTitleGridState extends State<PagedTitleGrid> {
  late TitleQuery _query = widget.initialQuery;
  late final _memory = widget.memory ?? FocusMemory();
  final _scroll = ScrollController();
  List<MediaItem> _items = [];
  Map<String, TitleMetadata> _metadata = {};
  int? _next = 1;
  int _generation = 0;
  bool _loading = false;
  Object? _error;
  String? _focusedId;
  final FocusNode _first = FocusNode(debugLabel: 'paged-grid-first');
  bool _entryPending = true;
  bool _entryFocusMoved = false;

  void _observeEntryFocus() {
    if (_entryPending) _entryFocusMoved = true;
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_nearEnd);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduleMicrotask(() {
        if (!mounted) return;
        FocusManager.instance.applyFocusChangesIfNeeded();
        FocusManager.instance.addListener(_observeEntryFocus);
      });
    });
    unawaited(_load());
  }

  @override
  void didUpdateWidget(PagedTitleGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQuery != widget.initialQuery) {
      _change(widget.initialQuery);
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_observeEntryFocus);
    _first.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _nearEnd() {
    if (_scroll.hasClients &&
        _scroll.position.extentAfter <= _scroll.position.viewportDimension) {
      unawaited(_load());
    }
  }

  void _change(TitleQuery query) {
    if (query == _query) return;
    setState(() {
      _query = query;
      _generation++;
      _items = [];
      _metadata = {};
      _next = 1;
      _error = null;
      _focusedId = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    unawaited(_load());
  }

  Future<void> _load({bool retry = false}) async {
    if (_loading || _next == null || (_error != null && !retry)) return;
    final generation = _generation, query = _query, page = _next!;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.source(query, page);
      if (!mounted) return;
      if (generation == _generation) {
        setState(() {
          final ids = _items.map((i) => i.id).toSet();
          _items = [
            ..._items,
            ...result.items.where((i) => !ids.contains(i.id)),
          ];
          _metadata = {..._metadata, ...result.metadata};
          if (query.base == TitleBase.search ||
              query.base == TitleBase.trending) {
            _items = sortTitles(_items, query, _metadata);
          }
          _next = page >= 500 ? null : result.nextPage;
          if (_entryPending && _items.isNotEmpty) {
            final chipsPrimary =
                AdaptiveBehavior.of(context).formFactor == FormFactor.tv &&
                widget.showFilters;
            final focusEntry =
                widget.showAppBar &&
                widget.autofocus &&
                !chipsPrimary &&
                !_entryFocusMoved;
            _entryPending = false;
            if (focusEntry) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && generation == _generation) {
                  (widget.firstFocusNode ?? _first).requestFocus();
                }
              });
            }
          }
        });
      }
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (generation != _generation) {
          unawaited(_load());
        } else if (_error == null && _next != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              if (_items.isEmpty) {
                unawaited(_load());
              } else {
                _nearEnd();
              }
            }
          });
        }
      }
    }
  }

  /// The failed-page notice: under the last line when titles are showing,
  /// full page when none are.
  Widget _retry({required bool fullPage}) {
    final retry = AppButton.primary(
      key: const ValueKey('title-page-retry'),
      label: AppStrings.of(context).common_retry,
      onActivate: () => _load(retry: true),
    );
    return fullPage
        ? EmptyView(
            icon: PhosphorIconsRegular.cloudSlash,
            headline: AppStrings.of(context).grid_loadFailed,
            action: retry,
          )
        : retry;
  }

  @override
  Widget build(BuildContext context) {
    // TV: the filter bar is the first focus row (DESIGN_SPEC §8.2).
    final chipsPrimary =
        AdaptiveBehavior.of(context).formFactor == FormFactor.tv &&
        widget.showAppBar &&
        widget.showFilters;
    final filterBar = widget.showFilters
        ? FilterBar(
            query: _query,
            onChanged: _change,
            genres: widget.genres,
            countries: widget.countries,
            primary: chipsPrimary,
            autofocus: chipsPrimary && widget.autofocus,
          )
        : null;
    final headerInGrid = widget.header != null && _items.isNotEmpty;
    final page = Scaffold(
      backgroundColor: Colors.transparent,
      appBar: widget.showAppBar
          ? PreferredSize(
              preferredSize: Size.fromHeight(pageTopInsetOf(context)),
              child: PageHeader(
                title: widget.title,
                showBackButton: ModalRoute.of(context)?.canPop ?? false,
              ),
            )
          : null,
      body: Column(
        children: [
          // Without titles the header and the filters stay put; with titles
          // they scroll with the grid.
          if (widget.header != null && !headerInGrid)
            Flexible(child: SingleChildScrollView(child: widget.header!)),
          if (!headerInGrid) ?filterBar,
          Expanded(
            child: _items.isEmpty
                ? (_loading
                      ? MediaGridSkeleton(memory: _memory)
                      : _error != null
                      ? _retry(fullPage: true)
                      : widget.empty ??
                            EmptyView(
                              key: const ValueKey('title-grid-empty'),
                              headline: AppStrings.of(context).library_noMatch,
                            ))
                : MediaGrid(
                    key: ValueKey(_generation),
                    items: _items,
                    memory: _memory,
                    firstFocusNode: widget.firstFocusNode ?? _first,
                    autofocus:
                        widget.autofocus && !chipsPrimary && !_entryFocusMoved,
                    focusedId: _focusedId,
                    onFocused: (item) {
                      _focusedId = item.id;
                    },
                    onItemTap: widget.onItemTap,
                    onLoadMore: _load,
                    isLoadingMore: _loading,
                    scrollController: _scroll,
                    pageEntry: widget.showAppBar && !chipsPrimary,
                    header: headerInGrid
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[widget.header!, ?filterBar],
                          )
                        : null,
                    trailingTile: _error != null
                        ? _retry(fullPage: false)
                        : null,
                  ),
          ),
        ],
      ),
    );
    return widget.showAppBar ? AmbientBackground(child: page) : page;
  }
}
