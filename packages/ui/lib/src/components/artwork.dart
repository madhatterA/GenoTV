import '../l10n_gen/app_strings.dart';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../theme/rivulet_tokens.dart';

import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'routed_network_image.dart';

/// Resolves an artwork URL string to the [ImageProvider] that loads it.
///
/// Production leaves this at the default ([RoutedNetworkImage]: direct
/// first, the backup proxy on failure). Goldens inject a
/// resolver (via [ArtworkResolverScope]) that maps fixture URLs to
/// [FileImage]/[MemoryImage] instead, so `flutter test` decodes real local
/// bytes deterministically rather than racing a network codec against
/// flutter_test's fake-async pump schedule.
typedef ArtworkResolver = ImageProvider Function(String url);

ImageProvider _defaultArtworkResolver(String url) => RoutedNetworkImage(url);

/// Supplies the [ArtworkResolver] every artwork call site reads through.
/// Absent an ancestor scope, [ArtworkResolverScope.of] falls back to
/// [_defaultArtworkResolver] ([RoutedNetworkImage]) — production behavior is
/// unchanged unless a test wraps the tree with this scope.
class ArtworkResolverScope extends InheritedWidget {
  const ArtworkResolverScope({
    required this.resolver,
    required super.child,
    super.key,
  });

  final ArtworkResolver resolver;

  static ArtworkResolver of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ArtworkResolverScope>()
          ?.resolver ??
      _defaultArtworkResolver;

  @override
  bool updateShouldNotify(ArtworkResolverScope oldWidget) =>
      resolver != oldWidget.resolver;
}

/// Loads and displays remote/injected artwork with race-safe replacement.
///
/// [requestId] identifies the artwork request (typically the resolved URL).
/// Every completion (success or error) from a stale [ImageStream] — one
/// started by an earlier [requestId]/[provider] than the one currently
/// active — is ignored, so out-of-order completions never clobber a newer
/// request's result. See `PosterCell.swift:349-382`'s `currentURL` guard
/// (`guard let self, self.currentURL == url else { return }`), the same
/// stale-completion pattern this widget ports.
///
/// A placeholder panel (`tintFill`) shows before the first decode; on a
/// genuine failure (or a null [provider]) the panel remains with the
/// media-kind fallback glyph centered over it. A picture that arrives late
/// fades in over 180 ms (TV 120 ms); one that is already in memory shows with
/// no fade (DESIGN_SPEC §5.2). Every picture is decoded at its display size
/// (DESIGN_SPEC P7).
class ArtworkView extends StatefulWidget {
  const ArtworkView({
    required this.requestId,
    required this.provider,
    required this.aspect,
    required this.fallbackKind,
    this.alignment = Alignment.center,
    super.key,
  });

  /// Identity of the current request. Changing this (with an unchanged
  /// [provider] instance, e.g. the same URL re-supplied) is still treated as
  /// a new request — callers that want to skip a reload keep the id stable.
  final Object requestId;

  /// The image source, or null when no artwork URL is available (an
  /// immediate, non-stale failure).
  final ImageProvider? provider;

  /// Width / height, e.g. 2/3 for a poster, 16/9 for a continue-watching card.
  final double aspect;

  final MediaKind fallbackKind;

  /// Which part of the picture stays visible when it is cropped to fit.
  final Alignment alignment;

  /// Decode width in pixels for a picture shown [logicalWidth] wide: rounded
  /// up to a multiple of 50 (DESIGN_SPEC P7).
  static int decodeWidth(double logicalWidth, double devicePixelRatio) =>
      (logicalWidth * devicePixelRatio / 50).ceil() * 50;

  /// [provider] decoding at the display size; the image-cache key a caller
  /// that pre-fetches the picture has to use too.
  static ImageProvider sized(
    ImageProvider provider,
    double logicalWidth,
    double devicePixelRatio,
  ) =>
      ResizeImage(provider, width: decodeWidth(logicalWidth, devicePixelRatio));

  @override
  State<ArtworkView> createState() => _ArtworkViewState();
}

enum _RevealMode { instant, fade }

class _ArtworkViewState extends State<ArtworkView> {
  /// Fixed by the first picture to arrive: a synchronous one never fades, and
  /// the widget type then stays the same for every later picture.
  _RevealMode? _mode;

  IconData get _fallbackIcon => switch (widget.fallbackKind) {
    MediaKind.movie => PhosphorIconsRegular.filmSlate,
    MediaKind.episode => PhosphorIconsRegular.television,
    MediaKind.other => PhosphorIconsRegular.image,
  };

  Widget _placeholder(RivuletColors colors, {required bool failed}) =>
      ColoredBox(
        color: colors.tintFill,
        child: failed
            ? Center(
                child: Icon(
                  _fallbackIcon,
                  size: 32,
                  color: colors.textTertiary,
                  semanticLabel: AppStrings.of(context).artwork_unavailable,
                ),
              )
            : const SizedBox.expand(),
      );

  Widget _reveal(Widget child, int? frame, bool synchronous, Duration fade) {
    if (frame == null && _mode == null) return const SizedBox.shrink();
    _mode ??= synchronous ? _RevealMode.instant : _RevealMode.fade;
    return _mode == _RevealMode.fade
        ? _FadeIn(duration: fade, child: child)
        : child;
  }

  @override
  Widget build(BuildContext context) {
    final colors = RivuletTokens.of(context).colors;
    final provider = widget.provider;
    final tv = AdaptiveBehavior.of(context).formFactor == FormFactor.tv;
    final fade = effectiveDuration(
      context,
      Duration(milliseconds: tv ? 120 : 180),
    );
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // One bone for the whole picture while a Skeletonizer is on.
    return Skeleton.leaf(
      child: AspectRatio(
        aspectRatio: widget.aspect,
        child: ClipRect(
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              fit: StackFit.expand,
              children: <Widget>[
                _placeholder(colors, failed: provider == null),
                if (provider != null)
                  Image(
                    image: ArtworkView.sized(
                      provider,
                      constraints.hasBoundedWidth
                          ? constraints.maxWidth
                          : MediaQuery.sizeOf(context).width,
                      dpr,
                    ),
                    fit: BoxFit.cover,
                    alignment: widget.alignment,
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                    frameBuilder: (context, child, frame, synchronous) =>
                        _reveal(child, frame, synchronous, fade),
                    errorBuilder: (context, error, stack) =>
                        _placeholder(colors, failed: true),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades its child in once, when first built.
class _FadeIn extends StatefulWidget {
  const _FadeIn({required this.duration, required this.child});

  final Duration duration;
  final Widget child;

  @override
  State<_FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<_FadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..forward();
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: RivuletMotion.easeOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _opacity, child: widget.child);
}
