import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import '../../application/cache/cache_keys.dart';
import '../../application/muto_scope.dart';
import '../../domain/entities/listing.dart';
import '../../l10n/generated/muto_localizations.dart';
import '../formatting/listing_labels.dart';
import '../shared/listing_feed_view.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key, required this.onOpenListing});

  final void Function(Listing listing) onOpenListing;

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scope = MutoScope.of(context);
      scope.favorites.configure(
        key: CacheKeys.favorites,
        loader: (cursor) => scope.dependencies.favorites.page(cursor: cursor),
      );
      unawaited(scope.favorites.load());
    });
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
      appBar: AppBar(centerTitle: true, title: Text(strings.navFavorites)),
      body: ListenableBuilder(
        // the saved set is listened to as well, so unsaving something removes
        // it from this list without a reload
        listenable: Listenable.merge([scope.favorites, scope.savedListings]),
        builder: (context, _) => ListingFeedView(
          feed: scope.favorites,
          labels: labels,
          onOpenListing: widget.onOpenListing,
          showFavoriteToggle: false,
          itemFilter: (listing) => scope.savedListings.isSaved(listing.id),
          extraItems: scope.savedListings.optimisticListings,
          emptyIcon: AppIcons.heartBroken,
          emptyTitle: strings.favoritesEmptyTitle,
        ),
      ),
    );
  }
}
