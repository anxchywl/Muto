import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:muto_ui/muto_ui.dart';

import '../../application/muto_scope.dart';
import '../../domain/entities/listing.dart';
import '../../domain/entities/listing_status.dart';
import '../../domain/failures.dart';
import '../../l10n/generated/muto_localizations.dart';
import '../formatting/listing_labels.dart';
import '../editor/listing_editor_sheet.dart';
import '../images/listing_image_provider.dart';
import '../report/report_sheet.dart';
import '../seller/seller_profile_screen.dart';
import 'contact_channels.dart';
import 'contact_sheet.dart';
import 'owner_actions.dart';

/// One listing in full.
///
/// The cached copy paints immediately and the listing is always re-read on
/// open, because status is the field most likely to have moved since the feed
/// was loaded.
class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({
    super.key,
    required this.listingId,
    this.preloaded,
  });

  final String listingId;

  /// The row that opened this screen, used to paint something at once.
  final Listing? preloaded;

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  Listing? _listing;
  MutoFailure? _failure;

  @override
  void initState() {
    super.initState();
    _listing = widget.preloaded;
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  Future<void> _load() async {
    final scope = MutoScope.of(context);
    final generation = scope.generation.value;
    setState(() => _failure = null);

    try {
      final listing = await scope.dependencies.listings.byId(widget.listingId);
      if (!mounted || !scope.generation.isCurrent(generation)) return;
      scope.cache.absorb(listing);
      setState(() => _listing = listing);
    } on MutoFailure catch (failure) {
      if (!mounted || !scope.generation.isCurrent(generation)) return;
      if (failure is UnauthorizedFailure) scope.session.reportExpired();
      setState(() => _failure = failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = MutoLocalizations.of(context);
    final labels = ListingLabels(
      strings,
      Localizations.localeOf(context).toString(),
    );
    final listing = _listing;
    final failure = _failure;

    return Scaffold(
      appBar: AppBar(title: Text(strings.listingDetailTitle)),
      body: switch ((listing, failure)) {
        (null, final MutoFailure f) => _Unavailable(
          failure: f,
          strings: strings,
        ),
        (null, null) => const Center(child: AppLoader()),
        (final Listing value, _) => _Content(listing: value, labels: labels),
      },
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.failure, required this.strings});

  final MutoFailure failure;
  final MutoLocalizations strings;

  @override
  Widget build(BuildContext context) {
    // a listing the seller took down and one that never existed are different
    // situations, and saying which is the difference between an explanation
    // and an error
    final (title, message) = switch (failure) {
      GoneFailure() => (
        strings.listingUnavailableTitle,
        strings.listingRemovedMessage,
      ),
      NotFoundFailure() => (
        strings.listingUnavailableTitle,
        strings.listingNotFoundMessage,
      ),
      NetworkFailure() => (strings.browseErrorTitle, strings.errorOffline),
      _ => (strings.browseErrorTitle, strings.errorGeneric),
    };

    return StateMessage(
      icon: AppIcons.alertCircle,
      title: title,
      message: message,
      actionLabel: strings.actionBackToBrowse,
      onAction: () => Navigator.of(context).maybePop(),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.listing, required this.labels});

  final Listing listing;
  final ListingLabels labels;

  @override
  Widget build(BuildContext context) {
    final scope = MutoScope.of(context);
    final strings = labels.strings;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final identity = scope.session.identity;
    final isVerified = identity?.isVerified ?? false;
    final isOwner = identity != null && listing.isOwnedBy(identity);
    final channels = contactChannelsOf(listing.contact);
    final notice = _noticeFor(listing.status, strings);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: ListingImage(
            provider: resolveListingImage(
              scope.dependencies.imageLocator,
              listing.coverImage,
            ),
            semanticLabel: strings.listingImageSemantics(listing.title),
          ),
        ),
        Padding(
          padding: AppSpacing.screenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (notice != null) ...[
                _Notice(text: notice),
                const SizedBox(height: AppSpacing.df),
              ],
              Text(
                listing.title,
                style: AppTextStyles.titleLarge.copyWith(
                  color: isLight
                      ? AppColors.textPrimary
                      : AppColors.textPrimaryDark,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              PriceLabel(text: labels.price(listing), large: true),
              const SizedBox(height: AppSpacing.df),
              Row(
                children: [
                  Flexible(
                    child: MetaChip(
                      label: labels.kind(listing.kind),
                      tone: MetaTone.accent,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: MetaChip(label: labels.condition(listing.condition)),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: MetaChip(label: labels.category(listing.category)),
                  ),
                ],
              ),
              if (listing.description.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                _Section(
                  title: strings.detailDescription,
                  // plain text, never rich or auto-linked, so a crafted
                  // description cannot become a tappable destination
                  body: listing.description,
                ),
              ],
              if (listing.wantedItems != null) ...[
                const SizedBox(height: AppSpacing.lg),
                _Section(
                  title: strings.detailLookingFor,
                  body: listing.wantedItems!,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              _SellerRow(listing: listing, strings: strings),
              const SizedBox(height: AppSpacing.xl),
              if (isOwner)
                _OwnerActions(listing: listing, strings: strings)
              else if (!isVerified)
                Text(
                  strings.contactUnavailableUnverified,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                )
              else if (channels.isNotEmpty &&
                  listing.status != ListingStatus.sold)
                AppPrimaryButton(
                  text: strings.actionContactSeller,
                  size: AppButtonSize.large,
                  onPressed: () => unawaited(
                    showContactSheet(
                      context,
                      listing: listing,
                      strings: strings,
                    ),
                  ),
                ),
              if (!isOwner) ...[
                const SizedBox(height: AppSpacing.sm),
                _ReportAction(listingId: listing.id, labels: labels),
              ],
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ],
    );
  }
}

String? _noticeFor(ListingStatus status, MutoLocalizations strings) {
  return switch (status) {
    ListingStatus.sold => strings.noticeSold,
    ListingStatus.reserved => strings.noticeReserved,
    _ => null,
  };
}

/// Who is selling, and the way through to everything else they have listed.
class _SellerRow extends StatelessWidget {
  const _SellerRow({required this.listing, required this.strings});

  final Listing listing;
  final MutoLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: strings.openSellerSemantics(listing.sellerDisplayName),
      excludeSemantics: true,
      // its own node, so the row is announced as a control rather than folded
      // into the block of text above it
      container: true,
      child: InkWell(
        borderRadius: AppSpacing.borderRadiusMd,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SellerProfileScreen(
              sellerId: listing.sellerId,
              sellerDisplayName: listing.sellerDisplayName,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: _Section(
                  title: strings.detailSeller,
                  body: listing.sellerDisplayName,
                ),
              ),
              AppIcon(
                AppIcons.chevronRight,
                size: 20,
                color: AppColors.iconSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reporting sits below the contact action, quiet but reachable. It is not an
/// owner's action, and it never appears on a listing the reader owns.
class _ReportAction extends StatelessWidget {
  const _ReportAction({required this.listingId, required this.labels});

  final String listingId;
  final ListingLabels labels;

  @override
  Widget build(BuildContext context) {
    final strings = labels.strings;

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: AppTextButton(
        text: strings.actionReportListing,
        textColor: AppColors.textSecondary,
        onPressed: () => unawaited(_open(context)),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final sent = await showReportSheet(
      context,
      listingId: listingId,
      labels: labels,
    );
    if (sent != true || !context.mounted) return;
    AppToast.showSuccess(context, labels.strings.reportSent);
  }
}

/// Everything the owner may do to their own listing, taken from the transition
/// map so the screen can never offer a move the rules would refuse.
class _OwnerActions extends StatefulWidget {
  const _OwnerActions({required this.listing, required this.strings});

  final Listing listing;
  final MutoLocalizations strings;

  @override
  State<_OwnerActions> createState() => _OwnerActionsState();
}

class _OwnerActionsState extends State<_OwnerActions> {
  bool _busy = false;

  Future<void> _apply(OwnerAction action) async {
    if (_busy) return;
    final scope = MutoScope.of(context);
    final strings = widget.strings;

    if (action.isDestructive) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(strings.removeListingTitle),
          content: Text(strings.removeListingMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(strings.actionCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(strings.actionRemove),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _busy = true);
    final generation = scope.generation.value;
    try {
      final updated = await scope.dependencies.listings.changeStatus(
        widget.listing.id,
        action.next,
        expected: widget.listing.version,
      );
      if (!mounted || !scope.generation.isCurrent(generation)) return;
      scope.cache.patch(updated);
      unawaited(scope.mine.refresh());
      AppToast.showSuccess(
        context,
        action.isDestructive ? strings.listingRemoved : strings.listingUpdated,
      );
      unawaited(Navigator.of(context).maybePop());
    } on MutoFailure catch (failure) {
      if (!mounted) return;
      if (failure is UnauthorizedFailure) scope.session.reportExpired();
      AppToast.showError(
        context,
        failure is ConflictFailure
            ? strings.editorConflictMessage
            : strings.errorGeneric,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final saved = await showListingEditorSheet(
      context,
      editing: widget.listing,
    );
    if (saved == null || !mounted) return;
    unawaited(Navigator.of(context).maybePop());
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final actions = ownerActionsFor(widget.listing.status, strings);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.yourListing,
          style: AppTextStyles.labelMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (widget.listing.status.isEditable)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: AppSecondaryButton(
              text: strings.actionEditListing,
              size: AppButtonSize.medium,
              onPressed: _busy ? null : () => unawaited(_edit()),
            ),
          ),
        for (final action in actions)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: AppSecondaryButton(
              text: action.label,
              size: AppButtonSize.medium,
              onPressed: _busy ? null : () => unawaited(_apply(action)),
            ),
          ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: AppSpacing.borderRadiusMd,
      ),
      child: Text(
        text,
        style: AppTextStyles.bodySmall.copyWith(color: AppColors.warning),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.labelMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          body,
          style: AppTextStyles.bodyMedium.copyWith(
            color: isLight ? AppColors.textPrimary : AppColors.textPrimaryDark,
          ),
        ),
      ],
    );
  }
}
