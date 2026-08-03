import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

/// A listing picture, or a quiet placeholder when there is none.
///
/// A missing image and an image that failed to load look the same on purpose:
/// both mean "no picture here", and neither is the student's problem to solve.
class ListingImage extends StatelessWidget {
  const ListingImage({
    super.key,
    required this.provider,
    this.semanticLabel,
    this.fit = BoxFit.cover,
  });

  final ImageProvider? provider;
  final String? semanticLabel;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final image = provider;
    if (image == null) return _Placeholder(semanticLabel: semanticLabel);

    return Image(
      image: image,
      fit: fit,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
      errorBuilder: (_, _, _) => _Placeholder(semanticLabel: semanticLabel),
      frameBuilder: (_, child, frame, wasSynchronous) {
        if (wasSynchronous || frame != null) return child;
        return _Placeholder(semanticLabel: semanticLabel);
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.semanticLabel});

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Semantics(
      label: semanticLabel,
      image: true,
      child: ColoredBox(
        color: isLight ? AppColors.fieldBackground : AppColors.surfaceDark,
        child: Center(
          child: AppIcon(
            AppIcons.image,
            size: 28,
            color: isLight ? AppColors.iconDisabled : AppColors.iconSecondary,
          ),
        ),
      ),
    );
  }
}
