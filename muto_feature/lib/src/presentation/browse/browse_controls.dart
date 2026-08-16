import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:muto_ui/muto_ui.dart';

import '../../domain/entities/listing_category.dart';
import '../../domain/entities/listing_condition.dart';
import '../../domain/entities/listing_kind.dart';
import '../../domain/repositories/listing_repository.dart';
import '../formatting/listing_labels.dart';
import '../shared/feed_layout.dart';
import 'choice_sheet.dart';

/// The strip above the feed: search, sort, and one pill per filter.
///
/// Searching and narrowing share a row rather than stacking, and the row
/// crossfades into the search field at the same height, so the feed keeps
/// the height it had. Every pill — search included — sits in one scrollable
/// row, so a swipe carries all of them together rather than leaving search
/// pinned while the rest slide past it.
class BrowseControls extends StatelessWidget {
  const BrowseControls({
    super.key,
    required this.query,
    required this.labels,
    required this.searching,
    required this.searchController,
    required this.searchFocus,
    required this.layout,
    required this.onQueryChanged,
    required this.onLayoutToggled,
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
  final FeedLayout layout;
  final ValueChanged<ListingQuery> onQueryChanged;
  final VoidCallback onLayoutToggled;
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
      child: SizedBox(
        height: FilterPill.height,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                ignoring: searching,
                child: AnimatedOpacity(
                  duration: _morph,
                  curve: searching ? Curves.easeOutCubic : Curves.easeInCubic,
                  opacity: searching ? 0 : 1,
                  child: _FilterStrip(
                    query: query,
                    labels: labels,
                    layout: layout,
                    searchHighlighted: query.text?.isNotEmpty ?? false,
                    onQueryChanged: onQueryChanged,
                    onLayoutToggled: onLayoutToggled,
                    onSearchOpened: onSearchOpened,
                    onPickSort: () => _pickSort(context),
                    onPickCategory: () => _pickCategory(context),
                    onPickKind: () => _pickKind(context),
                    onPickCondition: () => _pickCondition(context),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) => Align(
                  alignment: Alignment.centerLeft,
                  child: IgnorePointer(
                    ignoring: !searching,
                    child: AnimatedContainer(
                      duration: _morph,
                      curve: Curves.easeInOutCubic,
                      width: searching
                          ? constraints.maxWidth
                          : FilterPill.height,
                      child: AnimatedOpacity(
                        duration: _morph,
                        curve: searching
                            ? Curves.easeOutCubic
                            : Curves.easeInCubic,
                        opacity: searching ? 1 : 0,
                        child: FeedSearchField(
                          controller: searchController,
                          focusNode: searchFocus,
                          hint: strings.searchHint,
                          onChanged: onSearchChanged,
                          onSubmitted: onSearchSubmitted,
                          onClose: onSearchClosed,
                          clearLabel: strings.clearSearchSemantics,
                          closeLabel: strings.closeSearchSemantics,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
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
      // category, type and condition are all one- or two-word labels
      asChips: true,
    );
    if (picked == null) return null;
    return (value: picked.value);
  }
}

/// Search, sort, the three filters, and the layout switch, in the order a
/// reader works through them: find, then narrow, then choose how to look at
/// what is left.
class _FilterStrip extends StatelessWidget {
  const _FilterStrip({
    required this.query,
    required this.labels,
    required this.layout,
    required this.searchHighlighted,
    required this.onQueryChanged,
    required this.onLayoutToggled,
    required this.onSearchOpened,
    required this.onPickSort,
    required this.onPickCategory,
    required this.onPickKind,
    required this.onPickCondition,
  });

  final ListingQuery query;
  final ListingLabels labels;
  final FeedLayout layout;
  final bool searchHighlighted;
  final ValueChanged<ListingQuery> onQueryChanged;
  final VoidCallback onLayoutToggled;
  final VoidCallback onSearchOpened;
  final VoidCallback onPickSort;
  final VoidCallback onPickCategory;
  final VoidCallback onPickKind;
  final VoidCallback onPickCondition;

  @override
  Widget build(BuildContext context) {
    final strings = labels.strings;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          FilterPill(
            icon: AppIcons.search,
            semanticLabel: strings.searchHint,
            highlighted: searchHighlighted,
            onTap: onSearchOpened,
          ),
          const SizedBox(width: AppSpacing.sm),
          FilterPill(
            icon: AppIcons.sort,
            semanticLabel: strings.filterSort,
            highlighted: query.sort != ListingSort.newest,
            onTap: onPickSort,
          ),
          const SizedBox(width: AppSpacing.sm),
          FilterPill(
            label: query.category == null
                ? strings.filterCategory
                : labels.category(query.category!),
            highlighted: query.category != null,
            onTap: onPickCategory,
            clearLabel: strings.clearFilterSemantics(strings.filterCategory),
            onClear: () => onQueryChanged(query.copyWith(clearCategory: true)),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilterPill(
            label: query.kind == null
                ? strings.filterKind
                : labels.kind(query.kind!),
            highlighted: query.kind != null,
            onTap: onPickKind,
            clearLabel: strings.clearFilterSemantics(strings.filterKind),
            onClear: () => onQueryChanged(query.copyWith(clearKind: true)),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilterPill(
            label: query.condition == null
                ? strings.filterCondition
                : labels.condition(query.condition!),
            highlighted: query.condition != null,
            onTap: onPickCondition,
            clearLabel: strings.clearFilterSemantics(strings.filterCondition),
            onClear: () => onQueryChanged(query.copyWith(clearCondition: true)),
          ),
          const SizedBox(width: AppSpacing.sm),
          // last rather than up by sort: the three filters it follows are all
          // "narrow to X", and grouping it with them read as a fourth filter
          // instead of the separate "now show it how" choice it actually is
          FilterPill(
            icon: layout.switchIcon,
            semanticLabel: layout == FeedLayout.rows
                ? strings.layoutShowGrid
                : strings.layoutShowRows,
            onTap: onLayoutToggled,
          ),
        ],
      ),
    );
  }
}

/// One beat for the growth, the fade and the swap inside it, so they read as
/// a single movement rather than three.
const Duration _morph = Duration(milliseconds: 280);
