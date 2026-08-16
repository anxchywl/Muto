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

    return Stack(
      fit: StackFit.expand,
      children: [
        _Placeholder(semanticLabel: semanticLabel),
        Image(
          image: image,
          fit: fit,
          semanticLabel: semanticLabel,
          excludeFromSemantics: semanticLabel == null,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
          frameBuilder: (_, child, frame, wasSynchronous) {
            final visible = wasSynchronous || frame != null;
            return AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: visible
                  ? const Duration(milliseconds: 120)
                  : Duration.zero,
              curve: Curves.easeOut,
              child: child,
            );
          },
        ),
      ],
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.semanticLabel});

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final palette =
        _placeholderPalettes[(semanticLabel ?? '').codeUnits.fold<int>(
              0,
              (sum, code) => sum + code,
            ) %
            _placeholderPalettes.length];
    return Semantics(
      label: semanticLabel,
      image: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isLight ? palette : palette.reversed.toList(),
            stops: const [0, 0.34, 0.67, 1],
          ),
        ),
        child: Center(
          child: AppIcon(
            AppIcons.image,
            size: 28,
            color: isLight ? AppColors.white : AppColors.iconSecondary,
          ),
        ),
      ),
    );
  }
}

const _placeholderPalettes = <List<Color>>[
  [AppColors.primary, AppColors.blue, AppColors.blueLight, AppColors.green],
  [AppColors.orange, AppColors.yellow, AppColors.red, AppColors.purple],
  [
    AppColors.blueLight,
    AppColors.blue,
    AppColors.primaryAccentDark,
    AppColors.purple,
  ],
  [AppColors.green, AppColors.blueLight, AppColors.blue, AppColors.primary],
];
