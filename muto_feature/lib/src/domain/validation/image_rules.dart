import 'dart:typed_data';

import '../repositories/image_repository.dart';

enum ImageIssue { unsupportedType, tooLarge, tooSmall, tooManyPixels }

/// What the client checks before an image is allowed to leave the device.
///
/// These are a courtesy to the student and a first line of defence, never a
/// control: whatever accepts the upload has to make the same decisions again
/// and re-encode the result.
abstract final class ImageRules {
  static const int maxBytes = 5 * 1024 * 1024;
  static const int minDimension = 200;
  static const int maxPixels = 50000000;
  static const int uploadLongestEdge = 1600;

  static const Set<String> allowedMimeTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  /// Format is decided by the leading bytes, never by a file name, because a
  /// name is chosen by whoever supplied the file.
  static String? detectMimeType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return null;
  }

  static ImageIssue? check(StagedImage image) {
    final detected = detectMimeType(image.bytes);
    if (detected == null || !allowedMimeTypes.contains(detected)) {
      return ImageIssue.unsupportedType;
    }
    if (image.byteLength > maxBytes) return ImageIssue.tooLarge;
    if (image.width < minDimension || image.height < minDimension) {
      return ImageIssue.tooSmall;
    }
    if (image.width * image.height > maxPixels) return ImageIssue.tooManyPixels;
    return null;
  }
}
