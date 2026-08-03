import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

import '../../domain/entities/image_ref.dart';
import '../../domain/repositories/image_locator.dart';

/// Turns a located image into something Flutter can draw.
///
/// This is the only place image caching is configured, so changing how images
/// are stored later is one file rather than every widget that shows one.
ImageProvider? resolveListingImage(ImageLocator locator, ImageRef? ref) {
  if (ref == null) return null;
  final location = locator.locate(ref);
  return switch (location) {
    BundledImageLocation(:final assetPath) => AssetImage(assetPath),
    RemoteImageLocation(:final uri) => CachedNetworkImageProvider(
      uri.toString(),
    ),
    MemoryImageLocation(:final bytes) => MemoryImage(bytes),
    null => null,
  };
}
