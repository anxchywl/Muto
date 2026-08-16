import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:muto_ui/muto_ui.dart';

/// One option in a [showChoiceSheet].
final class SheetChoice<T> {
  const SheetChoice({required this.label, required this.value});

  final String label;

  /// Null is the unset option, which is what "any" means for a filter.
  final T? value;
}

/// Picks one value from a short list.
///
/// Every filter in the strip narrows on a single value, so this is the whole
/// vocabulary the sheets need: a title, a list, and the one that is chosen.
/// [deselectable] makes the chosen row a toggle: tapping it answers with
/// nothing chosen, which is how a filter is let go of without a reset control.
///
/// [asChips] lays the options out as a wrap of chips instead of a column of
/// rows. Worth it wherever the labels are one or two words — eight categories
/// as a stack is a scroll, and as a wrap it is three lines you can take in at
/// once. Sorting keeps the rows, because "Price, low to high" is a sentence
/// and sentences do not belong in chips.
Future<Picked<T>?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<SheetChoice<T>> choices,
  required T? selected,
  bool deselectable = false,
  bool asChips = false,
}) {
  return AppBottomSheet.show<Picked<T>>(
    context: context,
    // the tabs sit under a floating action button, which would otherwise
    // float above the sheet
    useRootNavigator: true,
    child: _ChoiceSheet<T>(
      title: title,
      choices: choices,
      selected: selected,
      deselectable: deselectable,
      asChips: asChips,
    ),
  );
}

/// Wraps the answer so letting a filter go can be told apart from dismissing
/// the sheet, since both would otherwise be null.
final class Picked<T> {
  const Picked(this.value);

  final T? value;
}

class _ChoiceSheet<T> extends StatelessWidget {
  const _ChoiceSheet({
    required this.title,
    required this.choices,
    required this.selected,
    required this.deselectable,
    required this.asChips,
  });

  final String title;
  final List<SheetChoice<T>> choices;
  final T? selected;
  final bool deselectable;
  final bool asChips;

  void _choose(BuildContext context, SheetChoice<T> choice) {
    final chosen = choice.value == selected;
    Navigator.of(
      context,
    ).pop<Picked<T>>(Picked<T>(chosen && deselectable ? null : choice.value));
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: SheetTitle(text: title, isLight: isLight),
        ),
        if (asChips)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.df,
              AppSpacing.xs,
              AppSpacing.df,
              AppSpacing.sm,
            ),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final choice in choices)
                  SelectableChip(
                    label: choice.label,
                    selected: choice.value == selected,
                    onTap: () => _choose(context, choice),
                  ),
              ],
            ),
          )
        else
          for (final choice in choices)
            _ChoiceRow<T>(
              label: choice.label,
              chosen: choice.value == selected,
              isLight: isLight,
              onTap: () => _choose(context, choice),
            ),
      ],
    );
  }
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.chosen,
    required this.isLight,
    required this.onTap,
  });

  final String label;
  final bool chosen;
  final bool isLight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = chosen
        ? (isLight ? AppColors.primary : AppColors.primaryAccentDark)
        : (isLight ? AppColors.textPrimary : AppColors.textPrimaryDark);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 2,
      ),
      child: Semantics(
        button: true,
        selected: chosen,
        excludeSemantics: true,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppSpacing.borderRadiusMd,
          // the chosen row is filled rather than only tinted, so the answer is
          // legible without hunting for the check
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: chosen
                  ? (isLight
                        ? AppColors.primaryLight
                        : AppColors.primaryLightDark)
                  : Colors.transparent,
              borderRadius: AppSpacing.borderRadiusMd,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: foreground,
                      fontWeight: chosen ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (chosen)
                  AppIcon(AppIcons.check, size: 18, color: foreground),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
