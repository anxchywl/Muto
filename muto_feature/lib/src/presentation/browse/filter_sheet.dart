import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/listing_category.dart';
import '../../domain/entities/listing_condition.dart';
import '../../domain/entities/listing_kind.dart';
import '../../domain/repositories/listing_repository.dart';
import '../../l10n/generated/muto_localizations.dart';
import '../formatting/listing_labels.dart';

/// Lets the reader narrow the feed.
///
/// Price bounds are deliberately absent: an amount only means something inside
/// one currency, and this build does no conversion, so a range across both
/// would quietly mislead.
Future<ListingQuery?> showFilterSheet(
  BuildContext context, {
  required ListingQuery current,
  required ListingLabels labels,
}) {
  return AppBottomSheet.show<ListingQuery>(
    context: context,
    child: _FilterSheet(initial: current, labels: labels),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial, required this.labels});

  final ListingQuery initial;
  final ListingLabels labels;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late ListingQuery _draft = widget.initial;

  MutoLocalizations get _strings => widget.labels.strings;

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _strings.filtersTitle,
            style: AppTextStyles.titleMedium.copyWith(
              color: isLight
                  ? AppColors.textPrimary
                  : AppColors.textPrimaryDark,
            ),
          ),
          const SizedBox(height: AppSpacing.df),

          _Group<ListingCategory?>(
            title: _strings.filterCategory,
            anyLabel: _strings.filterAny,
            selected: _draft.category,
            values: ListingCategory.values,
            labelOf: (value) => widget.labels.category(value!),
            onSelected: (value) => setState(() {
              _draft = value == null
                  ? _draft.copyWith(clearCategory: true)
                  : _draft.copyWith(category: value);
            }),
          ),
          const SizedBox(height: AppSpacing.df),

          _Group<ListingKind?>(
            title: _strings.filterKind,
            anyLabel: _strings.filterAny,
            selected: _draft.kind,
            values: ListingKind.values,
            labelOf: (value) => widget.labels.kind(value!),
            onSelected: (value) => setState(() {
              _draft = value == null
                  ? _draft.copyWith(clearKind: true)
                  : _draft.copyWith(kind: value);
            }),
          ),
          const SizedBox(height: AppSpacing.df),

          _Group<ListingCondition?>(
            title: _strings.filterCondition,
            anyLabel: _strings.filterAny,
            selected: _draft.condition,
            values: ListingCondition.values,
            labelOf: (value) => widget.labels.condition(value!),
            onSelected: (value) => setState(() {
              _draft = value == null
                  ? _draft.copyWith(clearCondition: true)
                  : _draft.copyWith(condition: value);
            }),
          ),
          const SizedBox(height: AppSpacing.df),

          _Group<ListingSort>(
            title: _strings.filterSort,
            selected: _draft.sort,
            values: ListingSort.values,
            labelOf: (value) => widget.labels.sort(value!),
            onSelected: (value) =>
                setState(() => _draft = _draft.copyWith(sort: value)),
          ),
          const SizedBox(height: AppSpacing.lg),

          Row(
            children: [
              Expanded(
                child: AppSecondaryButton(
                  text: _strings.actionReset,
                  size: AppButtonSize.medium,
                  onPressed: () =>
                      setState(() => _draft = const ListingQuery()),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppPrimaryButton(
                  text: _strings.actionApply,
                  size: AppButtonSize.medium,
                  onPressed: () => Navigator.of(context).pop(_draft),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One row of choices. [anyLabel] adds an unset option; omitting it makes the
/// group mandatory, which is what sorting is.
class _Group<T> extends StatelessWidget {
  const _Group({
    required this.title,
    required this.selected,
    required this.values,
    required this.labelOf,
    required this.onSelected,
    this.anyLabel,
  });

  final String title;
  final T? selected;
  final List<Object?> values;
  final String Function(T?) labelOf;
  final ValueChanged<T?> onSelected;
  final String? anyLabel;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.labelMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            if (anyLabel != null)
              _Choice(
                label: anyLabel!,
                selected: selected == null,
                isLight: isLight,
                onTap: () => onSelected(null),
              ),
            for (final value in values)
              _Choice(
                label: labelOf(value as T),
                selected: selected == value,
                isLight: isLight,
                onTap: () => onSelected(value),
              ),
          ],
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.isLight,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool isLight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = selected
        ? (isLight ? AppColors.primaryLight : AppColors.primaryLightDark)
        : (isLight ? AppColors.serviceBackground : AppColors.borderDark);
    final foreground = selected
        ? (isLight ? AppColors.primary : AppColors.primaryAccentDark)
        : AppColors.textSecondary;

    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppSpacing.borderRadiusSm,
        child: Container(
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
            style: AppTextStyles.chip.copyWith(color: foreground),
          ),
        ),
      ),
    );
  }
}
