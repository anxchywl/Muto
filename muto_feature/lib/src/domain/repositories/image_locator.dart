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
  const RemoteImageLocation(this.uri);

  final Uri uri;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoteImageLocation && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
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
