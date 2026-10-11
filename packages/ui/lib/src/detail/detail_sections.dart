import '../l10n_gen/app_strings.dart';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../browse/media_shelf.dart';
import '../components/app_chip.dart';
import '../components/app_row.dart';
import '../components/artwork.dart';
import '../components/tinted_surface.dart';
import '../focus/focus_memory.dart';
import '../focus/focusable_action.dart';
import '../focus/focusable_card.dart';
import '../l10n/app_text.dart';
import '../platform/adaptive_behavior.dart';
import '../theme/rivulet_tokens.dart';
import 'movie_detail_presentation.dart';

/// Below-the-hero sections (DESIGN_SPEC §8.5), each omitted when empty:
/// People, "More like this", Trailers, tags, About, then the library actions
/// (Watched, Watchlist, Info) that used to sit in the hero's action row.
/// Reuses [MediaShelf] for the two title rows.
import '../platform/form_factor.dart';

class DetailSections extends StatelessWidget {
  const DetailSections({
    required this.presentation,
    required this.memory,
    this.onRelatedTap,
    this.onTrailerTap,
    this.onLinkTap,
    this.onCastTap,
    this.onToggleWatched,
    this.onToggleWatchlist,
    this.onInfo,
    super.key,
  });

  final MovieDetailPresentation presentation;
  final FocusMemory memory;
  final ValueChanged<MediaItem>? onRelatedTap;
  final ValueChanged<MediaItem>? onTrailerTap;
  final ValueChanged<DetailLink>? onLinkTap;
  final ValueChanged<CastMember>? onCastTap;
  final VoidCallback? onToggleWatched;
  final VoidCallback? onToggleWatchlist;
  final VoidCallback? onInfo;

  @override
  Widget build(BuildContext context) {
    final formFactor = AdaptiveBehavior.of(context).formFactor;
    final sections = <Widget>[
      if (presentation.cast.isNotEmpty)
        _PeopleSection(
          key: const ValueKey<String>('detail-section-cast'),
          cast: presentation.cast,
          onTap: onCastTap,
        ),
      if (presentation.related.isNotEmpty)
        MediaShelf(
          key: const ValueKey<String>('detail-section-related'),
          keyPrefix: 'detail-related',
          title: AppStrings.of(context).detail_moreLikeThis,
          items: presentation.related,
          memory: memory,
          onFocused: (_) {},
          onItemTap: onRelatedTap,
          autofocus: false,
        ),
      if (presentation.trailers.isNotEmpty)
        MediaShelf(
          key: const ValueKey<String>('detail-section-trailers'),
          keyPrefix: 'detail-trailers',
          title: AppStrings.of(context).detail_trailers,
          items: presentation.trailers,
          memory: memory,
          onFocused: (_) {},
          onItemTap: onTrailerTap,
          autofocus: false,
        ),
      if (presentation.links.any((l) => l.isTag))
        _TagsSection(links: presentation.links, onTap: onLinkTap),
      if (presentation.about.isNotEmpty)
        _AboutSection(
          key: const ValueKey<String>('detail-section-about'),
          facts: presentation.about,
        ),
      if (onToggleWatched != null ||
          onToggleWatchlist != null ||
          onInfo != null)
        _LibrarySection(
          isWatched: presentation.isWatched,
          isInWatchlist: presentation.isInWatchlist,
          onToggleWatched: onToggleWatched,
          onToggleWatchlist: onToggleWatchlist,
          onInfo: onInfo,
        ),
    ];
    if (sections.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var i = 0; i < sections.length; i++) ...<Widget>[
          if (i > 0) SizedBox(height: RivuletSpacing.rowGap(formFactor)),
          Builder(
            builder: (context) => Focus(
              canRequestFocus: false,
              onFocusChange: (focused) {
                if (focused &&
                    (AdaptiveBehavior.of(context).formFactor ==
                        FormFactor.tv)) {
                  FocusableCard.revealSection(context);
                }
              },
              child: sections[i],
            ),
          ),
        ],
      ],
    );
  }
}

/// A section's left and right inset: the page gutter.
EdgeInsets _gutterOf(BuildContext context) => EdgeInsets.symmetric(
  horizontal: RivuletSpacing.gutter(AdaptiveBehavior.of(context).formFactor),
);

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: _gutterOf(context).copyWith(bottom: RivuletSpacing.s12),
    child: Semantics(
      header: true,
      child: AppText(
        title,
        style: RivuletTokens.of(context).typeStyles.headline,
      ),
    ),
  );
}

/// At most [maxTags] compact chips: genres first, then keywords.
const int maxTags = 7;

class _TagsSection extends StatelessWidget {
  const _TagsSection({required this.links, required this.onTap});

  final List<DetailLink> links;
  final ValueChanged<DetailLink>? onTap;

  @override
  Widget build(BuildContext context) {
    final tags = <DetailLink>[
      ...links.where((l) => l.filter == 'with_genres'),
      ...links.where((l) => l.filter == 'with_keywords'),
    ].take(maxTags);
    return Padding(
      padding: _gutterOf(context),
      child: Wrap(
        spacing: RivuletSpacing.s8,
        runSpacing: RivuletSpacing.s8,
        children: <Widget>[
          for (final link in tags)
            Tooltip(
              message: AppStrings.of(context).detail_browse(link.label),
              child: AppChip(
                key: ValueKey<String>(
                  'detail-link-${link.filter}-${link.value}',
                ),
                label: link.label,
                onActivate: onTap == null ? null : () => onTap!(link),
              ),
            ),
        ],
      ),
    );
  }
}

/// Circular portraits with the name (and role) under them (DESIGN_SPEC §8.5).
class _PeopleSection extends StatelessWidget {
  const _PeopleSection({required this.cast, required this.onTap, super.key});

  final List<CastMember> cast;
  final ValueChanged<CastMember>? onTap;

  static const double _thumbWidth = 84;
  static const double _thumbHeight = 126;
  static const double _cardWidth = 96;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final formFactor = AdaptiveBehavior.of(context).formFactor;
    final label = tokens.typeStyles.label.copyWith(
      color: tokens.colors.textPrimary,
    );
    final caption = tokens.typeStyles.caption;
    final scaler = MediaQuery.textScalerOf(context);
    double line(TextStyle style, double faHeight) =>
        (scaler.scale(style.fontSize!) *
                (isFarsi(context) ? faHeight : style.height!))
            .ceilToDouble();
    final gutter = RivuletSpacing.gutter(formFactor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SectionTitle(AppStrings.of(context).detail_cast),
        SizedBox(
          height:
              // Two lines each: names and roles show in full (owner 2026-10-10).
              _thumbHeight +
              RivuletSpacing.s8 +
              2 * line(label, RivuletTypeStyles.labelHeightFa) +
              2 * line(caption, RivuletTypeStyles.captionHeightFa),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: gutter),
            itemCount: cast.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: RivuletSpacing.s8),
            itemBuilder: (context, index) {
              final member = cast[index];
              return FocusableAction(
                key: ValueKey<String>('people-item-$index'),
                onActivate: onTap == null || member.id == null
                    ? null
                    : () => onTap!(member),
                semanticLabel: member.name,
                focusRadius: BorderRadius.circular(RivuletRadius.medium),
                child: SizedBox(
                  key: ValueKey<String>('cast-member-${member.id ?? index}'),
                  width: _cardWidth,
                  child: Column(
                    children: <Widget>[
                      _CastThumb(
                        member: member,
                        width: _thumbWidth,
                        height: _thumbHeight,
                      ),
                      const SizedBox(height: RivuletSpacing.s8),
                      AppText.content(
                        member.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: label,
                      ),
                      if (member.role case final role?)
                        AppText.content(
                          role,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: caption,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CastThumb extends StatelessWidget {
  const _CastThumb({
    required this.member,
    required this.width,
    required this.height,
  });

  final CastMember member;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final photo = member.photo;
    return SizedBox(
      key: const ValueKey<String>('cast-thumb'),
      width: width,
      height: height,
      child: photo == null
          ? TintedSurface(
              radius: RivuletRadius.medium,
              child: Icon(
                PhosphorIconsRegular.user,
                size: width / 2,
                color: RivuletTokens.of(context).colors.textTertiary,
              ),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(RivuletRadius.medium),
              child: ArtworkView(
                requestId: photo.toString(),
                provider: ArtworkResolverScope.of(context)(photo.toString()),
                aspect: 2 / 3,
                fallbackKind: MediaKind.other,
                alignment: Alignment.topCenter,
              ),
            ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.facts, super.key});

  final List<AboutFact> facts;

  @override
  Widget build(BuildContext context) {
    final styles = RivuletTokens.of(context).typeStyles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SectionTitle(AppStrings.of(context).detail_about),
        Padding(
          padding: _gutterOf(context),
          child: TintedSurface(
            padding: const EdgeInsets.all(RivuletSpacing.s16),
            child: Wrap(
              spacing: RivuletSpacing.s32,
              runSpacing: RivuletSpacing.s12,
              children: <Widget>[
                for (final fact in facts)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      AppText(fact.label, style: styles.caption),
                      AppText.content(fact.value, style: styles.body),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The hero's old Watched, Watchlist and Info buttons, as rows.
class _LibrarySection extends StatelessWidget {
  const _LibrarySection({
    required this.isWatched,
    required this.isInWatchlist,
    required this.onToggleWatched,
    required this.onToggleWatchlist,
    required this.onInfo,
  });

  final bool isWatched;
  final bool isInWatchlist;
  final VoidCallback? onToggleWatched;
  final VoidCallback? onToggleWatchlist;
  final VoidCallback? onInfo;

  @override
  Widget build(BuildContext context) {
    final sizes = AdaptiveBehavior.sizesOf(context);
    return Padding(
      padding: _gutterOf(context),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: sizes.settingsContentMaxWidth),
          child: AppRowGroup(
            children: <Widget>[
              if (onToggleWatched != null)
                AppRow(
                  key: const ValueKey<String>('detail-watched-action'),
                  icon: PhosphorIconsRegular.check,
                  label: AppStrings.of(context).common_watched,
                  selected: isWatched,
                  onActivate: onToggleWatched,
                ),
              if (onToggleWatchlist != null)
                AppRow(
                  key: const ValueKey<String>('detail-watchlist-action'),
                  icon: PhosphorIconsRegular.plus,
                  label: AppStrings.of(context).detail_watchlist,
                  selected: isInWatchlist,
                  onActivate: onToggleWatchlist,
                ),
              if (onInfo != null)
                AppRow(
                  key: const ValueKey<String>('detail-info-action'),
                  icon: PhosphorIconsRegular.info,
                  label: AppStrings.of(context).detail_info,
                  caret: true,
                  onActivate: onInfo,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
