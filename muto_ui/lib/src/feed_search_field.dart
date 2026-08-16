import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

/// The search field that takes the place of the pill strip.
///
/// It is the same height as a pill so opening search does not resize the
/// header, and it carries its own trailing control: one tap clears what was
/// typed, a second closes the field.
class FeedSearchField extends StatelessWidget {
  const FeedSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClose,
    required this.clearLabel,
    required this.closeLabel,
    this.showLeadingIcon = true,
    this.maxLength = 80,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClose;

  /// Named apart, because the trailing control does one thing when there is
  /// text and another when there is not.
  final String clearLabel;
  final String closeLabel;
  final bool showLeadingIcon;

  final int maxLength;

  /// Matches the pills either side of it in the cross-fade.
  static const double height = 40;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final foreground = isLight
        ? AppColors.textPrimary
        : AppColors.textPrimaryDark;

    return GestureDetector(
      onTap: focusNode.requestFocus,
      child: Container(
        height: height,
        padding: EdgeInsets.only(
          left: showLeadingIcon ? AppSpacing.sm : AppSpacing.xxxl,
          right: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: (isLight ? AppColors.surface : AppColors.surfaceDark)
              .withValues(alpha: 0.92),
          borderRadius: AppSpacing.borderRadiusDf,
          border: Border.all(
            color: isLight ? AppColors.borderGrey : AppColors.borderDark,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 120) {
              return showLeadingIcon
                  ? const Center(
                      child: AppIcon(
                        AppIcons.search,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    )
                  : const SizedBox.shrink();
            }

            return Row(
              children: [
                if (showLeadingIcon) ...[
                  AppIcon(
                    AppIcons.search,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    maxLength: maxLength,
                    scrollPadding: EdgeInsets.zero,
                    textInputAction: TextInputAction.search,
                    onChanged: onChanged,
                    onSubmitted: onSubmitted,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: foreground,
                    ),
                    decoration: InputDecoration(
                      filled: false,
                      hintText: hint,
                      hintStyle: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      counterText: '',
                    ),
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) {
                    final hasText = value.text.isNotEmpty;
                    return Semantics(
                      label: hasText ? clearLabel : closeLabel,
                      button: true,
                      excludeSemantics: true,
                      child: Tooltip(
                        message: hasText ? clearLabel : closeLabel,
                        child: GestureDetector(
                          onTap: () {
                            if (!hasText) {
                              focusNode.unfocus();
                              onClose();
                              return;
                            }
                            controller.clear();
                            onChanged('');
                            focusNode.requestFocus();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                              vertical: AppSpacing.sm,
                            ),
                            child: AppIcon(
                              AppIcons.close,
                              size: 18,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
