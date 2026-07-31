/// An opaque position in a paginated collection. The client never constructs
/// one — it only passes back what the previous page handed it.
final class Cursor {
  const Cursor(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Cursor && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Cursor($value)';
}

/// Optimistic concurrency token. Every mutation states the version it expects
/// so a stale write is rejected instead of overwriting someone else's edit.
final class Version {
  const Version(this.value);

  final int value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Version && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Version($value)';
}

/// One page of results plus the position to continue from.
final class Page<T> {
  const Page({required this.items, this.nextCursor});

  const Page.empty() : items = const [], nextCursor = null;

  final List<T> items;
  final Cursor? nextCursor;

  bool get hasMore => nextCursor != null;

  bool get isEmpty => items.isEmpty;
}
