import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

/// Asks before something that cannot be taken back, as a sheet that rises from
/// the bottom rather than a box dropped in the middle of the screen.
///
/// Everything else that asks a question in this app arrives from below — the
/// editor, the report form — so a confirmation has no reason to arrive from
/// somewhere else. It also puts the answer under the thumb rather than at the
/// top of the reach, which matters most for the answer you cannot undo.
///
/// Resolves to `true` only on the confirming action. Dismissing the sheet, by
/// the cancel button or by dragging it away, resolves to `false`.
Future<bool> showConfirmSheet(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  required String cancelLabel,
  bool isDestructive = false,
}) async {
  final confirmed = await AppBottomSheet.show<bool>(
    context: context,
    useRootNavigator: true,
    child: _ConfirmSheet(
      title: title,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      isDestructive: isDestructive,
    ),
  );
  return confirmed ?? false;
}

class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({
    required this.title,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.isDestructive,
  });

  final String title;
  final String confirmLabel;
  final String cancelLabel;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.df,
        AppSpacing.sm,
        AppSpacing.df,
        AppSpacing.df,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyles.titleMedium.copyWith(
              color: isLight
                  ? AppColors.textPrimary
                  : AppColors.textPrimaryDark,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // side by side, with the consequence given the wider half — it is
          // the answer being asked for, and backing out is the easy one to
          // find either way
          Row(
            children: [
              Expanded(
                flex: 2,
                child: AppSecondaryButton(
                  text: cancelLabel,
                  size: AppButtonSize.medium,
                  borderColor: isLight
                      ? AppColors.borderGrey
                      : AppColors.borderDark,
                  textColor: AppColors.textSecondary,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 3,
                child: AppPrimaryButton(
                  text: confirmLabel,
                  // red, and taller than the way out, because it is the one
                  // that cannot be taken back
                  size: AppButtonSize.large,
                  backgroundColor: isDestructive ? AppColors.error : null,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
