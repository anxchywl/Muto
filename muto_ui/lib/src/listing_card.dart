import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import 'listing_image.dart';
import 'price_label.dart';

/// Height of a listing row, and the side of its square thumbnail.
///
/// Price and the chip row used to stack as their own line each; sitting them
/// side by side instead let this come down from 128 without losing anything
/// a reader could not already see.
const double listingRowHeight = 100;

/// One listing in a feed.
///
/// Everything it shows arrives already localized and already formatted. The
/// card decides layout and nothing else, which is what keeps it usable from
/// any screen without dragging the feature's rules along.
class ListingCard extends StatelessWidget {
  const ListingCard({
    super.key,
    required this.title,
    required this.priceText,
    required this.onTap,
    required this.semanticLabel,
    this.image,
    this.imageSemanticLabel,
    this.statusLabel,
    this.trailing,
  });

  final String title;

  /// Already formatted: an amount, or the wording used for a giveaway or swap.
  final String priceText;

  final VoidCallback onTap;

  /// What a screen reader announces for the row, so it reads as one thing
  /// rather than four disconnected fragments.
  final String semanticLabel;

  final ImageProvider? image;
  final String? imageSemanticLabel;

  /// Present only when the listing is not plainly available, such as reserved.
  final String? statusLabel;

  /// Sits outside the row's own semantics, so a control placed here keeps its
  /// own announcement instead of being swallowed by the card's.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    // a status footer takes the bottom corners for its own background, so
    // the card above it stays square there; with no footer the card owns
    // the whole shape and every corner rounds
    final card = AppCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      borderRadius: statusLabel == null
          ? BorderRadius.circular(HomeRadius.card)
          : BorderRadius.only(
              topLeft: Radius.circular(HomeRadius.card),
              topRight: Radius.circular(HomeRadius.card),
            ),
      // a fixed row height keeps the thumbnail square inside a list, where the
      // cross axis is otherwise unbounded
      child: SizedBox(
        height: listingRowHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Semantics(
                label: semanticLabel,
                button: true,
                excludeSemantics: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: listingRowHeight,
                      child: ListingImage(
                        provider: image,
                        semanticLabel: imageSemanticLabel,
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.xs,
                          trailing == null ? AppSpacing.md : AppSpacing.xxl,
                          AppSpacing.xs,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.titleSmall.copyWith(
                                color: isLight
                                    ? AppColors.textPrimary
                                    : AppColors.textPrimaryDark,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            PriceLabel(text: priceText),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final visibleCard = statusLabel == null
        ? card
        : Opacity(
            opacity: 0.62,
            child: ColorFiltered(
              colorFilter: const ColorFilter.matrix(<double>[
                0.2126,
                0.7152,
                0.0722,
                0,
                0,
                0.2126,
                0.7152,
                0.0722,
                0,
                0,
                0.2126,
                0.7152,
                0.0722,
                0,
                0,
                0,
                0,
                0,
                1,
                0,
              ]),
              child: card,
            ),
          );
    final cardWithTrailing = trailing == null
        ? visibleCard
        : Stack(
            children: [
              visibleCard,
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                child: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: Center(child: trailing),
                ),
              ),
            ],
          );

    if (statusLabel == null) return cardWithTrailing;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        cardWithTrailing,
        _StatusFooter(label: statusLabel!, isLight: isLight),
      ],
    );
  }
}

class _StatusFooter extends StatelessWidget {
  const _StatusFooter({required this.label, required this.isLight});

  final String label;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isLight ? AppColors.serviceBackground : AppColors.borderDark,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(HomeRadius.card),
          bottomRight: Radius.circular(HomeRadius.card),
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
