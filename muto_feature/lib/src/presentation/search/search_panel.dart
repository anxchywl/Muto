import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import '../../application/search_controller.dart';
import '../../l10n/generated/muto_localizations.dart';

/// What the search field offers while it has focus.
///
/// It covers the feed rather than pushing it down, so the results a student is
/// already looking at stay exactly where they were when the field is dismissed.
class SearchPanel extends StatelessWidget {
  const SearchPanel({
    super.key,
    required this.controller,
    required this.hasText,
    required this.onTerm,
    required this.strings,
  });

  final MutoSearchController controller;

  /// Recent searches answer "where was I"; suggestions answer "what did I
  /// mean". Only one of those is useful at a time.
  final bool hasText;

  final ValueChanged<String> onTerm;
  final MutoLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final rows = hasText ? const <Widget>[] : _recentRows(context, isLight);
        if (rows.isEmpty) return const SizedBox.shrink();

        return Material(
          color: isLight ? AppColors.background : AppColors.surfaceDark,
          child: ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.df),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: rows,
          ),
        );
      },
    );
  }

  List<Widget> _recentRows(BuildContext context, bool isLight) {
    if (controller.recent.isEmpty) return const [];

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.df,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.xs,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                strings.searchRecentTitle,
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            AppTextButton(
              text: strings.actionClearRecentSearches,
              onPressed: controller.forgetAll,
            ),
          ],
        ),
      ),
      for (final term in controller.recent)
        _TermRow(
          icon: AppIcons.history,
          label: term,
          onTap: () => onTerm(term),
          trailing: IconButton(
            icon: AppIcon(
              AppIcons.close,
              size: 18,
              color: AppColors.iconSecondary,
            ),
            tooltip: strings.removeRecentSearchSemantics(term),
            onPressed: () => controller.forget(term),
          ),
        ),
    ];
  }
}

class _TermRow extends StatelessWidget {
  const _TermRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.df,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            AppIcon(icon, size: 18, color: AppColors.iconSecondary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Semantics(
                button: true,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: isLight
                        ? AppColors.textPrimary
                        : AppColors.textPrimaryDark,
                  ),
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
