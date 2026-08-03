import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

/// A listing's price, or the word used when there is no price to show.
///
/// The text arrives already formatted for the reader's locale and currency;
/// this only decides how it looks.
class PriceLabel extends StatelessWidget {
  const PriceLabel({super.key, required this.text, this.large = false});

  final String text;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: (large ? AppTextStyles.amount : AppTextStyles.amountSmall)
          .copyWith(
            color: isLight ? AppColors.textPrimary : AppColors.textPrimaryDark,
          ),
    );
  }
}
