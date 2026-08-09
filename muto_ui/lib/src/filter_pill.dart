import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

/// One control in the strip above a feed: search, sort, or a filter dimension.
///
/// A pill carries an icon, a label, or both, and says whether it is doing
/// anything by being highlighted — so the strip shows at a glance what has been
/// narrowed without opening a single sheet.
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.onTap,
    this.icon,
    this.label,
    this.semanticLabel,
    this.highlighted = false,
    this.onClear,
    this.clearLabel,
  }) : assert(icon != null || label != null, 'a pill needs something to show'),
       assert(
         onClear == null || clearLabel != null,
         'a clear control has to announce itself',
       );

  final VoidCallback onTap;
  final AppIconData? icon;
  final String? label;

  /// Required in practice for an icon-only pill, which otherwise announces
  /// nothing at all.
  final String? semanticLabel;

  final bool highlighted;

  /// Lets go of whatever this pill is narrowed to. Shown as a cross inside the
  /// pill, and only while [highlighted] — there is nothing to let go of
  /// otherwise.
  final VoidCallback? onClear;

  final String? clearLabel;

  /// Tall enough to hit, and the height the strip reserves.
  static const double height = 40;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final foreground = highlighted
        ? (isLight ? AppColors.primary : AppColors.primaryAccentDark)
        : (isLight ? AppColors.textPrimary : AppColors.textPrimaryDark);
    final background = highlighted
        ? (isLight ? AppColors.primaryLight : AppColors.primaryLightDark)
        : (isLight ? AppColors.surface : AppColors.surfaceDark);
    final radius = AppSpacing.borderRadiusRound;
    final clear = highlighted && onClear != null;

    return Semantics(
      label: semanticLabel ?? label,
      button: true,
      selected: highlighted,
      excludeSemantics: !clear,
      child: Material(
        color: background,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: label == null
              ? SizedBox(
                  width: height,
                  height: height,
                  child: Center(
                    child: AppIcon(icon!, size: 18, color: foreground),
                  ),
                )
              : Container(
                  constraints: const BoxConstraints(
                    minWidth: height,
                    minHeight: height,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        AppIcon(icon!, size: 18, color: foreground),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 140),
                        child: Text(
                          label!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (clear) ...[
                        const SizedBox(width: AppSpacing.sm),
                        // bare glyph, no surface of its own: it belongs to the
                        // pill rather than sitting on top of it
                        Semantics(
                          label: clearLabel,
                          button: true,
                          excludeSemantics: true,
                          // its own node, or it merges into the pill's label
                          // and stops being addressable on its own
                          container: true,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onClear,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.sm,
                              ),
                              child: AppIcon(
                                AppIcons.close,
                                size: 14,
                                color: foreground,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
