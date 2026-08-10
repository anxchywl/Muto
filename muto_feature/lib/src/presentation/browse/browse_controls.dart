import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:muto_ui/muto_ui.dart';

import '../../domain/entities/listing_category.dart';
import '../../domain/entities/listing_condition.dart';
import '../../domain/entities/listing_kind.dart';
import '../../domain/repositories/listing_repository.dart';
import '../formatting/listing_labels.dart';
import 'choice_sheet.dart';

/// The strip above the feed: search, sort, and one pill per filter.
///
/// Searching and narrowing share a row rather than stacking, and the row turns
/// into the search field in place, so the feed keeps the height it had.
class BrowseControls extends StatelessWidget {
  const BrowseControls({
    super.key,
    required this.query,
    required this.labels,
    required this.searching,
    required this.searchController,
    required this.searchFocus,
    required this.onQueryChanged,
    required this.onSearchOpened,
    required this.onSearchClosed,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
  });

  final ListingQuery query;
  final ListingLabels labels;
  final bool searching;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final ValueChanged<ListingQuery> onQueryChanged;
  final VoidCallback onSearchOpened;
  final VoidCallback onSearchClosed;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;

  @override
  Widget build(BuildContext context) {
    final strings = labels.strings;

    return Padding(
      // horizontal space comes from the feed this sits inside, the same way
      // it does for a card, so the two line up
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      // both halves are the same height, so the swap is a movement rather than
      // a resize: each one slides the way the other left
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final isField = (child.key as ValueKey<bool>?)?.value ?? false;
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: Offset(isField ? 0.08 : -0.08, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.centerLeft,
          children: [...previous, ?current],
        ),
        child: searching
            ? FeedSearchField(
                key: const ValueKey<bool>(true),
                controller: searchController,
                focusNode: searchFocus,
                hint: strings.searchHint,
                onChanged: onSearchChanged,
                onSubmitted: onSearchSubmitted,
                onClose: onSearchClosed,
                clearLabel: strings.clearSearchSemantics,
                closeLabel: strings.closeSearchSemantics,
              )
            : SizedBox(
                key: const ValueKey<bool>(false),
                height: FilterPill.height,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
                  children: [
                    FilterPill(
                      icon: AppIcons.search,
                      semanticLabel: strings.searchHint,
                      highlighted: query.text?.isNotEmpty ?? false,
                      onTap: onSearchOpened,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilterPill(
                      icon: AppIcons.sort,
                      semanticLabel: strings.filterSort,
                      highlighted: query.sort != ListingSort.newest,
                      onTap: () => _pickSort(context),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilterPill(
                      label: query.category == null
                          ? strings.filterCategory
                          : labels.category(query.category!),
                      highlighted: query.category != null,
                      onTap: () => _pickCategory(context),
                      clearLabel: strings.clearFilterSemantics(
                        strings.filterCategory,
                      ),
                      onClear: () =>
                          onQueryChanged(query.copyWith(clearCategory: true)),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilterPill(
                      label: query.kind == null
                          ? strings.filterKind
                          : labels.kind(query.kind!),
                      highlighted: query.kind != null,
                      onTap: () => _pickKind(context),
                      clearLabel: strings.clearFilterSemantics(
                        strings.filterKind,
                      ),
                      onClear: () =>
                          onQueryChanged(query.copyWith(clearKind: true)),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilterPill(
                      label: query.condition == null
                          ? strings.filterCondition
                          : labels.condition(query.condition!),
                      highlighted: query.condition != null,
                      onTap: () => _pickCondition(context),
                      clearLabel: strings.clearFilterSemantics(
                        strings.filterCondition,
                      ),
                      onClear: () =>
                          onQueryChanged(query.copyWith(clearCondition: true)),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _pickSort(BuildContext context) async {
    final strings = labels.strings;
    final picked = await showChoiceSheet<ListingSort>(
      context,
      title: strings.filterSort,
      selected: query.sort,
      choices: [
        for (final sort in ListingSort.values)
          SheetChoice<ListingSort>(label: labels.sort(sort), value: sort),
      ],
    );
    final sort = picked?.value;
    if (sort == null) return;
    onQueryChanged(query.copyWith(sort: sort));
  }

  Future<void> _pickCategory(BuildContext context) async {
    final strings = labels.strings;
    final picked = await _pickOptional<ListingCategory>(
      context,
      title: strings.filterCategory,
      selected: query.category,
      values: ListingCategory.values,
      labelOf: labels.category,
    );
    if (picked == null) return;
    onQueryChanged(
      picked.value == null
          ? query.copyWith(clearCategory: true)
          : query.copyWith(category: picked.value),
    );
  }

  Future<void> _pickKind(BuildContext context) async {
    final strings = labels.strings;
    final picked = await _pickOptional<ListingKind>(
      context,
      title: strings.filterKind,
      selected: query.kind,
      values: ListingKind.values,
      labelOf: labels.kind,
    );
    if (picked == null) return;
    onQueryChanged(
      picked.value == null
          ? query.copyWith(clearKind: true)
          : query.copyWith(kind: picked.value),
    );
  }

  Future<void> _pickCondition(BuildContext context) async {
    final strings = labels.strings;
    final picked = await _pickOptional<ListingCondition>(
      context,
      title: strings.filterCondition,
      selected: query.condition,
      values: ListingCondition.values,
      labelOf: labels.condition,
    );
    if (picked == null) return;
    onQueryChanged(
      picked.value == null
          ? query.copyWith(clearCondition: true)
          : query.copyWith(condition: picked.value),
    );
  }

  /// Wraps the answer, because a filter that was let go of and a sheet that was
  /// dismissed both come back as null otherwise.
  ///
  /// There is no "any" row: choosing the value that is already chosen is what
  /// lets it go, the same gesture the pill itself would need.
  Future<({T? value})?> _pickOptional<T extends Object>(
    BuildContext context, {
    required String title,
    required T? selected,
    required List<T> values,
    required String Function(T) labelOf,
  }) async {
    final picked = await showChoiceSheet<T>(
      context,
      title: title,
      selected: selected,
      choices: [
        for (final value in values)
          SheetChoice<T>(label: labelOf(value), value: value),
      ],
      deselectable: true,
    );
    if (picked == null) return null;
    return (value: picked.value);
  }
}
