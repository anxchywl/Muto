import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import 'listing_card.dart';

/// Placeholder rows shown while a feed loads for the first time.
///
/// Static on purpose: a shimmer that never stops is noise, and this is only
/// ever on screen for a moment.
class ListingSkeleton extends StatelessWidget {
  const ListingSkeleton({super.key, this.rows = 4});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ListView.separated(
        padding: AppSpacing.screenPadding,
        itemCount: rows,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (_, _) => const _SkeletonRow(),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final block = isLight ? AppColors.fieldBackground : AppColors.borderDark;

    return AppCard(
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(HomeRadius.card),
      child: SizedBox(
        height: listingRowHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: listingRowHeight,
              child: ColoredBox(color: block),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Bar(width: double.infinity, color: block),
                    const SizedBox(height: AppSpacing.sm),
                    _Bar(width: 140, color: block),
                    const SizedBox(height: AppSpacing.sm),
                    _Bar(width: 80, color: block),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.color});

  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppSpacing.borderRadiusXs,
      ),
    );
  }
}
