import '../l10n_gen/app_strings.dart';
import '../l10n/formatters.dart';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../components/ambient_background.dart';
import '../components/app_button.dart';
import '../components/artwork.dart';
import '../l10n/app_text.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../theme/rivulet_tokens.dart';

/// The Home hero (DESIGN_SPEC §8.1): a full-width backdrop with `scrimSide`
/// and `scrimBottom`, the title and meta line at the bottom-left, then the
/// Play and Details buttons and the page dots. The picture, title and meta
/// cross-fade on a slide change; the buttons stay put.
class HeroBackdrop extends StatelessWidget {
  const HeroBackdrop({
    required this.item,
    this.artworkOverride,
    this.pageIndex = 0,
    this.pageCount = 1,
    this.playFocusNode,
    this.detailsFocusNode,
    this.detailsEnabled = true,
    this.onPlay,
    this.onDetails,
    this.onPage,
    this.onNext,
    super.key,
  });

  final MediaItem? item;

  /// A wide backdrop picture to show instead of [item]'s own artwork (which
  /// is a small portrait poster).
  final Uri? artworkOverride;
  final int pageIndex;
  final int pageCount;

  final FocusNode? playFocusNode;
  final FocusNode? detailsFocusNode;

  /// Details is only a focus candidate once focus has entered the hero; Play
  /// never is gated.
  final bool detailsEnabled;

  final VoidCallback? onPlay;
  final VoidCallback? onDetails;

  /// A page dot was clicked or tapped.
  final ValueChanged<int>? onPage;

  /// Remote only: Right on the last hero button shows the next slide and
  /// puts focus on the new Play (DESIGN_SPEC §8.1).
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final sizes = AdaptiveBehavior.sizesOf(context);
    final formFactor = sizes.formFactor;
    final tv = formFactor == FormFactor.tv;
    final phone = formFactor == FormFactor.phone;
    final gutter = RivuletSpacing.gutter(formFactor);
    final artwork = artworkOverride ?? item?.artwork;
    final slide = item;
    final fade = effectiveDuration(
      context,
      tv ? RivuletMotion.fast : RivuletMotion.base,
    );
    final dots = pageCount > 1
        ? _PageDots(count: pageCount, index: pageIndex, onPage: onPage)
        : null;
    return SizedBox(
      key: const ValueKey<String>('hero-backdrop-band'),
      height: sizes.heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          RepaintBoundary(
            child: AmbientFade(
              child: AnimatedSwitcher(
                key: const ValueKey<String>('hero-image-switcher'),
                duration: fade,
                switchInCurve: RivuletMotion.easeOut,
                switchOutCurve: RivuletMotion.easeOut,
                layoutBuilder: _stack,
                child: HeroBackdropArt(
                  key: ValueKey<String>('hero-slide-${slide?.id}'),
                  artwork: artwork,
                  kind: slide?.kind ?? MediaKind.other,
                  height: sizes.heroHeight,
                ),
              ),
            ),
          ),
          Positioned(
            left: gutter,
            bottom: RivuletSpacing.s24,
            width: phone ? null : sizes.heroTextMaxWidth,
            right: phone ? gutter : null,
            child: Column(
              crossAxisAlignment: phone
                  ? CrossAxisAlignment.stretch
                  : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AnimatedSwitcher(
                  key: const ValueKey<String>('hero-metadata-switcher'),
                  duration: fade,
                  switchInCurve: RivuletMotion.easeOut,
                  switchOutCurve: RivuletMotion.easeOut,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.bottomLeft,
                    children: <Widget>[...previous, ?current],
                  ),
                  child: slide == null
                      ? const SizedBox.shrink(
                          key: ValueKey<String>('hero-empty'),
                        )
                      : _HeroText(
                          key: ValueKey<String>('hero-text-${slide.id}'),
                          item: slide,
                        ),
                ),
                const SizedBox(height: RivuletSpacing.s16),
                _HeroActions(
                  playFocusNode: playFocusNode,
                  detailsFocusNode: detailsFocusNode,
                  detailsEnabled: detailsEnabled,
                  onPlay: onPlay,
                  onDetails: onDetails,
                  onNext: onNext,
                ),
                if (phone && dots != null) ...<Widget>[
                  const SizedBox(height: RivuletSpacing.s8),
                  Center(child: dots),
                ],
              ],
            ),
          ),
          if (!phone && dots != null)
            Positioned(right: gutter, bottom: RivuletSpacing.s24, child: dots),
        ],
      ),
    );
  }

  static Widget _stack(Widget? current, List<Widget> previous) =>
      Stack(fit: StackFit.expand, children: <Widget>[...previous, ?current]);
}

/// The picture of a hero with `scrimSide` and `scrimBottom` over it
/// (DESIGN_SPEC §8.1, §8.5): shared by the Home hero, the detail hero and the
/// play-source backdrop. The caller wraps it in the one `AmbientFade`.
class HeroBackdropArt extends StatelessWidget {
  const HeroBackdropArt({
    required this.artwork,
    required this.kind,
    required this.height,
    super.key,
  });

  final Uri? artwork;
  final MediaKind kind;

  /// Height the picture is decoded for.
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = RivuletTokens.of(context).colors;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ArtworkView(
          requestId: artwork?.toString() ?? 'no-artwork',
          provider: artwork == null
              ? null
              : ArtworkResolverScope.of(context)(artwork.toString()),
          aspect: MediaQuery.sizeOf(context).width / height,
          fallbackKind: kind,
          alignment: Alignment.topCenter,
        ),
        Skeleton.ignore(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.55,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: colors.scrimSide),
              ),
            ),
          ),
        ),
        Skeleton.ignore(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: 0.45,
              widthFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: colors.scrimBottom),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Title and the runtime meta line of one slide (no year, owner 2026-10-10).
class _HeroText extends StatelessWidget {
  const _HeroText({required this.item, super.key});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final styles = RivuletTokens.of(context).typeStyles;
    final phone = AdaptiveBehavior.of(context).formFactor == FormFactor.phone;
    final duration = item.duration;
    final meta = duration == null || duration.inMinutes < 1
        ? ''
        : formatDuration(context, duration);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AppText.content(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: phone ? styles.title : styles.display,
        ),
        if (meta.isNotEmpty) ...<Widget>[
          const SizedBox(height: RivuletSpacing.s8),
          AppText(
            meta,
            maxLines: 1,
            style: styles.caption.copyWith(
              color: RivuletTokens.of(context).colors.textPrimary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Play and Details side by side (gap 12). On a remote, Right on Details
/// pages the hero.
class _HeroActions extends StatefulWidget {
  const _HeroActions({
    required this.detailsEnabled,
    this.playFocusNode,
    this.detailsFocusNode,
    this.onPlay,
    this.onDetails,
    this.onNext,
  });

  final FocusNode? playFocusNode;
  final FocusNode? detailsFocusNode;
  final bool detailsEnabled;
  final VoidCallback? onPlay;
  final VoidCallback? onDetails;
  final VoidCallback? onNext;

  @override
  State<_HeroActions> createState() => _HeroActionsState();
}

class _HeroActionsState extends State<_HeroActions> {
  late final bool _ownsPlay = widget.playFocusNode == null;
  late final bool _ownsDetails = widget.detailsFocusNode == null;
  late final FocusNode _play =
      widget.playFocusNode ?? FocusNode(debugLabel: 'hero-play');
  late final FocusNode _details =
      widget.detailsFocusNode ?? FocusNode(debugLabel: 'hero-details');

  @override
  void dispose() {
    if (_ownsPlay) _play.dispose();
    if (_ownsDetails) _details.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (widget.onNext == null ||
        !(AdaptiveBehavior.of(context).formFactor == FormFactor.tv) ||
        !_details.hasFocus ||
        event.logicalKey != LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      widget.onNext!();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // The Right just taken is not a way back: Left from the new Play must
        // reach the menu, not retrace to Details.
        FocusTraversalGroup.of(context)
            .invalidateScopeData(FocusScope.of(context));
        _play.requestFocus();
      });
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: _onKey,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AppButton.primary(
          key: const ValueKey<String>('hero-focus-play'),
          label: AppStrings.of(context).common_play,
          icon: PhosphorIconsFill.play,
          focusNode: _play,
          autofocus: (AdaptiveBehavior.of(context).formFactor == FormFactor.tv),
          onActivate: widget.onPlay,
        ),
        const SizedBox(width: RivuletSpacing.s12),
        ExcludeFocus(
          excluding: !widget.detailsEnabled,
          child: AppButton.secondary(
            key: const ValueKey<String>('hero-focus-details'),
            label: AppStrings.of(context).common_details,
            overMedia: true,
            focusNode: _details,
            onActivate: widget.onDetails,
          ),
        ),
      ],
    ),
  );
}

/// One dot per slide; the current one is `textPrimary`, the others
/// `textTertiary`. A tap or click on the row shows the slide under the
/// pointer; assistive technology pages with increase and decrease. Not
/// focusable: the keyboard and remote page the hero from its buttons.
class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index, this.onPage});

  static const double _dot = 8;
  static const double _cell = _dot + 2 * RivuletSpacing.s8;

  final int count;
  final int index;
  final ValueChanged<int>? onPage;

  @override
  Widget build(BuildContext context) {
    final colors = RivuletTokens.of(context).colors;
    final page = onPage;
    return Semantics(
      label: AppStrings.of(context).home_featuredItem(
        formatCount(context, index + 1),
        formatCount(context, count),
      ),
      onIncrease: page == null || index >= count - 1
          ? null
          : () => page(index + 1),
      onDecrease: page == null || index <= 0 ? null : () => page(index - 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: page == null
              ? null
              : (details) => page(
                  (details.localPosition.dx ~/ _cell).clamp(0, count - 1),
                ),
          child: SizedBox(
            height: RivuletSizes.touchHitTarget,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (var i = 0; i < count; i++)
                  SizedBox(
                    key: ValueKey<String>('hero-dot-$i'),
                    width: _cell,
                    child: Center(
                      child: SizedBox.square(
                        dimension: _dot,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == index
                                ? colors.textPrimary
                                : colors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
