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
    this.reservesComposeButton = false,
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

    if (!feed.hasLoaded && feed.failure != null) {
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
    if (!feed.hasLoaded) return _withStaticHeader(const ListingSkeleton());

    if (feed.items.isEmpty) {
      return _withStaticHeader(
        StateMessage(
          icon: widget.emptyIcon,
          title: widget.emptyTitle,
          message: widget.emptyMessage,
        ),
      );
    }

    final header = widget.header;
    // the header rides in the list itself, as row zero, rather than sitting
    // outside it — so it scrolls with the cards instead of apart from them
    final itemCount =
        (header == null ? 0 : 1) +
        feed.items.length +
        (feed.isLoadingMore ? 1 : 0);

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
              controller: _scroll,
              // the last row has to clear the compose button where there is
              // one, or the bottom of the feed is unreachable
              padding: EdgeInsets.fromLTRB(
                AppSpacing.df,
                header == null ? AppSpacing.df : 0,
                AppSpacing.df,
                widget.reservesComposeButton
                    ? AppSpacing.xxxl + AppSpacing.xl
                    : AppSpacing.df,
              ),
              itemCount: itemCount,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, index) {
                if (header != null && index == 0) return header;
                final itemIndex = header == null ? index : index - 1;

                if (itemIndex >= feed.items.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.df),
                    child: Center(child: AppLoader()),
                  );
                }
                final listing = feed.items[itemIndex];
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
                  trailing: widget.showFavoriteToggle
                      ? _FavoriteButton(listingId: listing.id)
                      : null,
                  onTap: () => widget.onOpenListing(listing),
                );
              },
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
  const _FavoriteButton({required this.listingId});

  final String listingId;

  @override
  Widget build(BuildContext context) {
    final favorites = MutoScope.of(context).savedListings;
    final strings = MutoLocalizations.of(context);

    return ListenableBuilder(
      listenable: favorites,
      builder: (context, _) {
        final saved = favorites.isSaved(listingId);
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
            onPressed: () => unawaited(favorites.toggle(listingId)),
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
