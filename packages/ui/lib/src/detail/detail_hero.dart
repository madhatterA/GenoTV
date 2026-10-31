import '../l10n/genre_labels.dart';
import '../l10n_gen/app_strings.dart';
import '../platform/app_haptics.dart';
import '../l10n/formatters.dart';

import 'package:intl/intl.dart';

import 'dart:async';
import 'dart:ui' as ui;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../browse/hero_backdrop.dart';
import '../components/ambient_background.dart';
import '../components/app_button.dart';
import '../components/app_icon_button.dart';
import '../components/app_dialog.dart';
import '../components/app_text_button.dart';
import '../components/artwork.dart';
import '../components/tinted_surface.dart';
import '../l10n/app_text.dart';
import '../navigation/page_top_inset.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../theme/rivulet_tokens.dart';
import 'favourites_scope.dart';
import 'movie_detail_presentation.dart';
import 'rating_mark.dart';

/// The movie and series hero (DESIGN_SPEC §8.5): the Home hero's backdrop
/// ([HeroBackdropArt] under the one [AmbientFade]), with the poster left of
/// the text block on desktop and TV, then the title, facts, overview and the
/// action row. It is at least the Home hero's height and grows with its text.
class DetailHero extends StatelessWidget {
  const DetailHero({
    required this.presentation,
    this.playFocusNode,
    this.onPlay,
    this.onTrailer,
    this.onLinkTap,
    super.key,
  });

  final MovieDetailPresentation presentation;
  final FocusNode? playFocusNode;

  /// Missing callback == disabled Play.
  final VoidCallback? onPlay;

  /// Shows the Trailer button when set.
  final VoidCallback? onTrailer;
  final ValueChanged<DetailLink>? onLinkTap;

  @override
  Widget build(BuildContext context) {
    final sizes = AdaptiveBehavior.sizesOf(context);
    final phone = sizes.formFactor == FormFactor.phone;
    final gutter = RivuletSpacing.gutterOf(context);
    final item = presentation.item;
    final poster = phone ? null : presentation.poster;
    final text = _TextBlock(
      phonePoster: phone ? presentation.poster : null,
      presentation: presentation,
      playFocusNode: playFocusNode,
      onPlay: onPlay,
      onTrailer: onTrailer,
      onLinkTap: onLinkTap,
    );
    // Focusing any hero action scrolls the page back to the top, so the
    // action never rests under the floating back button and menu pill.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (focused) {
        final position = Scrollable.maybeOf(context)?.position;
        if (focused && position != null && position.pixels > 0) {
          scrollPositionTo(
            position,
            0,
            duration: effectiveDuration(context, RivuletMotion.base),
            curve: RivuletMotion.easeOut,
          );
        }
      },
      child: ConstrainedBox(
        key: const ValueKey<String>('detail-hero'),
        constraints: BoxConstraints(minHeight: sizes.heroHeight),
        child: Stack(
          alignment: Alignment.bottomLeft,
          children: <Widget>[
            // No backdrop: the page's ambient background shows, not the
            // placeholder icon (it would sit behind the title).
            if (item.artwork != null)
              Positioned.fill(
                child: RepaintBoundary(
                  child: AmbientFade(
                    child: HeroBackdropArt(
                      artwork: item.artwork,
                      kind: item.kind,
                      height: sizes.heroHeight,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                gutter,
                pageTopInsetOf(context),
                gutter,
                0,
              ),
              child: phone
                  ? SizedBox(width: double.infinity, child: text)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        if (poster != null) ...<Widget>[
                          _Poster(
                            poster: poster,
                            kind: item.kind,
                            width: sizes.posterWidth * 1.4,
                          ),
                          const SizedBox(width: RivuletSpacing.s24),
                        ],
                        Flexible(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: sizes.heroTextMaxWidth,
                            ),
                            child: text,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({
    required this.poster,
    required this.kind,
    required this.width,
  });

  final Uri poster;
  final MediaKind kind;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey<String>('detail-poster'),
    width: width,
    height: width * 1.5,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(RivuletRadius.medium),
      child: ArtworkView(
        requestId: poster.toString(),
        provider: ArtworkResolverScope.of(context)(poster.toString()),
        aspect: 2 / 3,
        fallbackKind: kind,
      ),
    ),
  );
}

class _TextBlock extends StatelessWidget {
  const _TextBlock({
    required this.phonePoster,
    required this.presentation,
    required this.playFocusNode,
    required this.onPlay,
    required this.onTrailer,
    required this.onLinkTap,
  });

  /// Phone only: a small poster left of the title.
  final Uri? phonePoster;
  final MovieDetailPresentation presentation;
  final FocusNode? playFocusNode;
  final VoidCallback? onPlay;
  final VoidCallback? onTrailer;
  final ValueChanged<DetailLink>? onLinkTap;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final styles = tokens.typeStyles;
    final phone = AdaptiveBehavior.formFactorOf(context) == FormFactor.phone;
    final item = presentation.item;
    final kind = switch (item.kind) {
      MediaKind.movie => AppStrings.of(context).detail_kindMovie,
      MediaKind.episode => AppStrings.of(context).detail_kindTvShow,
      MediaKind.other => '',
    };
    final genreLine = <String>[
      kind,
      ...presentation.genres.take(2).map((g) => genreLabel(context, g)),
    ].where((part) => part.isNotEmpty).join(' · ');
    final overview = presentation.summary;
    final isTagline = overview == null || overview.isEmpty;
    final description = isTagline ? presentation.tagline : overview;
    DetailLink? linkWhere(bool Function(DetailLink) test) =>
        presentation.links.where(test).firstOrNull;
    Widget link(DetailLink link, String text) => AppTextButton(
      key: ValueKey<String>('detail-link-${link.filter}-${link.value}'),
      label: text,
      onActivate: onLinkTap == null ? null : () => onLinkTap!(link),
    );
    // Runtime and ratings in solid white, not the muted caption grey
    // (owner 2026-10-10).
    final strong = styles.caption.copyWith(color: tokens.colors.textPrimary);
    final facts = <Widget>[
      if (presentation.year case final rawYear?)
        if (linkWhere((l) => l.isYear) case final yearLink?)
          link(yearLink, _year(context, rawYear))
        else
          AppText(_year(context, rawYear), style: styles.caption),
      for (final country in presentation.links.where((l) => l.isCountry))
        link(country, country.label),
      if (presentation.runtimeLabel ??
              (presentation.runtime == null
                  ? null
                  : formatDuration(
                      context,
                      presentation.runtime!,
                      includeZeroMinutes: true,
                    ))
          case final runtime?)
        AppText(runtime, style: strong),
      if (presentation.imdbRating case final imdb? when imdb.isNotEmpty)
        RatingMark(imdb: imdb, scale: 1, textStyle: strong),
      if (presentation.rottenTomatoes case final rt? when rt.isNotEmpty)
        RatingMark(rottenTomatoes: rt, scale: 1, textStyle: strong),
      if (presentation.tmdbRating case final tmdb? when tmdb.isNotEmpty)
        RatingMark(tmdb: tmdb, scale: 1, textStyle: strong),
    ];
    final title = AppText.content(
      item.title,
      key: const ValueKey<String>('detail-hero-title'),
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
      style: phone ? styles.title : styles.display,
    );
    final progress = presentation.progress;
    final resume = _resumeLabel(context, progress);
    final liked = FavouritesScope.maybeOf(context) != null;
    final head = <Widget>[
      title,
      if (genreLine.isNotEmpty ||
          (presentation.contentRating ?? '').isNotEmpty) ...<Widget>[
        const SizedBox(height: RivuletSpacing.s8),
        Wrap(
          key: const ValueKey<String>('detail-hero-facts'),
          spacing: RivuletSpacing.s8,
          runSpacing: RivuletSpacing.s4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            if (genreLine.isNotEmpty) AppText(genreLine, style: styles.caption),
            if (presentation.contentRating case final rating?
                when rating.isNotEmpty)
              _Badge(rating),
          ],
        ),
      ],
      if (facts.isNotEmpty) ...<Widget>[
        const SizedBox(height: RivuletSpacing.s4),
        Wrap(
          key: const ValueKey<String>('detail-hero-badges'),
          spacing: RivuletSpacing.s16,
          runSpacing: RivuletSpacing.s4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            // A leading link button carries 8 px of padding; pull it back
            // so its text lines up with the title.
            for (var i = 0; i < facts.length; i++)
              if (i == 0 && facts[i] is AppTextButton)
                Transform.translate(
                  offset: Offset(
                    Directionality.of(context) == ui.TextDirection.rtl
                        ? RivuletSpacing.s8
                        : -RivuletSpacing.s8,
                    0,
                  ),
                  child: facts[i],
                )
              else
                facts[i],
          ],
        ),
      ],
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (phonePoster case final poster?)
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              _Poster(
                poster: poster,
                kind: item.kind,
                width: RivuletSizes.phoneDetailPoster,
              ),
              const SizedBox(width: RivuletSpacing.s16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: head,
                ),
              ),
            ],
          )
        else
          ...head,
        if (description != null && description.isNotEmpty) ...<Widget>[
          const SizedBox(height: RivuletSpacing.s12),
          _Summary(
            text: description,
            style: styles.body.copyWith(
              color: tokens.colors.textSecondary,
              fontStyle: isTagline ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ],
        const SizedBox(height: RivuletSpacing.s24),
        _actions(context, resume: resume, liked: liked),
      ],
    );
  }

  /// Play/Resume (tier L; phone: fills the row left of the others), Trailer, Like.
  Widget _actions(
    BuildContext context, {
    required String? resume,
    required bool liked,
  }) {
    final ff = AdaptiveBehavior.formFactorOf(context);
    final phone = ff == FormFactor.phone;
    const gap = RivuletSpacing.s12;
    final play = AppButton.primary(
      key: const ValueKey<String>('detail-play-action'),
      label: resume ?? AppStrings.of(context).common_play,
      icon: PhosphorIconsFill.play,
      size: RivuletControlSize.l,
      minWidth: phone ? null : 4 * RivuletControlSize.l.height(ff),
      expand: phone,
      focusNode: playFocusNode,
      autofocus: ff == FormFactor.tv,
      onActivate: onPlay,
    );
    final others = <Widget>[
      if (onTrailer != null)
        AppButton.secondary(
          key: const ValueKey<String>('detail-trailer'),
          label: AppStrings.of(context).detail_trailer,
          icon: PhosphorIconsRegular.play,
          size: RivuletControlSize.l,
          overMedia: true,
          onActivate: onTrailer,
        ),
      if (liked) _LikeToggle(mediaId: presentation.item.id),
    ];
    if (phone) {
      return Row(
        key: const ValueKey<String>('detail-actions'),
        children: <Widget>[
          Expanded(child: play),
          for (final w in others) ...<Widget>[const SizedBox(width: gap), w],
        ],
      );
    }
    return Wrap(
      key: const ValueKey<String>('detail-actions'),
      spacing: gap,
      runSpacing: gap,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[play, ...others],
    );
  }

  /// "Resume 12:34" while the title is partly watched, else null.
  static String? _resumeLabel(
    BuildContext context,
    PlaybackProgress? progress,
  ) {
    if (progress == null || progress.duration <= Duration.zero) return null;
    final fraction =
        progress.position.inMilliseconds / progress.duration.inMilliseconds;
    if (fraction <= 0 || fraction >= 0.98) return null;
    return AppStrings.of(context)
        .detail_resumeAt(_clock(context, progress.position));
  }

  static String _year(BuildContext context, String year) {
    final n = int.tryParse(year);
    return n == null ? year : formatYear(context, n);
  }

  static String _clock(BuildContext context, Duration d) {
    final locale = Localizations.localeOf(context).languageCode;
    String two(int n) => NumberFormat('00', locale).format(n);
    final seconds = two(d.inSeconds % 60);
    return d.inHours > 0
        ? '${NumberFormat('0', locale).format(d.inHours)}:'
              '${two(d.inMinutes % 60)}:$seconds'
        : '${NumberFormat('0', locale).format(d.inMinutes)}:$seconds';
  }
}

/// The content-rating and quality marks: a small non-interactive chip over
/// the backdrop (DESIGN_SPEC §3.2, §8.5).
class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => TintedSurface.overMedia(
    radius: RivuletRadius.xs,
    padding: const EdgeInsets.symmetric(
      horizontal: RivuletSpacing.s8,
      vertical: RivuletSpacing.s4,
    ),
    child: AppText(
      text,
      style: RivuletTokens.of(context).typeStyles.caption
          .copyWith(fontWeight: FontWeight.w600),
    ),
  );
}

/// Heart button: adds/removes the title from the app's favourites (the same
/// store the Liked row and menu page read). The icon swaps `heart` ↔
/// `heartFill` and scales 1 → 1.2 → 1 in 2 × `press` (DESIGN_SPEC §5.2).
class _LikeToggle extends StatefulWidget {
  const _LikeToggle({required this.mediaId});

  final String mediaId;

  @override
  State<_LikeToggle> createState() => _LikeToggleState();
}

class _LikeToggleState extends State<_LikeToggle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this);
  late final Animation<double> _scale = TweenSequence<double>(
    <TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: 1,
          end: 1.2,
        ).chain(CurveTween(curve: RivuletMotion.easeOut)),
        weight: 1,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: 1.2,
          end: 1,
        ).chain(CurveTween(curve: RivuletMotion.easeOut)),
        weight: 1,
      ),
    ],
  ).animate(_pulse);
  bool _liked = false;
  FavouritesRepository? _repository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repository = FavouritesScope.maybeOf(context);
    if (repository == _repository) return;
    _repository = repository;
    repository?.isFavourite(widget.mediaId).then((liked) {
      if (mounted) setState(() => _liked = liked);
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final next = !_liked;
    AppHaptics.selection(context);
    setState(() => _liked = next);
    _pulse.duration = effectiveDuration(context, RivuletMotion.press * 2);
    unawaited(_pulse.forward(from: 0));
    final ok = await setLikedWithFeedback(
      context,
      _repository!,
      widget.mediaId,
      next,
      onChanged: (liked) {
        if (mounted) setState(() => _liked = liked);
      },
    );
    if (!ok && mounted) setState(() => _liked = !next);
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: _scale,
    child: AppIconButton(
      key: const ValueKey<String>('detail-like'),
      overMedia: true,
      size: RivuletControlSize.l,
      icon: _liked ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
      semanticLabel: _liked
          ? AppStrings.of(context).detail_unlike
          : AppStrings.of(context).detail_like,
      onActivate: _toggle,
    ),
  );
}

/// The hero summary, cut at 4 lines. A focusable "More" opens the full text
/// (scrollable) when it was cut, in every language and form factor.
class _Summary extends StatelessWidget {
  const _Summary({required this.text, required this.style});

  final String text;
  final TextStyle style;

  static const int _maxLines = 4;

  @override
  Widget build(BuildContext context) {
    final summary = AppText.content(
      text,
      paragraph: true,
      key: const ValueKey<String>('detail-hero-summary'),
      maxLines: _maxLines,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: AppText.effectiveStyle(context, style),
          ),
          textDirection: Bidi.detectRtlDirectionality(text)
              ? ui.TextDirection.rtl
              : ui.TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: _maxLines,
        )..layout(maxWidth: constraints.maxWidth);
        final cut = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            summary,
            if (cut)
              AppTextButton(
                key: const ValueKey<String>('detail-summary-more'),
                label: AppStrings.of(context).detail_more,
                onActivate: () => showAppDialog<void>(
                  context: context,
                  builder: (_) => SingleChildScrollView(
                    child: AppText.content(text, paragraph: true, style: style),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
