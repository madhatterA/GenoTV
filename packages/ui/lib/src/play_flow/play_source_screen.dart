import '../l10n_gen/app_strings.dart';
import '../l10n/formatters.dart';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter/gestures.dart' show kBackMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_thinking_orbs/flutter_thinking_orbs.dart' show OrbState;
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../browse/choice_dialog.dart';
import '../browse/hero_backdrop.dart';
import '../components/ambient_background.dart';
import '../components/app_chip.dart';
import '../components/app_dialog.dart';
import '../components/app_icon_button.dart';
import '../components/app_row.dart';
import '../components/app_sheet.dart';
import '../components/orb_loader.dart';
import '../components/tinted_surface.dart';
import '../l10n/app_text.dart';
import '../navigation/page_back_button.dart';
import '../navigation/page_top_inset.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../states/error_view.dart';
import '../theme/rivulet_tokens.dart';
import 'play_flow_models.dart';
import 'stream_display.dart';

/// Provider list, then that provider's stream list — the screen between
/// picking "play" on a title and handing a [SourceSpec] to the player
/// (DESIGN_SPEC §8.6). Renders only what the caller hands it: no resolving,
/// no provider knowledge, no persistence of the last choice.
class PlaySourceScreen extends StatefulWidget {
  const PlaySourceScreen({
    required this.title,
    this.subtitle,
    required this.providers,
    this.selectedProviderId,
    required this.streams,
    required this.onProviderSelected,
    required this.onStreamSelected,
    required this.onBack,
    this.onInsertLink,
    this.onRetry,
    this.onRefresh,
    this.backdropArtwork,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<UiProviderOption> providers;
  final String? selectedProviderId;
  final UiStreamList streams;
  final ValueChanged<String> onProviderSelected;
  final ValueChanged<SourceSpec> onStreamSelected;
  final VoidCallback onBack;

  /// Adds a final "Insert link…" row to the source list when set (shown even
  /// when the title has no providers).
  final VoidCallback? onInsertLink;

  /// The failed state's Retry button; without it the failed state offers Back.
  final VoidCallback? onRetry;

  /// Loads the selected provider's streams afresh (skips the saved list).
  final VoidCallback? onRefresh;

  /// The title's artwork URL, painted behind the top of the page with the
  /// detail hero's backdrop and fade. Null paints no backdrop.
  final String? backdropArtwork;

  @override
  State<PlaySourceScreen> createState() => _PlaySourceScreenState();
}

class _PlaySourceScreenState extends State<PlaySourceScreen> {
  final FocusNode _firstProviderNode = FocusNode(
    debugLabel: 'play-source-first-provider',
  );
  final FocusNode _firstStreamNode = FocusNode(
    debugLabel: 'play-source-first-stream',
  );

  @override
  void dispose() {
    _firstProviderNode.dispose();
    _firstStreamNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(PlaySourceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final becameReady =
        widget.streams is UiStreamListReady &&
        (oldWidget.selectedProviderId != widget.selectedProviderId ||
            oldWidget.streams is! UiStreamListReady);
    if (becameReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _firstStreamNode.requestFocus();
      });
    }
  }

  String get _providerName =>
      widget.providers
          .where((p) => p.id == widget.selectedProviderId)
          .firstOrNull
          ?.name ??
      '';

  @override
  Widget build(BuildContext context) {
    final inSheet = AppSheet.contains(context);
    final sizes = AdaptiveBehavior.sizesOf(context);
    final backdrop = widget.backdropArtwork;
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): _BackIntent(),
        // Backspace pops here too, matching the detail pages' `PopOnEscape`.
        SingleActivator(LogicalKeyboardKey.backspace): _BackIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _BackIntent: CallbackAction<_BackIntent>(
            onInvoke: (_) {
              widget.onBack();
              return null;
            },
          ),
        },
        child: Focus(
          canRequestFocus: false,
          child: Listener(
            // A mouse's dedicated back button surfaces as a pointer button
            // (`kBackMouseButton`), not a `LogicalKeyboardKey` — needs its
            // own listener rather than the `Shortcuts` map above.
            onPointerDown: (event) {
              if (event.buttons & kBackMouseButton != 0) widget.onBack();
            },
            child: Builder(
              builder: (context) {
                final content = Material(
                  color: Colors.transparent,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      if (!inSheet && backdrop != null)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: sizes.heroHeight,
                          child: RepaintBoundary(
                            child: AmbientFade(
                              child: HeroBackdropArt(
                                artwork: Uri.parse(backdrop),
                                kind: MediaKind.movie,
                                height: sizes.heroHeight,
                              ),
                            ),
                          ),
                        ),
                      SafeArea(
                        top: false,
                        child: _body(
                          context,
                          inSheet,
                          sizes,
                          overMedia: !inSheet && backdrop != null,
                        ),
                      ),
                      if (!inSheet)
                        Positioned(
                          top: 0,
                          left: 0,
                          child: PageBackButton(onPressed: widget.onBack),
                        ),
                    ],
                  ),
                );
                return inSheet ? content : AmbientBackground(child: content);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    bool inSheet,
    RivuletSizes sizes, {
    required bool overMedia,
  }) {
    final gutter = RivuletSpacing.gutter(sizes.formFactor);
    final providers = _ProviderList(
      overMedia: overMedia,
      providers: widget.providers,
      selectedId: widget.selectedProviderId,
      onSelected: widget.onProviderSelected,
      firstFocusNode: _firstProviderNode,
      onInsertLink: widget.onInsertLink,
      onArrowRight: () {
        if (widget.streams is UiStreamListReady) {
          _firstStreamNode.requestFocus();
        }
      },
    );
    Widget streams(VoidCallback onArrowLeft) => _StreamPanel(
      overMedia: overMedia,
      streams: widget.streams,
      providerName: _providerName,
      onSelected: widget.onStreamSelected,
      onRetry: widget.onRetry,
      onRefresh: widget.onRefresh,
      onBack: widget.onBack,
      firstFocusNode: _firstStreamNode,
      onArrowLeft: onArrowLeft,
    );
    final Widget panes;
    if (sizes.formFactor == FormFactor.phone) {
      panes = widget.selectedProviderId != null
          ? streams(widget.onBack)
          : providers;
    } else {
      panes = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: providers),
          const SizedBox(width: RivuletSpacing.s24),
          Expanded(child: streams(_firstProviderNode.requestFocus)),
        ],
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(
        gutter,
        0,
        gutter,
        inSheet ? 0 : RivuletSpacing.s24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Header(
            title: widget.title,
            subtitle: widget.subtitle,
            inSheet: inSheet,
          ),
          Expanded(child: panes),
        ],
      ),
    );
  }
}

class _BackIntent extends Intent {
  const _BackIntent();
}

/// The title and subtitle. On a pushed page it sits beside the back button in
/// the menu row; in the phone sheet there is no back arrow and no page inset,
/// so it starts 16 px under the sheet handle.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.inSheet,
  });

  final String title;
  final String? subtitle;
  final bool inSheet;

  @override
  Widget build(BuildContext context) {
    final styles = RivuletTokens.of(context).typeStyles;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AppText.content(
          title,
          key: const ValueKey<String>('play-source-title'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: styles.headline,
        ),
        if (subtitle != null)
          AppText.content(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: styles.caption,
          ),
      ],
    );
    if (inSheet) {
      return Padding(
        padding: const EdgeInsets.only(
          top: RivuletSpacing.s16,
          bottom: RivuletSpacing.s16,
        ),
        child: SizedBox(width: double.infinity, child: text),
      );
    }
    final pill = menuSlotOf(context);
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: pageTopInsetOf(context)),
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: EdgeInsets.only(
            top: pill.top,
            left:
                pill.right +
                RivuletSpacing.s16 -
                RivuletSpacing.gutter(AdaptiveBehavior.of(context).formFactor),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: pill.height),
            child: Align(alignment: Alignment.centerLeft, child: text),
          ),
        ),
      ),
    );
  }
}

/// Wraps a row so Right/Left move focus to the other pane.
Widget _paneKey(LogicalKeyboardKey key, VoidCallback onKey, Widget child) =>
    Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent && event.logicalKey == key) {
          onKey();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );

class _ProviderList extends StatelessWidget {
  const _ProviderList({
    required this.overMedia,
    required this.providers,
    required this.selectedId,
    required this.onSelected,
    required this.firstFocusNode,
    required this.onArrowRight,
    this.onInsertLink,
  });

  final bool overMedia;
  final List<UiProviderOption> providers;
  final String? selectedId;
  final ValueChanged<String> onSelected;
  final FocusNode firstFocusNode;
  final VoidCallback onArrowRight;

  /// Adds the final "Insert link…" row when set.
  final VoidCallback? onInsertLink;

  @override
  Widget build(BuildContext context) {
    final colors = RivuletTokens.of(context).colors;
    final rows = <Widget>[
      for (var i = 0; i < providers.length; i++)
        _paneKey(
          LogicalKeyboardKey.arrowRight,
          onArrowRight,
          AppRow(
            key: ValueKey<String>('provider-row-${providers[i].id}'),
            label: providers[i].name,
            description: providers[i].message,
            leading: providers[i].state == UiProviderState.failed
                ? Icon(
                    PhosphorIconsRegular.warningCircle,
                    size: AdaptiveBehavior.sizesOf(context).iconGlyph,
                    color: colors.danger,
                  )
                : null,
            trailing: providers[i].state != UiProviderState.loading
                ? null
                : providers[i].progress != null
                ? AppText(
                    formatPercent(context, providers[i].progress!),
                    key: const ValueKey<String>('provider-progress'),
                    style: RivuletTokens.of(context).typeStyles.caption,
                  )
                : const OrbLoader.small(
                    key: ValueKey<String>('provider-loading'),
                    state: OrbState.searching,
                  ),
            selected: providers[i].id == selectedId,
            autofocus: i == 0,
            focusNode: i == 0 ? firstFocusNode : null,
            onActivate: () => onSelected(providers[i].id),
          ),
        ),
      if (onInsertLink != null)
        _paneKey(
          LogicalKeyboardKey.arrowRight,
          onArrowRight,
          AppRow(
            key: const ValueKey<String>('provider-row-insert-link'),
            icon: PhosphorIconsRegular.link,
            label: AppStrings.of(context).play_insertLink,
            autofocus: providers.isEmpty,
            focusNode: providers.isEmpty ? firstFocusNode : null,
            onActivate: onInsertLink,
          ),
        ),
    ];
    return ListView(
      key: const ValueKey<String>('play-source-providers'),
      children: <Widget>[AppRowGroup(overMedia: overMedia, children: rows)],
    );
  }
}

class _StreamPanel extends StatefulWidget {
  const _StreamPanel({
    required this.overMedia,
    required this.streams,
    required this.providerName,
    required this.onSelected,
    required this.onRetry,
    required this.onRefresh,
    required this.onBack,
    required this.firstFocusNode,
    required this.onArrowLeft,
  });

  final bool overMedia;
  final UiStreamList streams;
  final String providerName;
  final ValueChanged<SourceSpec> onSelected;
  final VoidCallback? onRetry;
  final VoidCallback? onRefresh;
  final VoidCallback onBack;
  final FocusNode firstFocusNode;
  final VoidCallback onArrowLeft;

  @override
  State<_StreamPanel> createState() => _StreamPanelState();
}

enum _StreamSort { none, size, seeds }

class _StreamPanelState extends State<_StreamPanel> {
  _StreamSort _sort = _StreamSort.none;

  @override
  void didUpdateWidget(_StreamPanel old) {
    super.didUpdateWidget(old);
    if (old.providerName != widget.providerName) _sort = _StreamSort.none;
  }

  int? _seeders(SourceSpec spec) =>
      parseStreamDisplay(spec, providerName: widget.providerName).seeders;

  /// Default keeps the provider's order; Size and Seeds list the biggest
  /// first, streams without the value last.
  List<SourceSpec> _sorted(List<SourceSpec> streams) {
    if (_sort == _StreamSort.none) return streams;
    int? key(SourceSpec spec) =>
        _sort == _StreamSort.size ? spec.expectedBytes : _seeders(spec);
    final indexed = streams.indexed.toList()
      ..sort((a, b) {
        final x = key(a.$2), y = key(b.$2);
        if (x == null && y == null) return a.$1.compareTo(b.$1);
        if (x == null) return 1;
        if (y == null) return -1;
        final byValue = y.compareTo(x);
        return byValue != 0 ? byValue : a.$1.compareTo(b.$1);
      });
    return [for (final entry in indexed) entry.$2];
  }

  Future<void> _pickSort(bool hasSeeders) async {
    final picked = await showChoiceDialog<_StreamSort>(
      context,
      title: AppStrings.of(context).play_sortStreams,
      current: _sort,
      options: <Choice<_StreamSort>>[
        (value: _StreamSort.none, label: AppStrings.of(context).common_default),
        (value: _StreamSort.size, label: AppStrings.of(context).play_sortSize),
        if (hasSeeders)
          (
            value: _StreamSort.seeds,
            label: AppStrings.of(context).play_sortSeeds,
          ),
      ],
    );
    if (picked != null && mounted) setState(() => _sort = picked);
  }

  Widget _sortControl(bool hasSeeders) {
    final label = switch (_sort) {
      _StreamSort.none => AppStrings.of(context).common_default,
      _StreamSort.size => AppStrings.of(context).play_sortSize,
      _StreamSort.seeds => AppStrings.of(context).play_sortSeeds,
    };
    return AppChip(
      key: const ValueKey<String>('stream-sort'),
      icon: PhosphorIconsRegular.sortAscending,
      label: AppStrings.of(context).filter_sortBy(label),
      onActivate: () => _pickSort(hasSeeders),
    );
  }

  Widget _ready(List<SourceSpec> all) {
    final collapsed = collapseHls(all);
    final visible = _sorted(collapsed);
    final hasSeeders = collapsed.any((spec) => _seeders(spec) != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (collapsed.length > 1 || widget.onRefresh != null) ...<Widget>[
          Wrap(
            spacing: RivuletSpacing.s8,
            children: <Widget>[
              if (collapsed.length > 1) _sortControl(hasSeeders),
              if (widget.onRefresh case final refresh?)
                AppChip(
                  key: const ValueKey<String>('stream-refresh'),
                  icon: PhosphorIconsRegular.arrowClockwise,
                  label: AppStrings.of(context).play_refresh,
                  onActivate: refresh,
                ),
            ],
          ),
          const SizedBox(height: RivuletSpacing.s8),
        ],
        Expanded(
          child: ListView(
            key: const ValueKey<String>('play-source-streams'),
            children: <Widget>[
              AppRowGroup(
                overMedia: widget.overMedia,
                children: <Widget>[
                  for (var i = 0; i < visible.length; i++)
                    _paneKey(
                      LogicalKeyboardKey.arrowLeft,
                      widget.onArrowLeft,
                      _StreamRow(
                        key: ValueKey<String>('stream-row-$i'),
                        spec: visible[i],
                        providerName: widget.providerName,
                        autofocus: i == 0,
                        focusNode: i == 0 ? widget.firstFocusNode : null,
                        onTap: () => widget.onSelected(visible[i]),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final body = tokens.typeStyles.body.copyWith(
      color: tokens.colors.textSecondary,
    );
    return switch (widget.streams) {
      UiStreamListNone() => Padding(
        padding: const EdgeInsets.symmetric(vertical: RivuletSpacing.s16),
        child: AppText(
          key: const ValueKey<String>('play-source-pick-provider'),
          AppStrings.of(context).play_pickProvider,
          style: body,
        ),
      ),
      UiStreamListLoading(:final progress) => Center(
        child: Column(
          key: const ValueKey<String>('play-source-loading'),
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const OrbLoader.medium(state: OrbState.searching),
            const SizedBox(height: RivuletSpacing.s16),
            AppText(AppStrings.of(context).play_finding, style: body),
            if (progress != null) ...<Widget>[
              const SizedBox(height: RivuletSpacing.s16),
              SizedBox(
                width: 240,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(RivuletRadius.small),
                  child: LinearProgressIndicator(
                    key: const ValueKey<String>('play-source-progress'),
                    value: progress,
                    minHeight: 6,
                    color: tokens.colors.accent,
                    backgroundColor: tokens.colors.textSecondary.withValues(
                      alpha: 0.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: RivuletSpacing.s8),
              AppText(formatPercent(context, progress), style: body),
            ],
          ],
        ),
      ),
      UiStreamListFailed(:final message) => ErrorView(
        key: const ValueKey<String>('play-source-failed'),
        failure: UnexpectedFailure(cause: message),
        message: message,
        onRetry: widget.onRetry,
        onBack: widget.onBack,
        fullScreen: true,
      ),
      UiStreamListReady(:final streams) => _ready(streams),
    };
  }
}

/// One stream: quality badges, the name, size and seeds, then a caret. The
/// info button beside it shows the file name.
class _StreamRow extends StatelessWidget {
  const _StreamRow({
    required this.spec,
    required this.providerName,
    required this.autofocus,
    required this.onTap,
    this.focusNode,
    super.key,
  });

  final SourceSpec spec;
  final String providerName;
  final bool autofocus;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final colors = tokens.colors;
    final caption = tokens.typeStyles.caption;
    final display = parseStreamDisplay(
      spec,
      providerName: providerName,
      torrentName: AppStrings.of(context).play_torrent,
    );
    final infoLabel = display.release
        ? AppStrings.of(context).play_infoRelease
        : AppStrings.of(context).play_infoFileName;
    return AppRow(
      label: display.name,
      description: spec.expectedBytes == null
          ? null
          : formatFileSize(context, spec.expectedBytes!, decimalBytes: true),
      caret: true,
      autofocus: autofocus,
      focusNode: focusNode,
      onActivate: onTap,
      // Badges shrink beside a long name or a narrow phone.
      leading: display.badges.isEmpty
          ? null
          : Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (var i = 0; i < display.badges.length; i++) ...<Widget>[
                      if (i > 0) const SizedBox(width: RivuletSpacing.s4),
                      _QualityBadge(display.badges[i]),
                    ],
                  ],
                ),
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (display.seeders != null)
            Semantics(
              label: AppStrings.of(context).play_seeders(
                display.seeders!,
                formatCount(context, display.seeders!),
              ),
              excludeSemantics: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    PhosphorIconsRegular.arrowDown,
                    size: caption.fontSize,
                    color: colors.success,
                  ),
                  AppText(
                    formatCount(context, display.seeders!),
                    style: caption.copyWith(color: colors.success),
                  ),
                ],
              ),
            ),
          if (display.seeders != null) const SizedBox(width: RivuletSpacing.s8),
          AppIconButton(
            key: const ValueKey<String>('stream-info'),
            icon: PhosphorIconsRegular.info,
            semanticLabel: infoLabel,
            onActivate: () => showAppDialog<void>(
              context: context,
              builder: (_) => ChoiceDialogShell(
                title: infoLabel,
                child: SelectableText(
                  display.fileName,
                  style: tokens.typeStyles.body,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One spec badge: a small non-interactive chip (`tintFill`, `caption` 600).
/// Captions are the closed-caption glyph, everything else is its standard
/// mark ("4K", "HDR", "DV", ...).
class _QualityBadge extends StatelessWidget {
  const _QualityBadge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final caption = tokens.typeStyles.caption;
    return TintedSurface(
      radius: RivuletRadius.small,
      padding: const EdgeInsets.symmetric(
        horizontal: RivuletSpacing.s8,
        vertical: RivuletSpacing.s4,
      ),
      child: text == 'CC'
          ? Icon(
              PhosphorIconsRegular.closedCaptioning,
              key: const ValueKey<String>('badge-cc'),
              size: caption.fontSize! * caption.height!,
              color: tokens.colors.textPrimary,
            )
          : AppText(
              text,
              style: caption.copyWith(
                fontWeight: FontWeight.w600,
                color: tokens.colors.textPrimary,
              ),
            ),
    );
  }
}
