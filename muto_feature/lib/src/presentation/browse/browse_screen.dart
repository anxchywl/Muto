import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import '../../application/cache/cache_keys.dart';
import '../../application/muto_scope.dart';
import '../../domain/entities/listing.dart';
import '../../domain/repositories/listing_repository.dart';
import '../../domain/validation/text_rules.dart';
import '../../l10n/generated/muto_localizations.dart';
import '../formatting/listing_labels.dart';
import '../shared/listing_feed_view.dart';
import 'filter_sheet.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key, required this.onOpenListing});

  final void Function(Listing listing) onOpenListing;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final TextEditingController _search = TextEditingController();

  ListingQuery _query = const ListingQuery();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _apply();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Points the feed at the current query and loads it. Reconfiguring with an
  /// unchanged key keeps whatever is cached, so this is safe to call often.
  void _apply() {
    final scope = MutoScope.of(context);
    final query = _query;
    scope.browse.configure(
      key: CacheKeys.browse(query),
      loader: (cursor) =>
          scope.dependencies.listings.browse(query: query, cursor: cursor),
    );
    unawaited(scope.browse.load());
  }

  void _onSearchChanged(String raw) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final text = TextRules.normalizeLine(raw);
      setState(() {
        _query = text.isEmpty
            ? _query.copyWith(clearText: true)
            : _query.copyWith(text: text);
      });
      _apply();
    });
  }

  Future<void> _openFilters(ListingLabels labels) async {
    final next = await showFilterSheet(
      context,
      current: _query,
      labels: labels,
    );
    if (next == null || !mounted) return;
    setState(() => _query = next);
    _apply();
  }

  @override
  Widget build(BuildContext context) {
    final scope = MutoScope.of(context);
    final strings = MutoLocalizations.of(context);
    final labels = ListingLabels(
      strings,
      Localizations.localeOf(context).toString(),
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.df,
                AppSpacing.sm,
                AppSpacing.df,
                AppSpacing.sm,
              ),
              child: GlobalSearchBar(
                controller: _search,
                hint: strings.searchHint,
                onChanged: _onSearchChanged,
                onClear: () => _onSearchChanged(''),
                clearTooltip: strings.clearSearchSemantics,
                showFilterButton: true,
                filterTooltip: strings.openFiltersSemantics,
                onFilterPressed: () => unawaited(_openFilters(labels)),
              ),
            ),
            Expanded(
              // rebuilt apart from the search field, so a feed update cannot
              // take the caret away mid-typing
              child: ListenableBuilder(
                listenable: scope.browse,
                builder: (context, _) => ListingFeedView(
                  feed: scope.browse,
                  labels: labels,
                  onOpenListing: widget.onOpenListing,
                  emptyIcon: AppIcons.search,
                  emptyTitle: strings.browseEmptyTitle,
                  emptyMessage: strings.browseEmptyMessage,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
