import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:muto_ui/muto_ui.dart';

import '../../domain/entities/listing_category.dart';
import '../formatting/listing_labels.dart';

/// The categories, one tap away.
///
/// Browsing by category is the most common way into a marketplace, so it sits
/// on the surface rather than inside the filter sheet. Choosing here and
/// choosing there are the same choice, and the two always agree.
class CategoryStrip extends StatelessWidget {
  const CategoryStrip({
    super.key,
    required this.selected,
    required this.labels,
    required this.onSelected,
  });

  final ListingCategory? selected;
  final ListingLabels labels;
  final ValueChanged<ListingCategory?> onSelected;

  @override
  Widget build(BuildContext context) {
    final strings = labels.strings;

    return SizedBox(
      height: FilterPill.height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.df),
        itemCount: ListingCategory.values.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          if (index == 0) {
            return FilterPill(
              label: strings.categoryAll,
              highlighted: selected == null,
              onTap: () => onSelected(null),
            );
          }
          final category = ListingCategory.values[index - 1];
          return FilterPill(
            label: labels.category(category),
            highlighted: selected == category,
            onTap: () => onSelected(selected == category ? null : category),
          );
        },
      ),
    );
  }
}
