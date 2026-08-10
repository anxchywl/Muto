import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import '../../application/cache/cache_keys.dart';
import '../../application/muto_scope.dart';
import '../../domain/entities/listing.dart';
import '../../l10n/generated/muto_localizations.dart';
import '../formatting/listing_labels.dart';
import '../shared/listing_feed_view.dart';

class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key, required this.onOpenListing});

  final void Function(Listing listing) onOpenListing;

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scope = MutoScope.of(context);
      scope.mine.configure(
        key: CacheKeys.mine(null),
        loader: (cursor) => scope.dependencies.listings.mine(cursor: cursor),
      );
      unawaited(scope.mine.load(force: true));
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
      appBar: AppBar(centerTitle: true, title: Text(strings.navMyListings)),
      body: ListenableBuilder(
        listenable: scope.mine,
        builder: (context, _) => ListingFeedView(
          feed: scope.mine,
          labels: labels,
          onOpenListing: widget.onOpenListing,
          emptyIcon: AppIcons.request,
          emptyTitle: strings.myListingsEmptyTitle,
          // saving your own listing is not a thing anyone wants to do
          showFavoriteToggle: false,
          reservesComposeButton: true,
        ),
      ),
    );
  }
}
