import '../l10n_gen/app_strings.dart';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import '../components/ambient_background.dart';
import '../browse/media_row.dart';
import '../browse/paged_title_grid.dart';
import '../browse/title_query.dart';
import '../components/app_chip.dart';
import '../components/app_text_button.dart';
import '../components/artwork.dart';
import '../components/tinted_surface.dart';
import '../focus/focus_memory.dart';
import '../l10n/app_text.dart';
import '../navigation/page_top_inset.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../theme/rivulet_tokens.dart';
import 'movie_detail_presentation.dart';

import 'package:phosphor_flutter/phosphor_flutter.dart';

/// The person page (DESIGN_SPEC §8): the portrait left of the text on desktop
/// and TV, above it on a phone; name, role, the biography (six lines, "More"
/// expands it) and the Movies/TV chips, then the filmography grid.
class PersonDetailScreen extends StatefulWidget {
  const PersonDetailScreen({
    required this.person,
    required this.memory,
    required this.source,
    this.initialKind = TitleKind.movie,
    this.genresByKind = const {},
    this.countries = const [],
    this.onTitleTap,
    super.key,
  });
  final CastMember person;
  final FocusMemory memory;
  final TitlePageSource source;
  final TitleKind initialKind;
  final Map<TitleKind, List<TitleFilterOption<int>>> genresByKind;
  final List<TitleFilterOption<String>> countries;
  final ValueChanged<MediaItem>? onTitleTap;
  @override
  State<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends State<PersonDetailScreen> {
  late TitleKind _kind = widget.initialKind;
  bool _bioExpanded = false;
  List<MediaItem> _known = const <MediaItem>[];
  int _knownRequest = 0;

  TitleQuery get _query => TitleQuery(
    kind: _kind,
    base: widget.person.id == null ? TitleBase.discover : TitleBase.person,
    personId: widget.person.id,
    personRole: widget.person.isCrew
        ? TitlePersonRole.crew
        : TitlePersonRole.cast,
  );

  @override
  void initState() {
    super.initState();
    _loadKnown();
  }

  /// "Known for": the first 10 titles of the filmography list below.
  Future<void> _loadKnown() async {
    final request = ++_knownRequest;
    try {
      final page = await widget.source(_query, 1);
      if (mounted && request == _knownRequest) {
        setState(() => _known = page.items.take(10).toList());
      }
    } on Object {
      // The grid below shows and retries a failed load; the row just stays
      // empty.
      if (mounted && request == _knownRequest) {
        setState(() => _known = const <MediaItem>[]);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final styles = tokens.typeStyles;
    final person = widget.person;
    final sizes = AdaptiveBehavior.sizesOf(context);
    final phone = sizes.formFactor == FormFactor.phone;
    final gutter = RivuletSpacing.gutter(sizes.formFactor);
    final photo = person.photo;
    final portrait = SizedBox.square(
      key: const ValueKey('person-portrait'),
      dimension: sizes.posterWidth,
      child: photo == null
          ? TintedSurface(
              radius: RivuletRadius.full,
              child: Icon(
                PhosphorIconsRegular.user,
                size: sizes.posterWidth / 2,
                color: tokens.colors.textTertiary,
              ),
            )
          : ClipOval(
              child: ArtworkView(
                requestId: photo.toString(),
                provider: ArtworkResolverScope.of(context)(photo.toString()),
                aspect: 1,
                fallbackKind: MediaKind.other,
                alignment: Alignment.topCenter,
              ),
            ),
    );
    final biography = person.biography;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AppText.content(
          person.name,
          key: const ValueKey('person-name'),
          style: styles.title,
        ),
        if (person.role != null)
          AppText.content(
            person.role!,
            style: styles.body.copyWith(color: tokens.colors.textSecondary),
          ),
        if (biography != null && biography.isNotEmpty) ...<Widget>[
          const SizedBox(height: RivuletSpacing.s12),
          _Biography(
            text: biography,
            style: styles.body.copyWith(color: tokens.colors.textSecondary),
            expanded: _bioExpanded,
            onToggle: () => setState(() => _bioExpanded = !_bioExpanded),
          ),
        ],
        const SizedBox(height: RivuletSpacing.s12),
        Wrap(
          spacing: RivuletSpacing.s8,
          runSpacing: RivuletSpacing.s8,
          children: <Widget>[
            for (final kind in TitleKind.values)
              AppChip(
                key: ValueKey('title-kind-${kind.name}'),
                label: kind == TitleKind.movie
                    ? AppStrings.of(context).common_movies
                    : AppStrings.of(context).common_tv,
                selected: _kind == kind,
                onActivate: () {
                  setState(() => _kind = kind);
                  _loadKnown();
                },
              ),
          ],
        ),
      ],
    );
    return AmbientBackground(
      key: const ValueKey('person-detail-page'),
      child: SafeArea(
        top: false,
        child: PagedTitleGrid(
          source: widget.source,
          memory: widget.memory,
          title: person.name,
          showAppBar: false,
          initialQuery: _query,
          genres: widget.genresByKind[_kind] ?? const [],
          countries: widget.countries,
          onItemTap: widget.onTitleTap,
          header: Padding(
            padding: EdgeInsets.only(bottom: RivuletSpacing.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    pageTopInsetOf(context),
                    gutter,
                    RivuletSpacing.s16,
                  ),
                  child: phone
                      ? SizedBox(
                          width: double.infinity,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              portrait,
                              const SizedBox(height: RivuletSpacing.s16),
                              text,
                            ],
                          ),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            portrait,
                            const SizedBox(width: RivuletSpacing.s24),
                            Expanded(child: text),
                          ],
                        ),
                ),
                if (_known.isNotEmpty)
                  MediaRow(
                    key: const ValueKey('person-known-for'),
                    title: AppStrings.of(context).person_knownFor,
                    items: _known,
                    memory: widget.memory,
                    onFocused: (_) {},
                    onItemTap: widget.onTitleTap,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The biography: six lines, then a "More" button that expands it inline.
/// A biography that fits in six lines has no button.
class _Biography extends StatelessWidget {
  const _Biography({
    required this.text,
    required this.style,
    required this.expanded,
    required this.onToggle,
  });

  static const int _collapsedLines = 6;

  final String text;
  final TextStyle style;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final tooLong = (TextPainter(
        text: TextSpan(text: text, style: style),
        maxLines: _collapsedLines,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: constraints.maxWidth)).didExceedMaxLines;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AppText.content(
            text,
            paragraph: true,
            key: const ValueKey('person-bio'),
            maxLines: expanded ? null : _collapsedLines,
            overflow: expanded ? null : TextOverflow.ellipsis,
            style: style,
          ),
          if (tooLong)
            AppTextButton(
              key: const ValueKey('person-bio-toggle'),
              label: expanded
                  ? AppStrings.of(context).common_less
                  : AppStrings.of(context).common_more,
              onActivate: onToggle,
            ),
        ],
      );
    },
  );
}
