import 'package:intl/intl.dart';

import '../l10n_gen/app_strings.dart';
import '../l10n/app_text.dart';
import '../components/app_dialog.dart';
import '../components/app_row.dart';
import '../components/app_switch.dart';
import '../components/orb_loader.dart';
import '../platform/adaptive_behavior.dart';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/app_text_field.dart';
import '../components/tinted_surface.dart';
import '../focus/focusable_action.dart';
import '../theme/rivulet_tokens.dart';
import 'settings_catalog.dart';

import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Title, optional tag and a trailing control: the chrome every row shares.
class _RowShell extends StatelessWidget {
  const _RowShell({
    required this.title,
    this.description,
    this.tag,
    this.trailing,
    this.onActivate,
  });

  final String title;
  final String? description;
  final String? tag;
  final Widget? trailing;
  final VoidCallback? onActivate;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      AppRow(
        label: title,
        description: description,
        trailing: trailing,
        onActivate: onActivate,
      ),
      if (tag != null)
        Padding(
          padding: const EdgeInsets.only(
            left: RivuletSpacing.s16,
            bottom: RivuletSpacing.s8,
          ),
          child: Align(alignment: Alignment.centerLeft, child: _Tag(tag!)),
        ),
    ],
  );
}

/// The small "Live" / "Restart" pill beside a row title.
class _Tag extends StatelessWidget {
  const _Tag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => TintedSurface(
    radius: RivuletRadius.small,
    padding: const EdgeInsets.symmetric(
      horizontal: RivuletSpacing.s8,
      vertical: RivuletSpacing.s4,
    ),
    child: AppText(
      label,
      style: RivuletTokens.of(context).typeStyles.caption
          .copyWith(fontWeight: FontWeight.w600),
    ),
  );
}

class SettingToggleRow extends StatelessWidget {
  const SettingToggleRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.tag,
    this.description,
    super.key,
  });

  final String title;
  final String? tag;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => _RowShell(
    title: title,
    description: description,
    tag: tag,
    onActivate: () => onChanged(!value),
    trailing: AppSwitch(value: value),
  );
}

class SettingChoiceRow extends StatelessWidget {
  const SettingChoiceRow({
    required this.title,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
    this.tag,
    this.description,
    super.key,
  });

  final String title;
  final String? tag;
  final String? description;
  final String value;
  final List<String> options;
  final String Function(String) labelOf;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => _RowShell(
    title: title,
    description: description,
    tag: tag,
    onActivate: () async {
      final picked = await showAppChoiceDialog<String>(
        context: context,
        title: title,
        options: {for (final option in options) option: labelOf(option)},
        current: value,
      );
      if (picked != null && picked != value) onChanged(picked);
    },
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: AppText(
            labelOf(value),
            overflow: TextOverflow.ellipsis,
            style: RivuletTokens.of(context).typeStyles.label.copyWith(
              color: RivuletTokens.of(context).colors.textSecondary,
            ),
          ),
        ),
        Icon(
          PhosphorIconsRegular.caretRight,
          size: AdaptiveBehavior.sizesOf(context).iconGlyph,
          color: RivuletTokens.of(context).colors.textSecondary,
        ),
      ],
    ),
  );
}

/// A free-text field. Every edit is reported at once.
class SettingTextRow extends StatefulWidget {
  const SettingTextRow({
    required this.title,
    required this.initial,
    required this.onChanged,
    this.validate,
    this.tag,
    this.description,
    this.multiline = false,
    super.key,
  });

  /// Several lines (a list of entries) instead of one.
  final bool multiline;
  final String title;
  final String? tag;
  final String? description;
  final String initial;
  final ValueChanged<String> onChanged;
  final String? Function(String)? validate;

  @override
  State<SettingTextRow> createState() => _SettingTextRowState();
}

class _SettingTextRowState extends State<SettingTextRow> {
  late String? _error = widget.validate?.call(widget.initial);
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _RowShell(
        title: widget.title,
        description: widget.description,
        tag: widget.tag,
      ),
      Padding(
        padding: const EdgeInsets.only(
          left: RivuletSpacing.s16,
          right: RivuletSpacing.s16,
          bottom: RivuletSpacing.s16,
        ),
        child: AppTextField(
          controller: _controller,
          hint: AppStrings.of(context).common_default,
          minLines: widget.multiline ? 3 : 1,
          maxLines: widget.multiline ? 8 : 1,
          errorText: _error,
          onChanged: (value) {
            setState(() => _error = widget.validate?.call(value));
            if (_error == null) widget.onChanged(value);
          },
        ),
      ),
    ],
  );
}

/// A number with a range: minus / plus buttons around "value unit". Values
/// are clamped to [min]..[max] and move by [step].
class SettingStepperRow extends StatelessWidget {
  const SettingStepperRow({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.unit,
    required this.onChanged,
    this.tag,
    this.description,
    this.zeroLabel,
    super.key,
  });

  final String title;
  final String? tag;
  final String? description;

  /// Shown instead of "0 unit" when 0 means unset ("Auto", "Unlimited").
  final String? zeroLabel;
  final double value;
  final double min;
  final double max;
  final double step;
  final String unit;
  final ValueChanged<double> onChanged;

  static String format(double v) => v == v.truncateToDouble()
      ? v.toInt().toString()
      : '${(v * 100).round() / 100}';

  void _move(double direction) {
    // Round away the binary noise of repeated 0.1 steps.
    final next = (value + direction * step).clamp(min, max);
    onChanged((next * 1000).round() / 1000);
  }

  Widget _button(
    BuildContext context,
    IconData icon,
    String label,
    double direction,
    bool enabled,
  ) => MergeSemantics(
    child: FocusableAction(
      key: ValueKey<String>('$title-$label'),
      enabled: enabled,
      onActivate: () => _move(direction),
      semanticLabel: AppStrings.of(context).settings_adjust(label, title),
      focusRadius: BorderRadius.circular(RivuletRadius.full),
      child: TintedSurface(
        radius: RivuletRadius.full,
        child: SizedBox.square(
          dimension: AdaptiveBehavior.sizesOf(context).iconButton,
          child: Icon(icon, size: AdaptiveBehavior.sizesOf(context).iconGlyph),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = RivuletTokens.of(context).colors;
    final styles = RivuletTokens.of(context).typeStyles;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      // DESIGN_SPEC §6.4 rule 6: Left/Right change the value.
      onKeyEvent: (_, event) {
        if (event is KeyUpEvent) return KeyEventResult.ignored;
        final direction = switch (event.logicalKey) {
          LogicalKeyboardKey.arrowLeft => -1.0,
          LogicalKeyboardKey.arrowRight => 1.0,
          _ => null,
        };
        if (direction == null) return KeyEventResult.ignored;
        _move(direction);
        return KeyEventResult.handled;
      },
      child: Padding(
        padding: EdgeInsets.zero,
        child: _RowShell(
          title: title,
          description: description,
          tag: tag,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _button(
                context,
                PhosphorIconsRegular.minus,
                AppStrings.of(context).settings_decrease,
                -1,
                value > min,
              ),
              SizedBox(
                width: 104,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AppText(
                    value == 0 && zeroLabel != null
                        ? zeroLabel!
                        : AppStrings.of(context).settings_valueUnit(
                            AppStrings.of(context).localeName == 'fa'
                                ? NumberFormat('0.##', 'fa').format(value)
                                : format(value),
                            settingUnit(unit, AppStrings.of(context)),
                          ),
                    style: styles.body.copyWith(color: colors.textPrimary),
                  ),
                ),
              ),
              _button(
                context,
                PhosphorIconsRegular.plus,
                AppStrings.of(context).settings_increase,
                1,
                value < max,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A multi-select checklist of [options].
class SettingListRow extends StatelessWidget {
  const SettingListRow({
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.labelOf,
    this.tag,
    this.description,
    super.key,
  });

  final String title;
  final String? tag;
  final String? description;
  final List<String> options;
  final List<String> selected;
  final String Function(String) labelOf;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RowShell(title: title, description: description, tag: tag),
        for (final option in options)
          Semantics(
            checked: selected.contains(option),
            child: AppRow(
              key: ValueKey<String>('list-option-$option'),
              label: labelOf(option),
              onActivate: () => onChanged(<String>[
                for (final o in options)
                  if (o == option
                      ? !selected.contains(o)
                      : selected.contains(o))
                    o,
              ]),
              trailing: Icon(
                selected.contains(option)
                    ? PhosphorIconsFill.checkSquare
                    : PhosphorIconsRegular.square,
                size: AdaptiveBehavior.sizesOf(context).iconGlyph,
                color: selected.contains(option)
                    ? tokens.colors.accent
                    : tokens.colors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}

/// A row that opens another page.
class SettingPageRow extends StatelessWidget {
  const SettingPageRow({required this.title, required this.onOpen, super.key});

  final String title;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) =>
      AppRow(label: title, caret: true, onActivate: onOpen);
}

/// A row that runs an action when activated and shows its outcome beside the
/// title (e.g. "Clear cache" -> "Freed 1.2 GB").
class SettingActionRow extends StatefulWidget {
  const SettingActionRow({required this.title, required this.run, super.key});

  final String title;

  /// Runs the action and returns the outcome text.
  final Future<String> Function() run;

  @override
  State<SettingActionRow> createState() => _SettingActionRowState();
}

class _SettingActionRowState extends State<SettingActionRow> {
  String _outcome = '';
  bool _busy = false;

  Future<void> _go() async {
    if (_busy) return;
    final strings = AppStrings.of(context);
    setState(() {
      _busy = true;
      _outcome = strings.settings_working;
    });
    String outcome;
    try {
      outcome = await widget.run();
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'settings',
          context: ErrorDescription('while running ${widget.title}'),
        ),
      );
      outcome = strings.settings_failed;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _outcome = outcome;
    });
  }

  @override
  Widget build(BuildContext context) => _RowShell(
    title: widget.title,
    onActivate: _go,
    trailing: _busy
        ? const OrbLoader.small()
        : _outcome.isEmpty
        ? Icon(
            PhosphorIconsRegular.trash,
            color: RivuletTokens.of(context).colors.textSecondary,
          )
        : AppText(
            _outcome,
            style: RivuletTokens.of(context).typeStyles.caption,
          ),
  );
}

/// "Auto" / "Unlimited" for a number whose default 0 means unset; null where
/// 0 is a real value (borders, shadow, dialogue boost).
String? _zeroLabel(SettingDef def, AppStrings strings) {
  if (def.min != 0 || def.defaultValue != '0') return null;
  return switch (def.unit) {
    'px' || 'dB' => null,
    'KB/s' => strings.settings_unlimited,
    _ => strings.common_auto,
  };
}

/// The control for one schema [def], reading and writing [values].
/// [onChanged] runs after every successful write so the owner can rebuild.
class SettingRow extends StatelessWidget {
  const SettingRow({
    required this.def,
    required this.values,
    required this.onChanged,
    required this.onOpenPage,
    this.choices,
    this.note,
    super.key,
  });

  final SettingDef def;
  final SettingsValues values;
  final VoidCallback onChanged;
  final VoidCallback onOpenPage;

  final Map<String, String>? choices;
  final String? note;

  Future<void> _write(Object value) async {
    await values.write(def, value);
    onChanged();
  }

  @override
  Widget build(BuildContext context) => _control(context);

  Widget _control(BuildContext context) {
    final title = settingLabel(def, AppStrings.of(context));
    const String? tag = null;
    final notes = [
      applyNote(def, AppStrings.of(context)),
      note,
    ].whereType<String>().join('\n');
    final description = notes.isEmpty ? null : notes;
    if (choices != null) {
      final saved = values.read<String>(def);
      return SettingChoiceRow(
        title: title,
        tag: tag,
        description: description,
        value: choices!.containsKey(saved) ? saved : choices!.keys.first,
        options: choices!.keys.toList(),
        labelOf: (value) => choices![value] ?? value,
        onChanged: _write,
      );
    }
    switch (def.kind) {
      case SettingKind.toggle:
        return SettingToggleRow(
          title: title,
          description: description,
          tag: tag,
          value: values.read<bool>(def),
          onChanged: _write,
        );
      case SettingKind.choice:
        return SettingChoiceRow(
          title: title,
          description: description,
          tag: tag,
          value: values.read<String>(def),
          options: <String>[
            if (!def.choices.contains(def.defaultValue)) def.defaultValue,
            ...def.choices,
          ],
          labelOf: (v) => choiceLabel(def, v, AppStrings.of(context)),
          onChanged: _write,
        );
      case SettingKind.number:
        return SettingStepperRow(
          title: title,
          description: description,
          tag: tag,
          value: values.read<double>(def),
          min: def.min!,
          max: def.max!,
          step: def.step!,
          unit: def.unit!,
          zeroLabel: _zeroLabel(def, AppStrings.of(context)),
          onChanged: _write,
        );
      case SettingKind.text:
      case SettingKind.path:
        return SettingTextRow(
          title: title,
          description: description,
          tag: tag,
          initial: values.read<String>(def),
          multiline: def.id == 'advanced.customMpvOptions',
          validate: def.id == 'languages.trackPriority'
              ? (value) {
                  if (values.validatePriority(value) == null) return null;
                  final token = value
                      .split(',')
                      .map((part) => part.trim())
                      .firstWhere(
                        (part) =>
                            part.isEmpty ||
                            values.validatePriority(part) != null,
                      );
                  return AppStrings.of(context)
                      .settings_invalidTrackRule(token);
                }
              : null,
          onChanged: _write,
        );
      case SettingKind.list:
        return SettingListRow(
          title: title,
          description: description,
          tag: tag,
          options: def.choices,
          selected: values.read<List<String>>(def),
          labelOf: (value) => choiceLabel(def, value, AppStrings.of(context)),
          onChanged: _write,
        );
      case SettingKind.page:
        return SettingPageRow(title: title, onOpen: onOpenPage);
    }
  }
}
