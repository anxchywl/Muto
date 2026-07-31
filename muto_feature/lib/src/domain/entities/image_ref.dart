/// A reference to a stored listing image.
///
/// The feature never builds an image URL itself — an `ImageSource` resolves a
/// reference, which is what keeps image hosting swappable. [version] changes
/// whenever the underlying image is replaced, so a cached copy is never served
/// for new content.
final class ImageRef {
  const ImageRef({required this.id, required this.version});

  final String id;
  final String version;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImageRef && other.id == id && other.version == version;

  @override
  int get hashCode => Object.hash(id, version);

  @override
  String toString() => 'ImageRef($id@$version)';
}
