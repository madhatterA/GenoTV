import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../components/ambient_background.dart';
import '../components/app_button.dart';
import '../components/app_chip.dart';
import '../l10n/app_text.dart';
import '../components/tinted_surface.dart';
import '../l10n_gen/app_strings.dart';
import '../navigation/page_back_button.dart';
import '../navigation/page_top_inset.dart';
import '../platform/adaptive_behavior.dart';
import '../theme/rivulet_tokens.dart';
import 'domain_editor.dart';

/// One Title API entry as the screen shows it.
class UiTitleApiEntry {
  const UiTitleApiEntry({
    required this.id,
    required this.name,
    required this.domain,
  });
  final String id;
  final String name;
  final String domain;
}

/// Settings > Title API: the ordered list the app tries top to bottom, each
/// entry with an editable domain (phase 14). Separate from Providers.
class TitleApiScreen extends StatefulWidget {
  const TitleApiScreen({
    required this.load,
    required this.onReorder,
    required this.onDomain,
    required this.onReset,
    super.key,
  });

  final List<UiTitleApiEntry> Function() load;
  final Future<void> Function(int from, int to) onReorder;
  final Future<String?> Function(String id, String? raw) onDomain;
  final Future<void> Function() onReset;

  @override
  State<TitleApiScreen> createState() => _TitleApiScreenState();
}

class _TitleApiScreenState extends State<TitleApiScreen> {
  late var _entries = widget.load();

  void _refresh() => setState(() => _entries = widget.load());

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final styles = RivuletTokens.of(context).typeStyles;
    final sizes = AdaptiveBehavior.sizesOf(context);
    final gutter = RivuletSpacing.gutterOf(context);
    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: sizes.settingsContentMaxWidth,
                ),
                child: ReorderableListView(
                  key: const ValueKey<String>('title-api-list'),
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    pageTopInsetOf(context),
                    gutter,
                    gutter,
                  ),
                  header: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(strings.settings_titleApi, style: styles.title),
                      const SizedBox(height: RivuletSpacing.s8),
                      AppText(
                        strings.settings_titleApi_hint,
                        style: styles.caption,
                      ),
                      const SizedBox(height: RivuletSpacing.s16),
                    ],
                  ),
                  footer: Padding(
                    padding: const EdgeInsets.only(top: RivuletSpacing.s16),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: AppButton.secondary(
                        key: const ValueKey<String>('title-api-reset'),
                        label: strings.titleApi_reset,
                        onActivate: () async {
                          await widget.onReset();
                          _refresh();
                        },
                      ),
                    ),
                  ),
                  onReorder: (from, to) async {
                    if (to > from) to -= 1;
                    await widget.onReorder(from, to);
                    _refresh();
                  },
                  children: [
                    for (final entry in _entries)
                      Padding(
                        key: ValueKey<String>('title-api-${entry.id}'),
                        padding: const EdgeInsets.only(
                          bottom: RivuletSpacing.s8,
                        ),
                        child: TintedSurface(
                          radius: RivuletRadius.medium,
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            RivuletSpacing.s16,
                            RivuletSpacing.s16,
                            RivuletSpacing.s48,
                            RivuletSpacing.s16,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    AppText(entry.name, style: styles.headline),
                                    AppText(
                                      entry.domain,
                                      style: styles.caption,
                                    ),
                                  ],
                                ),
                              ),
                              AppChip(
                                key: ValueKey<String>(
                                  'title-api-edit-${entry.id}',
                                ),
                                icon: PhosphorIconsRegular.globe,
                                label: strings.domain_change,
                                onActivate: () async {
                                  final saved = await showDomainDialog(
                                    context,
                                    title:
                                        '${entry.name} - ${strings.domain_label}',
                                    current: entry.domain,
                                    save: (raw) =>
                                        widget.onDomain(entry.id, raw),
                                  );
                                  if (saved == true) _refresh();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const PageBackButton(),
          ],
        ),
      ),
    );
  }
}
