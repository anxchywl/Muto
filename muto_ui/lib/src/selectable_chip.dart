import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

/// One choice among several, selected or not.
///
/// Used wherever a small set of options has to be picked from without opening
/// anything: a category row, a filter group. The label arrives translated; the
/// chip decides only how a choice looks.
class SelectableChip extends StatelessWidget {
  const SelectableChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Comfortably above the 44 logical pixels a finger needs, since a chip's
  /// text alone would be shorter than that.
  static const double minHeight = 44;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final background = selected
        ? (isLight ? AppColors.primaryLight : AppColors.primaryLightDark)
        : (isLight ? AppColors.serviceBackground : AppColors.borderDark);
    final foreground = selected
        ? (isLight ? AppColors.primary : AppColors.primaryAccentDark)
        : AppColors.textSecondary;

    // merged so a chip is announced once, as "label, selected, button", rather
    // than as a flagless node followed by a stray word
    return MergeSemantics(
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppSpacing.borderRadiusSm,
          child: Container(
            constraints: const BoxConstraints(minHeight: minHeight),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: AppSpacing.borderRadiusSm,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.chip.copyWith(color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}
