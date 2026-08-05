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
    required this.emptyMessage,
    required this.emptyIcon,
    this.showFavoriteToggle = true,
  });

  final ListingFeedController feed;
  final ListingLabels labels;
  final void Function(Listing listing) onOpenListing;
  final String emptyTitle;
  final String emptyMessage;
  final AppIconData emptyIcon;
  final bool showFavoriteToggle;

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
      return StateMessage(
        icon: AppIcons.alertCircle,
        title: strings.browseErrorTitle,
        message: _messageFor(feed.failure!, strings),
        actionLabel: strings.actionRetry,
        onAction: () => unawaited(feed.refresh()),
      );
    }

    // nothing has arrived yet, which is not the same as nothing matching
    if (!feed.hasLoaded) return const ListingSkeleton();

    if (feed.items.isEmpty) {
      return StateMessage(
        icon: widget.emptyIcon,
        title: widget.emptyTitle,
        message: widget.emptyMessage,
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
              controller: _scroll,
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
