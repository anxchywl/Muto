import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

/// A first letter rather than a photo. There are no avatars in this build, and
/// an empty circle says less than an initial does.
///
/// Shared between the seller's own profile page and a student's own listings,
/// which read the same way for the same reason: this is what stands in for a
/// photo of a person, wherever the app names one.
class Monogram extends StatelessWidget {
  const Monogram({
    super.key,
    required this.name,
    required this.isLight,
    this.size = 48,
  });

  final String name;
  final bool isLight;
  final double size;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty
        ? ''
        : String.fromCharCode(trimmed.runes.first).toUpperCase();

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isLight ? AppColors.primaryLight : AppColors.primaryLightDark,
      ),
      child: ExcludeSemantics(
        child: Text(
          initial,
          style:
              (size >= 48
                      ? AppTextStyles.titleMedium
                      : AppTextStyles.labelLarge)
                  .copyWith(
                    color: isLight
                        ? AppColors.primary
                        : AppColors.primaryAccentDark,
                  ),
        ),
      ),
    );
  }
}
