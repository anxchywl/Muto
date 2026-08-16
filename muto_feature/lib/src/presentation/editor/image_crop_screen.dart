import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../domain/repositories/image_repository.dart';
import '../../l10n/generated/muto_localizations.dart';

/// Square side of the crop viewport, in logical pixels.
const double _viewportSide = 300;

/// Resolution the crop is rendered at, independent of screen density, so a
/// small phone does not quietly ship a soft photo.
const double _outputSide = 900;

const double _minScale = 1;
const double _maxScale = 3.5;

/// Lets the student reposition and zoom a photo into a square before it is
/// attached to the listing, the way a picked photo rarely arrives pre-framed.
///
/// Answers with the cropped image, or nothing if they backed out — in which
/// case the original pick is discarded rather than attached unedited.
Future<StagedImage?> showImageCropScreen(
  BuildContext context, {
  required Uint8List bytes,
}) {
  return Navigator.of(context).push<StagedImage>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ImageCropScreen(bytes: bytes),
    ),
  );
}

class ImageCropScreen extends StatefulWidget {
  const ImageCropScreen({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> {
  final GlobalKey _boundaryKey = GlobalKey();
  late final ImageProvider _provider = MemoryImage(widget.bytes);

  double _scale = _minScale;
  Offset _offset = Offset.zero;
  Size? _imageSize;

  double _gestureStartScale = 1;
  Offset _gestureStartOffset = Offset.zero;
  Offset _gestureStartFocal = Offset.zero;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final stream = _provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      if (!mounted) return;
      setState(() {
        _imageSize = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
        // the frame picked before the natural size was known assumed a
        // square photo; now that the real aspect ratio is in, pull the pan
        // back inside whatever the true bounds turn out to be
        _offset = _constrain(_offset, _scale);
      });
      stream.removeListener(listener);
    });
    stream.addListener(listener);
  }

  /// The side, in logical pixels, the image would take up at scale 1 so that
  /// it fully covers the square viewport — cover, never contain, since the
  /// frame must never show empty space.
  Size _baseSize() {
    final natural = _imageSize;
    if (natural == null) return const Size(_viewportSide, _viewportSide);
    final aspect = natural.width / natural.height;
    return aspect >= 1
        ? Size(_viewportSide * aspect, _viewportSide)
        : Size(_viewportSide, _viewportSide / aspect);
  }

  Offset _constrain(Offset offset, double scale) {
    final base = _baseSize();
    final w = base.width * scale;
    final h = base.height * scale;
    final maxX = (w - _viewportSide) / 2;
    final maxY = (h - _viewportSide) / 2;
    return Offset(
      maxX <= 0 ? 0 : offset.dx.clamp(-maxX, maxX),
      maxY <= 0 ? 0 : offset.dy.clamp(-maxY, maxY),
    );
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStartScale = _scale;
    _gestureStartOffset = _offset;
    _gestureStartFocal = details.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final nextScale = (_gestureStartScale * details.scale).clamp(
      _minScale,
      _maxScale,
    );
    final pan = details.focalPoint - _gestureStartFocal;
    setState(() {
      _scale = nextScale;
      _offset = _constrain(_gestureStartOffset + pan, nextScale);
    });
  }

  Future<void> _apply() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final boundary =
          _boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final pixelRatio = _outputSide / _viewportSide;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null || !mounted) return;
      final result = StagedImage(
        bytes: data.buffer.asUint8List(),
        mimeType: 'image/png',
        width: _outputSide.round(),
        height: _outputSide.round(),
      );
      Navigator.of(context).pop(result);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = MutoLocalizations.of(context);
    final base = _baseSize();
    // clamped here rather than trusted from whatever last set _scale/_offset,
    // so painting can never show past the photo's edge regardless of which
    // gesture or slider tick got the state here
    final scale = _scale.clamp(_minScale, _maxScale);
    final offset = _constrain(_offset, scale);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(strings.editorCropTitle),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ClipRRect(
                  borderRadius: AppSpacing.borderRadiusMd,
                  child: GestureDetector(
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    child: SizedBox(
                      width: _viewportSide,
                      height: _viewportSide,
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.hardEdge,
                        children: [
                          // only the photo lives inside the boundary, because
                          // this is the thing that gets rasterized on apply —
                          // anything drawn in here is drawn into the saved
                          // file, which is how the framing grid used to end up
                          // baked across every uploaded picture
                          RepaintBoundary(
                            key: _boundaryKey,
                            child: SizedBox(
                              width: _viewportSide,
                              height: _viewportSide,
                              child: Stack(
                                alignment: Alignment.center,
                                clipBehavior: Clip.hardEdge,
                                children: [
                                  Container(color: Colors.black),
                                  // scale is applied at paint time rather than
                                  // by resizing the box: relayouting a Stack
                                  // child on every slider tick proved
                                  // unreliable, where a Transform always
                                  // repaints on the next frame
                                  Transform.translate(
                                    offset: offset,
                                    child: Transform.scale(
                                      scale: scale,
                                      // Stack hands its non-positioned children
                                      // loose constraints capped at its OWN
                                      // size (300x300), so a `base` wider than
                                      // that — any landscape photo — would
                                      // silently get clamped back down to 300
                                      // here, throwing off every pan/zoom bound
                                      // computed from the real `base`.
                                      // OverflowBox is what lets the photo
                                      // actually render at its true cover size
                                      // instead of that shrunk one.
                                      child: OverflowBox(
                                        minWidth: base.width,
                                        maxWidth: base.width,
                                        minHeight: base.height,
                                        maxHeight: base.height,
                                        child: Image(
                                          image: _provider,
                                          fit: BoxFit.fill,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // a framing aid for the person cropping, and nothing
                          // more: outside the boundary, so it is never part of
                          // what gets saved
                          IgnorePointer(
                            child: CustomPaint(
                              size: const Size(_viewportSide, _viewportSide),
                              painter: _GridPainter(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: AppSpacing.screenPadding,
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.zoom_out,
                        color: Colors.white54,
                        size: 18,
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: AppColors.primary,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: AppColors.primary,
                            overlayColor: AppColors.primary.withValues(
                              alpha: 0.2,
                            ),
                          ),
                          child: Slider(
                            value: scale,
                            min: _minScale,
                            max: _maxScale,
                            onChanged: (value) => setState(() {
                              _scale = value;
                              _offset = _constrain(_offset, value);
                            }),
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.zoom_in,
                        color: Colors.white54,
                        size: 18,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                        ),
                      ),
                      onPressed: _saving ? null : () => unawaited(_apply()),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(strings.editorCropApply),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final dx = size.width * i / 3;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
      final dy = size.height * i / 3;
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), paint);
    }
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}
