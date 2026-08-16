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
import '../search/search_panel.dart';
import '../shared/feed_layout.dart';
import '../shared/listing_feed_view.dart';
import 'browse_controls.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key, required this.onOpenListing});

  final void Function(Listing listing) onOpenListing;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  ListingQuery _query = const ListingQuery();

  /// Rows or tiles. Kept here rather than in the query, because it changes
  /// nothing about which listings are asked for — only how they are drawn.
  FeedLayout _layout = FeedLayout.rows;

  /// The strip is the search field's other half: opening search replaces it,
  /// and closing brings it back.
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    // the panel and the clear control both depend on whether anything has been
    // typed, which the field alone does not tell this screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _apply();
      final scope = MutoScope.of(context);
      final identity = scope.session.identity;
      if (identity != null) unawaited(scope.search.start(identity.userId));
    });
  }

  @override
  void dispose() {
    _searchFocus.dispose();
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

  void _onQueryChanged(ListingQuery next) {
    if (next.text != _query.text && (next.text ?? '').isEmpty) {
      _search.clear();
    }
    setState(() => _query = next);
    _apply();
  }

  void _openSearch() {
    setState(() => _searching = true);
    // the field is only mounted into view by this frame, so the caret has to
    // wait for it
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _searchFocus.unfocus();
    setState(() {
      _searching = false;
    });
  }

  void _onSearchChanged(String raw) {
    if (raw.trim().isEmpty) {
      _runSearch('', remember: false);
      return;
    }
  }

  /// A term the student chose deliberately — typed and submitted, or picked
  /// from the panel. Only these are worth remembering.
  void _onSearchSubmitted(String raw) {
    final term = TextRules.normalizeLine(raw);
    if (_search.text != term) _search.text = term;
    _searchFocus.unfocus();
    _runSearch(term, remember: true);
  }

  void _runSearch(String term, {required bool remember}) {
    setState(() {
      _query = term.isEmpty
          ? _query.copyWith(clearText: true)
          : _query.copyWith(text: term);
    });
    _apply();
    if (remember && term.isNotEmpty) {
      unawaited(MutoScope.of(context).search.submitted(term));
    }
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
      appBar: AppBar(centerTitle: true, title: Text(strings.navBrowse)),
      body: SafeArea(
        bottom: false,
        // the panel covers the feed instead of replacing it, so dismissing
        // the field puts the reader back where they were
        child: Stack(
          children: [
            ListenableBuilder(
              listenable: scope.browse,
              builder: (context, _) => ListingFeedView(
                feed: scope.browse,
                labels: labels,
                onOpenListing: widget.onOpenListing,
                emptyIcon: AppIcons.search,
                emptyTitle: strings.browseEmptyTitle,
                layout: _layout,
                header: BrowseControls(
                  query: _query,
                  labels: labels,
                  searching: _searching,
                  searchController: _search,
                  searchFocus: _searchFocus,
                  layout: _layout,
                  onQueryChanged: _onQueryChanged,
                  onLayoutToggled: () =>
                      setState(() => _layout = _layout.other),
                  onSearchOpened: _openSearch,
                  onSearchClosed: _closeSearch,
                  onSearchChanged: _onSearchChanged,
                  onSearchSubmitted: _onSearchSubmitted,
                ),
              ),
            ),
            if (_searching)
              Positioned(
                top: AppSpacing.sm + 40 + AppSpacing.sm,
                left: 0,
                right: 0,
                bottom: 0,
                child: SearchPanel(
                  controller: scope.search,
                  hasText: _search.text.trim().isNotEmpty,
                  onTerm: _onSearchSubmitted,
                  strings: strings,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
