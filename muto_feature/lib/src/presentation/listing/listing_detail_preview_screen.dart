import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:muto_ui/muto_ui.dart';

import '../../domain/entities/listing.dart';
import '../formatting/listing_labels.dart';
import 'listing_detail_visuals.dart';

/// A read-only stand-in for [ListingDetailScreen], built off the draft that
/// is still being edited rather than a listing that exists yet.
///
/// Shares the same photo-and-sheet shell as that screen, so what a student
/// sees here is what they will see once it is published, not an
/// approximation of it.
class ListingDetailPreviewScreen extends StatelessWidget {
  const ListingDetailPreviewScreen({
    super.key,
    required this.draft,
    required this.labels,
    required this.sellerDisplayName,
  });

  final ListingDraft draft;
  final ListingLabels labels;
  final String sellerDisplayName;

  @override
  Widget build(BuildContext context) {
    final strings = labels.strings;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final title = draft.title.trim().isEmpty
        ? strings.editorFieldTitle
        : draft.title.trim();
    final description = draft.description.trim();
    final wantedItems = draft.wantedItems?.trim() ?? '';
    final priceText = labels.priceOf(draft.price, draft.kind);

    final bottomReserve =
        AppSpacing.xxxxl + AppSpacing.df + MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: isLight ? AppColors.background : AppColors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: ListingImageGallery(
                    images: draft.images,
                    title: title,
                    strings: strings,
                    price: priceText,
                  ),
                ),
                SliverToBoxAdapter(
                  child: Transform.translate(
                    offset: const Offset(0, -sheetOverlap),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isLight ? AppColors.background : AppColors.black,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.df,
                        sheetOverlap + AppSpacing.xl,
                        AppSpacing.df,
                        bottomReserve,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: AppTextStyles.titleLarge.copyWith(
                              color: isLight
                                  ? AppColors.textPrimary
                                  : AppColors.textPrimaryDark,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            labels.postedDate(DateTime.now()),
                            style: AppTextStyles.labelSmall.copyWith(
                              color: isLight
                                  ? AppColors.textSecondary
                                  : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Wrap(
                            spacing: AppSpacing.xs,
                            runSpacing: AppSpacing.xs,
                            children: [
                              MetaChip(
                                label: labels.condition(draft.condition),
                              ),
                              MetaChip(label: labels.category(draft.category)),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          const DetailDivider(),
                          const SizedBox(height: AppSpacing.lg),
                          DetailSection(
                            title: strings.detailSeller,
                            body: sellerDisplayName,
                          ),
                          if (description.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.lg),
                            const DetailDivider(),
                            const SizedBox(height: AppSpacing.lg),
                            DetailSection(
                              title: strings.detailDescription,
                              body: description,
                            ),
                          ],
                          if (wantedItems.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.lg),
                            DetailSection(
                              title: strings.detailLookingFor,
                              body: wantedItems,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + AppSpacing.sm,
            left: AppSpacing.df,
            child: DetailRoundIconButton(
              icon: AppIcons.back,
              tooltip: strings.actionBackToBrowse,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _PreviewHintBanner(text: strings.editorPreviewHint),
          ),
        ],
      ),
    );
  }
}

/// The one line that keeps this screen from being mistaken for the real
/// thing — set apart from the facts around it with its own colour rather
/// than blending in as another grey caption.
class _PreviewHintBanner extends StatelessWidget {
  const _PreviewHintBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.df,
        AppSpacing.sm,
        AppSpacing.df,
        AppSpacing.sm + bottomInset,
      ),
      decoration: BoxDecoration(
        color: isLight ? AppColors.primaryLight : AppColors.primaryLightDark,
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppTextStyles.bodySmall.copyWith(
          color: isLight ? AppColors.primary : AppColors.primaryAccentDark,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
