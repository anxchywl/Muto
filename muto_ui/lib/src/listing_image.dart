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
      child: ClipRect(
        child: CustomPaint(
          painter: _StripePainter(
            isLight ? palette : palette.reversed.toList(),
          ),
          child: Center(
            child: AppIcon(
              AppIcons.image,
              size: 28,
              color: isLight ? AppColors.white : AppColors.iconSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

final class _StripePainter extends CustomPainter {
  const _StripePainter(this.palette);

  final List<Color> palette;

  @override
  void paint(Canvas canvas, Size size) {
    final bandWidth = size.shortestSide * 0.16;
    final stripeGap = bandWidth * 1.5;
    final paint = Paint();
    for (var index = -8; index < 16; index++) {
      paint.color = palette[index.abs() % palette.length];
      final start = index * stripeGap;
      final path = Path()
        ..moveTo(start, 0)
        ..lineTo(start + bandWidth, 0)
        ..lineTo(start + size.height + bandWidth, size.height)
        ..lineTo(start + size.height, size.height)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_StripePainter oldDelegate) =>
      oldDelegate.palette != palette;
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
