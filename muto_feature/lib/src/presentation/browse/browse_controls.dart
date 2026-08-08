import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:muto_ui/muto_ui.dart';

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

  bool get _anyFilterActive =>
      query.kind != null ||
      query.condition != null ||
      query.category != null ||
      query.sort != ListingSort.newest ||
      (query.text?.isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    final strings = labels.strings;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.df,
        AppSpacing.sm,
        AppSpacing.df,
        AppSpacing.sm,
      ),
      child: AnimatedCrossFade(
        duration: const Duration(milliseconds: 200),
        sizeCurve: Curves.easeInOut,
        crossFadeState: searching
            ? CrossFadeState.showSecond
            : CrossFadeState.showFirst,
        firstChild: SizedBox(
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
                label: query.kind == null
                    ? strings.filterKind
                    : labels.kind(query.kind!),
                highlighted: query.kind != null,
                onTap: () => _pickKind(context),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilterPill(
                label: query.condition == null
                    ? strings.filterCondition
                    : labels.condition(query.condition!),
                highlighted: query.condition != null,
                onTap: () => _pickCondition(context),
              ),
              if (_anyFilterActive) ...[
                const SizedBox(width: AppSpacing.sm),
                FilterPill(
                  icon: AppIcons.close,
                  label: strings.actionClearFilters,
                  highlighted: true,
                  onTap: _clearAll,
                ),
              ],
            ],
          ),
        ),
        secondChild: SizedBox(
          height: FilterPill.height,
          child: Row(
            children: [
              Expanded(
                child: GlobalSearchBar(
                  controller: searchController,
                  focusNode: searchFocus,
                  hint: strings.searchHint,
                  // both halves of the cross-fade are built, so autofocus here
                  // would take the caret while the strip is still showing
                  maxLength: 80,
                  onChanged: onSearchChanged,
                  onSubmitted: onSearchSubmitted,
                  onClear: () => onSearchChanged(''),
                  clearTooltip: strings.clearSearchSemantics,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              IconButton(
                icon: const AppIcon(AppIcons.close, size: 20),
                tooltip: strings.closeSearchSemantics,
                onPressed: onSearchClosed,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _clearAll() {
    searchController.clear();
    onSearchClosed();
    onQueryChanged(const ListingQuery());
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
    if (picked == null) return;
    onQueryChanged(query.copyWith(sort: picked));
  }

  Future<void> _pickKind(BuildContext context) async {
    final strings = labels.strings;
    final picked = await _pickOptional<ListingKind>(
      context,
      title: strings.filterKind,
      anyLabel: strings.filterAny,
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
      anyLabel: strings.filterAny,
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

  /// Wraps the answer, because a filter that was set back to "any" and a sheet
  /// that was dismissed both come back as null otherwise.
  Future<({T? value})?> _pickOptional<T extends Object>(
    BuildContext context, {
    required String title,
    required String anyLabel,
    required T? selected,
    required List<T> values,
    required String Function(T) labelOf,
  }) async {
    const anySentinel = _AnyChoice();
    final picked = await showChoiceSheet<Object>(
      context,
      title: title,
      selected: selected ?? anySentinel,
      choices: [
        SheetChoice<Object>(label: anyLabel, value: anySentinel),
        for (final value in values)
          SheetChoice<Object>(label: labelOf(value), value: value),
      ],
    );
    if (picked == null) return null;
    return (value: picked == anySentinel ? null : picked as T);
  }
}

/// Stands in for "no filter" inside a sheet that picks one value.
final class _AnyChoice {
  const _AnyChoice();

  @override
  bool operator ==(Object other) => other is _AnyChoice;

  @override
  int get hashCode => 0;
}
