import '../l10n_gen/app_strings.dart';
import '../l10n/formatters.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/app_button.dart';
import '../components/app_dialog.dart';
import '../components/app_chip.dart';
import '../components/app_row.dart';
import '../l10n/app_text.dart';
import '../theme/rivulet_tokens.dart';
import 'choice_dialog.dart';

const _firstYear = 1900;

/// Result of the year popup. Both null means "any year".
typedef YearSelection = ({int? from, int? to});

/// The recent-years presets of the year dialog.
const _presets = <int>[1, 2, 5, 10];

/// Opens the year choice dialog (DESIGN_SPEC §8.9): Any year, the presets, or
/// a single year / range on the wheels. Returns null when dismissed.
Future<YearSelection?> showYearPicker(
  BuildContext context, {
  required int? from,
  required int? to,
}) {
  return showAppDialog<YearSelection>(
    context: context,
    builder: (context) => ChoiceDialogShell(
      title: AppStrings.of(context).year_title,
      child: _YearPickerCard(from: from, to: to),
    ),
  );
}

class _YearPickerCard extends StatefulWidget {
  const _YearPickerCard({required this.from, required this.to});
  final int? from, to;
  @override
  State<_YearPickerCard> createState() => _YearPickerCardState();
}

class _YearPickerCardState extends State<_YearPickerCard> {
  final _current = DateTime.now().year;
  bool _wheels = false;
  late bool _range = widget.from != null && widget.from != widget.to;
  late int _start = widget.from ?? _current;
  late int _end = widget.to ?? _current;
  late final _startCtrl = FixedExtentScrollController(
    initialItem: _current - _start,
  );
  late final _endCtrl = FixedExtentScrollController(
    initialItem: _current - _end,
  );

  final _applyNode = FocusNode();

  @override
  void dispose() {
    _applyNode.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  void _setMode(bool range) {
    if (range == _range) return;
    setState(() => _range = range);
    // The wheels are rebuilt for the new mode; keep them on the current years.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_startCtrl.hasClients) _startCtrl.jumpToItem(_current - _start);
      if (_endCtrl.hasClients) _endCtrl.jumpToItem(_current - _end);
    });
  }

  void _pick(int years) =>
      Navigator.pop(context, (from: _current - years, to: _current));

  /// The preset the current selection equals, if any.
  int? get _currentPreset {
    if (widget.from == null || widget.to != _current) return null;
    final years = _current - widget.from!;
    return _presets.any((p) => p == years) ? years : null;
  }

  Widget _rows() {
    final preset = _currentPreset;
    final any = widget.from == null;
    return SingleChildScrollView(
      child: AppRowGroup(
        children: <Widget>[
          AppRow(
            key: const ValueKey('year-clear'),
            label: AppStrings.of(context).common_anyYear,
            selected: any,
            autofocus: any,
            onActivate: () => Navigator.pop(context, (from: null, to: null)),
          ),
          for (final years in _presets)
            AppRow(
              key: ValueKey('year-preset-$years'),
              label: years == 1
                  ? AppStrings.of(context).year_pastYear
                  : AppStrings.of(context)
                        .year_lastYears(years, formatCount(context, years)),
              selected: preset == years,
              autofocus: preset == years,
              onActivate: () => _pick(years),
            ),
          AppRow(
            key: const ValueKey('year-custom'),
            label: AppStrings.of(context).year_singleOrRange,
            caret: true,
            selected: !any && preset == null,
            autofocus: !any && preset == null,
            onActivate: () => setState(() => _wheels = true),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_wheels) return _rows();
    final invalid = _range && _start > _end;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AppChip(
              key: const ValueKey('year-mode-single'),
              label: AppStrings.of(context).year_single,
              selected: !_range,
              onActivate: () => _setMode(false),
            ),
            const SizedBox(width: RivuletSpacing.s8),
            AppChip(
              key: const ValueKey('year-mode-range'),
              label: AppStrings.of(context).year_range,
              selected: _range,
              onActivate: () => _setMode(true),
            ),
          ],
        ),
        const SizedBox(height: RivuletSpacing.s16),
        SizedBox(
          height: 180,
          child: _range
              ? Row(
                  children: [
                    Expanded(
                      child: _Wheel(
                        key: const ValueKey('year-start'),
                        caption: AppStrings.of(context).year_from,
                        controller: _startCtrl,
                        first: _current,
                        autofocus: true,
                        onSelect: _applyNode.requestFocus,
                        onChanged: (y) => setState(() => _start = y),
                      ),
                    ),
                    Expanded(
                      child: _Wheel(
                        key: const ValueKey('year-end'),
                        caption: AppStrings.of(context).year_to,
                        controller: _endCtrl,
                        first: _current,
                        onSelect: _applyNode.requestFocus,
                        onChanged: (y) => setState(() => _end = y),
                      ),
                    ),
                  ],
                )
              : _Wheel(
                  key: const ValueKey('year-single'),
                  controller: _startCtrl,
                  first: _current,
                  autofocus: true,
                  onSelect: _applyNode.requestFocus,
                  onChanged: (y) => setState(() {
                    _start = y;
                    _end = y;
                  }),
                ),
        ),
        const SizedBox(height: RivuletSpacing.s16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton.secondary(
              key: const ValueKey('year-clear'),
              label: AppStrings.of(context).common_anyYear,
              onActivate: () => Navigator.pop(context, (from: null, to: null)),
            ),
            const SizedBox(width: RivuletSpacing.s12),
            AppButton.primary(
              key: const ValueKey('year-apply'),
              label: AppStrings.of(context).common_apply,
              focusNode: _applyNode,
              onActivate: invalid
                  ? null
                  : () => Navigator.pop(context, (
                      from: _start,
                      to: _range ? _end : _start,
                    )),
            ),
          ],
        ),
      ],
    );
  }
}

/// iPhone-timer style wheel, newest year on top. Up/Down (arrows, remote
/// D-pad) step one year; Select hands focus on to [onSelect]; Up on the
/// newest year and Left/Right fall through to normal focus traversal.
class _Wheel extends StatelessWidget {
  const _Wheel({
    required this.controller,
    required this.first,
    required this.onChanged,
    required this.onSelect,
    this.autofocus = false,
    this.caption,
    super.key,
  });
  final FixedExtentScrollController controller;
  final int first;
  final ValueChanged<int> onChanged;
  final VoidCallback onSelect;
  final bool autofocus;
  final String? caption;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) onSelect();
      return KeyEventResult.handled;
    }
    final step = key == LogicalKeyboardKey.arrowDown
        ? 1
        : key == LogicalKeyboardKey.arrowUp
        ? -1
        : 0;
    if (step == 0) return KeyEventResult.ignored;
    final target = controller.selectedItem + step;
    if (target < 0) return KeyEventResult.ignored;
    if (target > first - _firstYear) return KeyEventResult.handled;
    controller.animateToItem(
      target,
      duration: RivuletMotion.press,
      curve: RivuletMotion.easeOut,
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = RivuletTokens.of(context).colors;
    return Focus(
      autofocus: autofocus,
      onKeyEvent: _onKey,
      child: Builder(
        builder: (context) => Column(
          children: [
            if (caption != null)
              AppText(
                caption!,
                style: RivuletTokens.of(context).typeStyles.caption
                    .copyWith(color: c.textSecondary),
              ),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(RivuletRadius.small),
                  border: Border.all(
                    color: Focus.of(context).hasFocus
                        ? c.accent
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: CupertinoPicker(
                  scrollController: controller,
                  itemExtent: 36,
                  selectionOverlay: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.tintFillHover,
                      borderRadius: BorderRadius.circular(RivuletRadius.small),
                    ),
                  ),
                  onSelectedItemChanged: (i) => onChanged(first - i),
                  children: [
                    for (var y = first; y >= _firstYear; y--)
                      Center(
                        child: AppText(
                          formatYear(context, y),
                          style: RivuletTokens.of(context).typeStyles.title
                              .copyWith(color: c.textPrimary),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
