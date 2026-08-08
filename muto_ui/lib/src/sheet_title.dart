import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

/// The heading of a bottom sheet.
///
/// Centred and full width, so every sheet in the product is topped the same
/// way whatever it holds underneath.
class SheetTitle extends StatelessWidget {
  const SheetTitle({super.key, required this.text, required this.isLight});

  final String text;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppTextStyles.titleMedium.copyWith(
          color: isLight ? AppColors.textPrimary : AppColors.textPrimaryDark,
        ),
      ),
    );
  }
}
