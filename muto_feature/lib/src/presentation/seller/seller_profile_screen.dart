import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:muto_ui/muto_ui.dart';

import '../../application/cache/cache_keys.dart';
import '../../application/listing_feed_controller.dart';
import '../../application/muto_scope.dart';
import '../../domain/entities/listing.dart';
import '../../domain/entities/seller_profile.dart';
import '../../domain/failures.dart';
import '../../l10n/generated/muto_localizations.dart';
import '../formatting/listing_labels.dart';
import '../listing/listing_detail_screen.dart';
import '../shared/listing_feed_view.dart';

/// Who is selling, and what else they have.
///
/// There is no reputation here and no history beyond the listings themselves,
/// because this marketplace has no ratings — the useful question is "what else
/// are they getting rid of", and that is what this answers.
class SellerProfileScreen extends StatefulWidget {
  const SellerProfileScreen({
    super.key,
    required this.sellerId,
    required this.sellerDisplayName,
  });

  final String sellerId;

  /// Known from the listing that opened this screen, so the header has a name
  /// before the profile arrives.
  final String sellerDisplayName;

  @override
  State<SellerProfileScreen> createState() => _SellerProfileScreenState();
}

class _SellerProfileScreenState extends State<SellerProfileScreen> {
  ListingFeedController? _feed;
  SellerProfile? _profile;
  MutoFailure? _failure;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _configureFeed();
      unawaited(_load());
    });
  }

  @override
  void dispose() {
    _feed?.dispose();
    super.dispose();
  }

  void _configureFeed() {
    final scope = MutoScope.of(context);
    final feed = _feed ??= scope.createFeed();
    feed.configure(
      key: CacheKeys.seller(widget.sellerId),
      loader: (cursor) =>
          scope.dependencies.sellers.listings(widget.sellerId, cursor: cursor),
    );
    unawaited(feed.load());
  }

  Future<void> _load() async {
    final scope = MutoScope.of(context);
    final generation = scope.generation.value;
    setState(() => _failure = null);

    try {
      final profile = await scope.dependencies.sellers.profile(widget.sellerId);
      if (!mounted || !scope.generation.isCurrent(generation)) return;
      setState(() => _profile = profile);
    } on MutoFailure catch (failure) {
      if (!mounted || !scope.generation.isCurrent(generation)) return;
      if (failure is UnauthorizedFailure) scope.session.reportExpired();
      setState(() => _failure = failure);
    }
  }

  void _openListing(Listing listing) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ListingDetailScreen(listingId: listing.id, preloaded: listing),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = MutoLocalizations.of(context);
    final labels = ListingLabels(
      strings,
      Localizations.localeOf(context).toString(),
    );
    final feed = _feed;
    final profile = _profile;

    return Scaffold(
      appBar: AppBar(title: Text(widget.sellerDisplayName)),
      body: Column(
        children: [
          _Header(
            displayName: profile?.displayName ?? widget.sellerDisplayName,
            profile: profile,
            failed: _failure != null,
            labels: labels,
          ),
          Expanded(
            child: feed == null
                ? const ListingSkeleton()
                : ListenableBuilder(
                    listenable: feed,
                    builder: (context, _) => ListingFeedView(
                      feed: feed,
                      labels: labels,
                      onOpenListing: _openListing,
                      emptyIcon: AppIcons.user,
                      emptyTitle: strings.sellerEmptyTitle,
                      emptyMessage: strings.sellerEmptyMessage,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.displayName,
    required this.profile,
    required this.failed,
    required this.labels,
  });

  final String displayName;
  final SellerProfile? profile;
  final bool failed;
  final ListingLabels labels;

  @override
  Widget build(BuildContext context) {
    final strings = labels.strings;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final resolved = profile;

    // the name is known from the listing, so a failed profile read leaves the
    // header standing rather than replacing the page with an error. the
    // listing count folds into the same line as flowing text rather than a
    // second chip competing for attention next to it
    final detail = switch ((resolved, failed)) {
      (final SellerProfile value, _) =>
        '${strings.sellerSince(labels.monthAndYear(value.firstListedAt))} · '
            '${strings.listingCount(value.activeListingCount)}',
      (null, true) => strings.sellerDetailsUnavailable,
      (null, false) => null,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.df,
        AppSpacing.df,
        AppSpacing.df,
        AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Monogram(name: displayName, isLight: isLight),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: isLight
                        ? AppColors.textPrimary
                        : AppColors.textPrimaryDark,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    detail,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A first letter rather than a photo. There are no avatars in this build, and
/// an empty circle says less than an initial does.
class _Monogram extends StatelessWidget {
  const _Monogram({required this.name, required this.isLight});

  final String name;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty
        ? ''
        : String.fromCharCode(trimmed.runes.first).toUpperCase();

    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isLight ? AppColors.primaryLight : AppColors.primaryLightDark,
      ),
      child: ExcludeSemantics(
        child: Text(
          initial,
          style: AppTextStyles.titleMedium.copyWith(
            color: isLight ? AppColors.primary : AppColors.primaryAccentDark,
          ),
        ),
      ),
    );
  }
}
