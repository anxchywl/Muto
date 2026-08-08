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
Future<T?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<SheetChoice<T>> choices,
  required T? selected,
}) {
  return AppBottomSheet.show<_Picked<T>>(
    context: context,
    // the tabs sit under a floating action button, which would otherwise
    // float above the sheet
    useRootNavigator: true,
    child: _ChoiceSheet<T>(title: title, choices: choices, selected: selected),
  ).then((picked) => picked?.value);
}

/// Wraps the answer so choosing the unset option can be told apart from
/// dismissing the sheet, since both would otherwise be null.
final class _Picked<T> {
  const _Picked(this.value);

  final T? value;
}

class _ChoiceSheet<T> extends StatelessWidget {
  const _ChoiceSheet({
    required this.title,
    required this.choices,
    required this.selected,
  });

  final String title;
  final List<SheetChoice<T>> choices;
  final T? selected;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.df,
              AppSpacing.sm,
              AppSpacing.df,
              AppSpacing.sm,
            ),
            child: SheetTitle(text: title, isLight: isLight),
          ),
          for (final choice in choices)
            _ChoiceRow<T>(
              label: choice.label,
              chosen: choice.value == selected,
              isLight: isLight,
              onTap: () => Navigator.of(
                context,
              ).pop<_Picked<T>>(_Picked<T>(choice.value)),
            ),
        ],
      ),
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

    return Semantics(
      button: true,
      selected: chosen,
      excludeSemantics: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.df,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: foreground,
                    fontWeight: chosen ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              if (chosen) AppIcon(AppIcons.check, size: 18, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}
