import 'dart:typed_data';

import '../entities/image_ref.dart';

/// Where the bytes for an image reference actually live.
///
/// Keeping this a closed set means presentation can render an image without
/// knowing whether it came from the bundle or a server, and swapping image
/// hosting later touches one implementation rather than every widget.
sealed class ImageLocation {
  const ImageLocation();
}

final class BundledImageLocation extends ImageLocation {
  const BundledImageLocation(this.assetPath);

  final String assetPath;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BundledImageLocation && other.assetPath == assetPath;

  @override
  int get hashCode => assetPath.hashCode;
}

final class RemoteImageLocation extends ImageLocation {
  const RemoteImageLocation(this.uri, {this.headers = const {}});

  final Uri uri;
  final Map<String, String> headers;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoteImageLocation &&
          other.uri == uri &&
          _mapsEqual(other.headers, headers);

  @override
  int get hashCode =>
      Object.hash(uri, Object.hashAllUnordered(headers.entries));

  static bool _mapsEqual(Map<String, String> left, Map<String, String> right) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) return false;
    }
    return true;
  }
}

/// An image that has been staged but not yet redeemed, so it exists only in
/// this session's memory.
final class MemoryImageLocation extends ImageLocation {
  const MemoryImageLocation(this.bytes);

  final Uint8List bytes;
}

abstract interface class ImageLocator {
  /// Returns null when the reference resolves to nothing, so the caller can
  /// render its failure state instead of guessing.
  ImageLocation? locate(ImageRef ref);
}
