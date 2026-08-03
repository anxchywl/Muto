import 'dart:ui' as ui;

import 'package:image_picker/image_picker.dart';

import '../../domain/repositories/image_repository.dart';
import '../../domain/validation/image_rules.dart';

/// Picks one photo and measures it.
///
/// The picker is asked to downscale before the bytes ever reach us, which
/// keeps a phone camera's full-resolution file from being carried around only
/// to be rejected for its size.
Future<StagedImage?> pickListingImage(ImagePicker picker) async {
  final file = await picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: ImageRules.uploadLongestEdge.toDouble(),
    maxHeight: ImageRules.uploadLongestEdge.toDouble(),
  );
  if (file == null) return null;

  final bytes = await file.readAsBytes();
  final descriptor = await ui.ImageDescriptor.encoded(
    await ui.ImmutableBuffer.fromUint8List(bytes),
  );

  try {
    return StagedImage(
      bytes: bytes,
      // the declared type is recorded but never trusted; the rules read the
      // leading bytes instead
      mimeType: file.mimeType ?? 'application/octet-stream',
      width: descriptor.width,
      height: descriptor.height,
    );
  } finally {
    descriptor.dispose();
  }
}
