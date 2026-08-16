import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import 'listing_image.dart';
import 'price_label.dart';

/// One listing as a tile in a two-column feed.
///
/// The same facts [ListingCard] carries, weighted for a shape that is taller
/// than it is wide: the photo gets the whole top rather than a square at one
/// end, and the price sits above the title because at this width a shopper is
/// scanning prices down a column and reading titles only where one stops them.
///
/// Everything arrives already localized and already formatted, as it does for
/// the row — the tile decides layout and nothing else.
class ListingGridTile extends StatelessWidget {
  const ListingGridTile({
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

  /// What a screen reader announces for the tile, so it reads as one thing
  /// rather than three disconnected fragments.
  final String semanticLabel;

  final ImageProvider? image;
  final String? imageSemanticLabel;

  /// Present only when the listing is not plainly available, such as reserved.
  final String? statusLabel;

  /// Sits over the top corner of the photo, outside the tile's own semantics,
  /// so a control placed here keeps its own announcement.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    // a status rides on the photo itself rather than adding a footer row
    // below it: a footer is extra height the grid's fixed-ratio cell does not
    // have to give, so it came out of the photo, which is what left a
    // reserved tile's image visibly shorter than an ordinary one right next
    // to it. every tile keeps the same Expanded-photo-plus-text shape now,
    // status or not, so a row of tiles lines up regardless of which ones
    // carry one
    final greyed = statusLabel != null;
    final photoImage = ListingImage(
      provider: image,
      semanticLabel: imageSemanticLabel,
    );

    final photo = Stack(
      fit: StackFit.expand,
      children: [
        greyed ? _Desaturated(child: photoImage) : photoImage,
        // sits outside the desaturation, so the label stays legible instead
        // of dimming along with the photo underneath it
        if (statusLabel != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _StatusBanner(label: statusLabel!),
          ),
      ],
    );

    final priceAndTitle = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          PriceLabel(text: priceText),
          const SizedBox(height: AppSpacing.xs),
          Text(
            title,
            maxLines: 2,
            // capped at two lines: tiles sit side by side, and a three-line
            // neighbour next to a one-line one leaves the row ragged
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyMedium.copyWith(
              color: isLight
                  ? AppColors.textPrimary
                  : AppColors.textPrimaryDark,
            ),
          ),
        ],
      ),
    );

    final tile = AppCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(HomeRadius.card),
      child: Semantics(
        label: semanticLabel,
        button: true,
        excludeSemantics: true,
        // the words take the height they need and the photo takes the rest,
        // rather than the photo claiming a fixed square and the text
        // overflowing whatever is left — a tile in a grid is handed its
        // height, and at a larger text scale that square would not fit
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: photo),
            greyed
                ? Opacity(opacity: 0.62, child: priceAndTitle)
                : priceAndTitle,
          ],
        ),
      ),
    );

    if (trailing == null) return tile;
    return Stack(
      children: [
        tile,
        Positioned(top: AppSpacing.xs, right: AppSpacing.xs, child: trailing!),
      ],
    );
  }
}

/// Greys out a photo for a listing that is not plainly available, the same
/// treatment [ListingCard] uses for a reserved or sold row.
class _Desaturated extends StatelessWidget {
  const _Desaturated({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Opacity(
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
        child: child,
      ),
    );
  }
}

/// A status across the foot of the photo, in the same dark scrim the price
/// overlay on a listing's own page uses — legible over whatever the photo
/// happens to be, rather than a bar with its own opaque background that
/// would need the tile's rounded corners repeated in exactly the right place.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      color: AppColors.black.withValues(alpha: 0.55),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: AppTextStyles.labelSmall.copyWith(color: AppColors.white),
      ),
    );
  }
}
