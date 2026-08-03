import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import 'listing_image.dart';
import 'meta_chip.dart';
import 'price_label.dart';

/// Height of a listing row, and the side of its square thumbnail.
const double listingRowHeight = 128;

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
    this.metaLabel,
    this.statusLabel,
    this.trailing,
  });

  final String title;

  /// Already formatted: an amount, or the wording used for a giveaway or swap.
  final String priceText;

  final VoidCallback onTap;

  /// What a screen reader announces for the whole card, so the row reads as one
  /// thing rather than four disconnected fragments.
  final String semanticLabel;

  final ImageProvider? image;
  final String? imageSemanticLabel;

  /// Condition, or another single fact worth showing in a feed.
  final String? metaLabel;

  /// Present only when the listing is not plainly available, such as reserved.
  final String? statusLabel;

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Semantics(
      label: semanticLabel,
      button: true,
      excludeSemantics: true,
      child: AppCard(
        onTap: onTap,
        padding: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(HomeRadius.card),
        // a fixed row height keeps the thumbnail square inside a list, where
        // the cross axis is otherwise unbounded
        child: SizedBox(
          height: listingRowHeight,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
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
                      if (metaLabel != null || statusLabel != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        // one line, never wrapping, so a row keeps the same
                        // height whatever the screen width
                        Row(
                          children: [
                            if (statusLabel != null)
                              Flexible(
                                child: MetaChip(
                                  label: statusLabel!,
                                  tone: MetaTone.caution,
                                ),
                              ),
                            if (statusLabel != null && metaLabel != null)
                              const SizedBox(width: AppSpacing.xs),
                            if (metaLabel != null)
                              Flexible(child: MetaChip(label: metaLabel!)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (trailing != null)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: Center(child: trailing),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
