import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:muto_ui/muto_ui.dart';

import '../../application/muto_scope.dart';
import '../../domain/entities/image_ref.dart';
import '../../l10n/generated/muto_localizations.dart';
import '../images/listing_image_provider.dart';

/// How far the content sheet is pulled up over the foot of the photo. The
/// gallery keeps whatever it paints in that corner above this line.
const double sheetOverlap = 20;

const Duration detailConfirmationFade = Duration(milliseconds: 200);

/// The listing's pictures, full-bleed, one screen-width panel per photo.
///
/// Marketplace apps live and die on this: a shopper decides in the first
/// swipe whether to keep reading, so the photo gets the entire top of the
/// screen rather than sharing it with chrome.
class ListingImageGallery extends StatefulWidget {
  const ListingImageGallery({
    super.key,
    required this.images,
    required this.title,
    required this.strings,
    required this.price,
    this.header,
  });

  final List<ImageRef> images;
  final String title;
  final MutoLocalizations strings;

  /// Sits in the bottom corner of the photo, where it is the first thing read
  /// and costs the sheet below no room at all.
  final String price;
  final Widget? header;

  @override
  State<ListingImageGallery> createState() => _ListingImageGalleryState();
}

class _ListingImageGalleryState extends State<ListingImageGallery> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = MutoScope.of(context);
    final strings = widget.strings;
    final title = widget.title;
    final images = widget.images;
    final count = images.length;

    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (count == 0)
            ListingImage(
              provider: null,
              semanticLabel: strings.listingImageSemantics(title),
            )
          else
            PageView.builder(
              controller: _controller,
              itemCount: count,
              onPageChanged: (page) => setState(() => _page = page),
              itemBuilder: (context, index) => ListingImage(
                provider: resolveListingImage(
                  scope.dependencies.imageLocator,
                  images[index],
                ),
                semanticLabel: strings.listingImageSemantics(title),
              ),
            ),
          if (widget.header != null)
            Positioned(top: 0, left: 0, right: 0, child: widget.header!),
          // everything below sits above sheetOverlap, because the content
          // sheet is drawn over the foot of the photo and would otherwise
          // swallow it. the price and the count sit close to that seam
          // rather than floating mid-photo, which is where a price reads on
          // a marketplace card
          Positioned(
            left: AppSpacing.df,
            bottom: sheetOverlap + AppSpacing.xs,
            child: _PriceOverlay(text: widget.price),
          ),
          if (count > 1)
            Positioned(
              right: AppSpacing.df,
              bottom: sheetOverlap + AppSpacing.xs,
              child: _CountBadge(current: _page + 1, total: count),
            ),
          if (count > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: sheetOverlap - AppSpacing.xs,
              child: _DotIndicator(current: _page, total: count),
            ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.black.withValues(alpha: 0.55),
        borderRadius: AppSpacing.borderRadiusRound,
      ),
      child: Text(
        '$current/$total',
        style: AppTextStyles.labelSmall.copyWith(color: AppColors.white),
      ),
    );
  }
}

class _DotIndicator extends StatelessWidget {
  const _DotIndicator({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    // capped so a listing with many photos doesn't grow an unreadable row
    final shown = total > 8 ? 8 : total;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < shown; i++)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: i == current ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == current
                  ? AppColors.white
                  : AppColors.white.withValues(alpha: 0.5),
              borderRadius: AppSpacing.borderRadiusRound,
            ),
          ),
      ],
    );
  }
}

/// The price, read straight off the photo. It carries its own dark ground
/// because the picture underneath it is whatever the seller uploaded.
///
/// Sized like a badge rather than like the headline it used to be up in the
/// sheet: the price is confirmed again in full size the moment the sheet
/// comes into view underneath, so this copy only has to be legible at a
/// glance, not carry the weight of being the biggest thing on screen.
class _PriceOverlay extends StatelessWidget {
  const _PriceOverlay({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.black.withValues(alpha: 0.55),
        borderRadius: AppSpacing.borderRadiusSm,
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.amountSmall.copyWith(color: AppColors.white),
      ),
    );
  }
}

/// An icon over a photo, circled in a dark scrim so it reads against
/// whatever the photo underneath happens to be.
class DetailRoundIconButton extends StatelessWidget {
  const DetailRoundIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.backgroundColor,
  });

  final AppIconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final Color? color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    // an icon over a photo says nothing on its own, so the label it carries
    // for a screen reader is also the one a long press shows
    final button = Material(
      color: backgroundColor ?? AppColors.black.withValues(alpha: 0.4),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: AnimatedSwitcher(
            duration: detailConfirmationFade,
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: AppIcon(
              icon,
              key: ValueKey(icon),
              size: 20,
              color: color ?? AppColors.white,
            ),
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      child: tooltip == null
          ? button
          : Tooltip(message: tooltip!, child: button),
    );
  }
}

class DetailDivider extends StatelessWidget {
  const DetailDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Divider(
      height: 1,
      thickness: AppSpacing.dividerThin,
      color: isLight ? AppColors.borderGrey : AppColors.borderDark,
    );
  }
}

class DetailSection extends StatelessWidget {
  const DetailSection({super.key, required this.title, required this.body});

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
