import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:muto_ui/muto_ui.dart';

import '../../application/cache/cache_keys.dart';
import '../../application/muto_scope.dart';
import '../../domain/entities/listing.dart';
import '../../domain/failures.dart';
import '../../domain/repositories/listing_repository.dart';
import '../../domain/validation/text_rules.dart';
import '../../l10n/generated/muto_localizations.dart';
import '../formatting/listing_labels.dart';
import '../images/listing_image_provider.dart';
import 'filter_sheet.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key, required this.onOpenListing});

  final void Function(Listing listing) onOpenListing;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();

  ListingQuery _query = const ListingQuery();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _apply());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final remaining =
        _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (remaining < 400) unawaited(MutoScope.of(context).browse.loadMore());
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
                showFilterButton: true,
                onFilterPressed: () => unawaited(_openFilters(labels)),
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: scope.browse,
                builder: (context, _) => _Results(
                  labels: labels,
                  scrollController: _scroll,
                  onOpenListing: widget.onOpenListing,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Split out so a rebuild from the feed does not rebuild the search field and
/// steal focus mid-typing.
class _Results extends StatelessWidget {
  const _Results({
    required this.labels,
    required this.scrollController,
    required this.onOpenListing,
  });

  final ListingLabels labels;
  final ScrollController scrollController;
  final void Function(Listing listing) onOpenListing;

  @override
  Widget build(BuildContext context) {
    final scope = MutoScope.of(context);
    final feed = scope.browse;
    final strings = labels.strings;

    if (!feed.hasLoaded && feed.isLoading) return const ListingSkeleton();

    if (!feed.hasLoaded && feed.failure != null) {
      return StateMessage(
        icon: AppIcons.alertCircle,
        title: strings.browseErrorTitle,
        message: _messageFor(feed.failure!, strings),
        actionLabel: strings.actionRetry,
        onAction: () => unawaited(feed.refresh()),
      );
    }

    if (feed.items.isEmpty) {
      return StateMessage(
        icon: AppIcons.search,
        title: strings.browseEmptyTitle,
        message: strings.browseEmptyMessage,
      );
    }

    return RefreshIndicator(
      onRefresh: feed.refresh,
      child: Column(
        children: [
          if (feed.isShowingStaleData && feed.fetchedAt != null)
            _StaleNotice(
              text: strings.staleDataNotice(labels.savedAt(feed.fetchedAt!)),
            ),
          Expanded(
            child: ListView.separated(
              controller: scrollController,
              padding: AppSpacing.screenPadding,
              itemCount: feed.items.length + (feed.isLoadingMore ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, index) {
                if (index >= feed.items.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.df),
                    child: Center(child: AppLoader()),
                  );
                }
                final listing = feed.items[index];
                return ListingCard(
                  title: listing.title,
                  priceText: labels.price(listing),
                  metaLabel: labels.condition(listing.condition),
                  statusLabel: labels.status(listing.status),
                  semanticLabel: labels.listingSemantics(listing),
                  imageSemanticLabel: strings.listingImageSemantics(
                    listing.title,
                  ),
                  image: resolveListingImage(
                    scope.dependencies.imageLocator,
                    listing.coverImage,
                  ),
                  onTap: () => onOpenListing(listing),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StaleNotice extends StatelessWidget {
  const _StaleNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.infoLight,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.df,
        vertical: AppSpacing.sm,
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppTextStyles.labelSmall.copyWith(color: AppColors.info),
      ),
    );
  }
}

String _messageFor(MutoFailure failure, MutoLocalizations strings) {
  return switch (failure) {
    NetworkFailure() => strings.errorOffline,
    _ => strings.errorGeneric,
  };
}
