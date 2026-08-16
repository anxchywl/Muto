import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:muto_ui/muto_ui.dart';

import '../../application/listing_feed_controller.dart';
import '../../application/muto_scope.dart';
import '../../domain/entities/listing.dart';
import '../../domain/failures.dart';
import '../../l10n/generated/muto_localizations.dart';
import '../formatting/listing_labels.dart';
import '../images/listing_image_provider.dart';
import 'feed_layout.dart';

/// One paginated list of listings, with every state it can be in.
///
/// Browse, favorites and the student's own listings differ in what they load
/// and what they say when empty, not in how a list behaves, so they share this.
class ListingFeedView extends StatefulWidget {
  const ListingFeedView({
    super.key,
    required this.feed,
    required this.labels,
    required this.onOpenListing,
    required this.emptyTitle,
    required this.emptyIcon,
    this.emptyMessage,
    this.showFavoriteToggle = true,
    this.itemFilter,
    this.extraItems = const [],
    this.reservesComposeButton = false,
    this.layout = FeedLayout.rows,
    this.header,
  });

  final ListingFeedController feed;
  final ListingLabels labels;
  final void Function(Listing listing) onOpenListing;
  final String emptyTitle;

  /// Left out where the title already says everything, which is most of the
  /// time — a second sentence under it reads as an apology.
  final String? emptyMessage;
  final AppIconData emptyIcon;
  final bool showFavoriteToggle;
  final bool Function(Listing listing)? itemFilter;
  final List<Listing> extraItems;

  /// Rows or tiles. The reader's choice, held by whoever owns this feed.
  final FeedLayout layout;

  /// Sits above the cards as the list's own first item, so it scrolls with
  /// them rather than floating apart from what it is searching and filtering.
  final Widget? header;

  /// Keeps a strip at the bottom clear for the compose button, on the one feed
  /// that has one. Elsewhere the last card would be looking at empty space.
  final bool reservesComposeButton;

  @override
  State<ListingFeedView> createState() => _ListingFeedViewState();
}

class _ListingFeedViewState extends State<ListingFeedView> {
  final ScrollController _scroll = ScrollController();
  double _savedOffset = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    _savedOffset = _scroll.offset;
    final remaining =
        _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (remaining < 400) unawaited(widget.feed.loadMore());
  }

  @override
  Widget build(BuildContext context) {
    final scope = MutoScope.of(context);
    final feed = widget.feed;
    final labels = widget.labels;
    final strings = labels.strings;
    final items = <Listing>[];
    final seen = <String>{};
    for (final listing in [...feed.items, ...widget.extraItems]) {
      if (widget.itemFilter != null && !widget.itemFilter!(listing)) continue;
      if (seen.add(listing.id)) items.add(listing);
    }

    if (!feed.hasLoaded && feed.failure != null && items.isEmpty) {
      return _withStaticHeader(
        StateMessage(
          icon: AppIcons.alertCircle,
          title: strings.browseErrorTitle,
          message: _messageFor(feed.failure!, strings),
          actionLabel: strings.actionRetry,
          onAction: () => unawaited(feed.refresh()),
        ),
      );
    }

    // nothing has arrived yet, which is not the same as nothing matching
    if (!feed.hasLoaded && items.isEmpty) {
      return _withStaticHeader(const ListingSkeleton());
    }

    if (items.isEmpty) {
      return _withStaticHeader(
        StateMessage(
          icon: widget.emptyIcon,
          title: widget.emptyTitle,
          message: widget.emptyMessage,
        ),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || _savedOffset == 0) return;
      final target = _savedOffset.clamp(
        _scroll.position.minScrollExtent,
        _scroll.position.maxScrollExtent,
      );
      if ((_scroll.offset - target).abs() > 0.5) _scroll.jumpTo(target);
    });

    final header = widget.header;
    final isGrid = widget.layout == FeedLayout.grid;

    Widget tileFor(Listing listing) {
      final isOwner = scope.session.identity?.userId == listing.sellerId;
      final trailing = widget.showFavoriteToggle && !isOwner
          ? _FavoriteButton(listing: listing)
          : null;
      final image = resolveListingImage(
        scope.dependencies.imageLocator,
        listing.coverImage,
      );
      final imageSemantics = strings.listingImageSemantics(listing.title);

      return isGrid
          ? ListingGridTile(
              title: listing.title,
              priceText: labels.cardPrice(listing),
              statusLabel: labels.status(listing.status),
              semanticLabel: labels.listingSemantics(listing),
              imageSemanticLabel: imageSemantics,
              image: image,
              trailing: trailing,
              onTap: () => widget.onOpenListing(listing),
            )
          : ListingCard(
              title: listing.title,
              priceText: labels.cardPrice(listing),
              statusLabel: labels.status(listing.status),
              semanticLabel: labels.listingSemantics(listing),
              imageSemanticLabel: imageSemantics,
              image: image,
              trailing: trailing,
              onTap: () => widget.onOpenListing(listing),
            );
    }

    // the last row has to clear the compose button where there is one, or the
    // bottom of the feed is unreachable
    final bottomInset = widget.reservesComposeButton
        ? AppSpacing.xxxl + AppSpacing.xl
        : AppSpacing.df;

    return RefreshIndicator(
      onRefresh: feed.refresh,
      child: Column(
        children: [
          if (feed.isShowingStaleData && feed.fetchedAt != null)
            _StaleNotice(
              text: strings.staleDataNotice(labels.savedAt(feed.fetchedAt!)),
            ),
          Expanded(
            // slivers rather than one list, because the header and the
            // loading foot are single full-width rows either way while the
            // listings between them are rows in one layout and a grid in the
            // other — three sections that scroll as one
            child: CustomScrollView(
              key: PageStorageKey<ListingFeedController>(widget.feed),
              controller: _scroll,
              slivers: [
                // the header rides in the scroll itself rather than sitting
                // outside it, so it moves with the cards instead of apart
                if (header != null)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.df,
                    ),
                    sliver: SliverToBoxAdapter(child: header),
                  ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.df,
                    header == null ? AppSpacing.df : 0,
                    AppSpacing.df,
                    feed.isLoadingMore ? 0 : bottomInset,
                  ),
                  sliver: isGrid
                      ? SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: AppSpacing.md,
                                crossAxisSpacing: AppSpacing.md,
                                // the photo is square and the block under it
                                // is two lines of text plus its padding, which
                                // is what this ratio reserves
                                childAspectRatio: 0.66,
                              ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => tileFor(items[index]),
                            childCount: items.length,
                          ),
                        )
                      : SliverList.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppSpacing.md),
                          itemBuilder: (context, index) =>
                              tileFor(items[index]),
                        ),
                ),
                if (feed.isLoadingMore)
                  SliverPadding(
                    padding: EdgeInsets.only(
                      top: AppSpacing.df,
                      bottom: bottomInset,
                    ),
                    sliver: const SliverToBoxAdapter(
                      child: Center(child: AppLoader()),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The header stays put here — there is nothing under it worth scrolling —
  /// but it keeps searching and filtering reachable even out of listings.
  Widget _withStaticHeader(Widget child) {
    final header = widget.header;
    if (header == null) return child;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.df),
          child: header,
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final favorites = MutoScope.of(context).savedListings;
    final strings = MutoLocalizations.of(context);

    return ListenableBuilder(
      listenable: favorites,
      builder: (context, _) {
        final saved = favorites.isSaved(listing.id);
        final label = saved
            ? strings.actionUnsaveListing
            : strings.actionSaveListing;

        return Semantics(
          label: label,
          button: true,
          toggled: saved,
          excludeSemantics: true,
          child: IconButton(
            tooltip: label,
            icon: AppIcon(
              AppIcons.heart,
              size: 20,
              color: saved ? AppColors.error : AppColors.iconSecondary,
            ),
            onPressed: () =>
                unawaited(favorites.toggle(listing.id, listing: listing)),
          ),
        );
      },
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
