import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:muto_ui/muto_ui.dart';

import '../../application/cache/cache_keys.dart';
import '../../application/listing_feed_controller.dart';
import '../../application/muto_scope.dart';
import '../../domain/entities/listing.dart';
import '../../domain/entities/seller_contact.dart';
import '../../domain/entities/seller_profile.dart';
import '../../domain/failures.dart';
import '../../l10n/generated/muto_localizations.dart';
import '../formatting/listing_labels.dart';
import '../listing/contact_channels.dart';
import '../listing/listing_detail_screen.dart';
import '../shared/contact_buttons.dart';
import '../shared/listing_feed_view.dart';
import '../shared/monogram.dart';

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
    this.contact,
  });

  final String sellerId;

  /// Known from the listing that opened this screen, so the header has a name
  /// before the profile arrives.
  final String sellerDisplayName;

  /// Carried in from that same listing.
  ///
  /// The profile a server returns says who someone is and what they have, not
  /// how to reach them — contact details live on the listing, where they are
  /// gated on the reader being a verified student. Passing them in keeps that
  /// gate exactly where it already is rather than opening a second way to the
  /// same handles.
  final SellerContact? contact;

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

    // the seller's own name is the first thing in the page; repeating it in
    // the bar says nothing and leaves the bar unable to say what the page is
    return Scaffold(
      appBar: AppBar(title: Text(strings.sellerProfileTitle)),
      body: Column(
        children: [
          _Header(
            displayName: profile?.displayName ?? widget.sellerDisplayName,
            profile: profile,
            failed: _failure != null,
            labels: labels,
            contact: widget.contact,
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
    required this.contact,
  });

  final String displayName;
  final SellerProfile? profile;
  final bool failed;
  final ListingLabels labels;
  final SellerContact? contact;

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

    // the same gate the listing uses: an unverified reader is told why rather
    // than shown an empty space where the handles would be
    final isVerified =
        MutoScope.of(context).session.identity?.isVerified ?? false;
    final channels = isVerified
        ? contactChannelsOf(contact)
        : const <ContactChannel>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.df,
        AppSpacing.df,
        AppSpacing.df,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Monogram(name: displayName, isLight: isLight),
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
          if (channels.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              strings.sellerContactTitle,
              style: AppTextStyles.labelMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // text rows rather than the listing's buttons: this page is a
            // list of facts about someone, and one tap still copies the
            // handle and opens the chat
            ContactChannelList(channels: channels, strings: strings),
          ] else if (!isVerified) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              strings.contactUnavailableUnverified,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
