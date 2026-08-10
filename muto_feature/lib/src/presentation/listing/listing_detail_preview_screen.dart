import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:muto_ui/muto_ui.dart';

import '../../application/muto_scope.dart';
import '../../domain/entities/listing.dart';
import '../formatting/listing_labels.dart';
import '../images/listing_image_provider.dart';

/// A read-only stand-in for [ListingDetailScreen], built off the draft that
/// is still being edited rather than a listing that exists yet.
///
/// Mirrors that screen's layout closely — same image, same order of facts —
/// so what a student sees here is what they will see once it is published,
/// not an approximation of it.
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
    final scope = MutoScope.of(context);
    final strings = labels.strings;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final title = draft.title.trim().isEmpty
        ? strings.editorFieldTitle
        : draft.title.trim();
    final description = draft.description.trim();
    final wantedItems = draft.wantedItems?.trim() ?? '';
    final priceText = labels.priceOf(draft.price, draft.kind);

    return Scaffold(
      appBar: AppBar(title: Text(strings.listingDetailTitle)),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppColors.primaryLight,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.df,
              vertical: AppSpacing.sm,
            ),
            child: Text(
              strings.editorPreviewHint,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: ListingImage(
                    provider: resolveListingImage(
                      scope.dependencies.imageLocator,
                      draft.images.isEmpty ? null : draft.images.first,
                    ),
                    semanticLabel: strings.listingImageSemantics(title),
                  ),
                ),
                Padding(
                  padding: AppSpacing.screenPadding,
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
                      const SizedBox(height: AppSpacing.sm),
                      PriceLabel(text: priceText, large: true),
                      const SizedBox(height: AppSpacing.df),
                      Row(
                        children: [
                          Flexible(
                            child: MetaChip(
                              label: labels.kind(draft.kind),
                              tone: MetaTone.accent,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Flexible(
                            child: MetaChip(
                              label: labels.condition(draft.condition),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Flexible(
                            child: MetaChip(
                              label: labels.category(draft.category),
                            ),
                          ),
                        ],
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _Section(
                          title: strings.detailDescription,
                          body: description,
                        ),
                      ],
                      if (wantedItems.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _Section(
                          title: strings.detailLookingFor,
                          body: wantedItems,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      _Section(
                        title: strings.detailSeller,
                        body: sellerDisplayName,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
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
