import 'dart:typed_data';

import '../entities/image_ref.dart';

/// An image the student picked, after the client has checked its shape.
final class StagedImage {
  const StagedImage({
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final String mimeType;
  final int width;
  final int height;

  int get byteLength => bytes.length;
}

/// Uploads happen in two steps: an image is staged and gets a reference, and
/// the reference is redeemed when the listing itself is saved. A reference
/// that is never redeemed expires rather than leaving an orphan.
abstract interface class ImageRepository {
  Future<ImageRef> stage(StagedImage image);
}
