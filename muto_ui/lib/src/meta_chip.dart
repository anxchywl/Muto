import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

enum MetaTone { neutral, accent, positive, caution }

/// A small factual label: a condition, a category, or what a listing is asking
/// for in return. Text only, because a colour alone would say nothing to a
/// reader who cannot distinguish it.
class MetaChip extends StatelessWidget {
  const MetaChip({
    super.key,
    required this.label,
    this.tone = MetaTone.neutral,
  });

  final String label;
  final MetaTone tone;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final (background, foreground) = _colors(isLight);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
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
    );
  }

  (Color, Color) _colors(bool isLight) {
    switch (tone) {
      case MetaTone.neutral:
        return isLight
            ? (AppColors.serviceBackground, AppColors.textSecondary)
            : (AppColors.borderDark, AppColors.textSecondary);
      case MetaTone.accent:
        return isLight
            ? (AppColors.primaryLight, AppColors.primary)
            : (AppColors.primaryLightDark, AppColors.primaryAccentDark);
      case MetaTone.positive:
        return (AppColors.successLight, AppColors.success);
      case MetaTone.caution:
        return (AppColors.warningLight, AppColors.warning);
    }
  }
}
