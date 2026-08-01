/// Where a listing sits in its lifecycle.
///
/// [unknown] absorbs any value this build does not recognise so a newer server
/// vocabulary renders read-only instead of crashing the app.
enum ListingStatus {
  active('active'),
  reserved('reserved'),
  sold('sold'),
  hidden('hidden'),
  removed('removed'),
  unknown('unknown');

  const ListingStatus(this.wireValue);

  final String wireValue;

  static ListingStatus fromWire(String? value) {
    for (final status in ListingStatus.values) {
      if (status.wireValue == value) return status;
    }
    return ListingStatus.unknown;
  }

  /// The single source of allowed moves. Screens derive their actions from
  /// this map rather than hardcoding a button list.
  static const Map<ListingStatus, Set<ListingStatus>> _transitions = {
    ListingStatus.active: {
      ListingStatus.reserved,
      ListingStatus.sold,
      ListingStatus.hidden,
      ListingStatus.removed,
    },
    ListingStatus.reserved: {
      ListingStatus.active,
      ListingStatus.sold,
      ListingStatus.removed,
    },
    ListingStatus.sold: {ListingStatus.active, ListingStatus.removed},
    ListingStatus.hidden: {ListingStatus.active, ListingStatus.removed},
    ListingStatus.removed: <ListingStatus>{},
    ListingStatus.unknown: <ListingStatus>{},
  };

  Set<ListingStatus> get allowedNext =>
      _transitions[this] ?? const <ListingStatus>{};

  bool canTransitionTo(ListingStatus next) => allowedNext.contains(next);

  bool get isTerminal => allowedNext.isEmpty;

  /// Content may be edited only while the listing is still in circulation.
  bool get isEditable =>
      this == ListingStatus.active ||
      this == ListingStatus.reserved ||
      this == ListingStatus.hidden;

  /// What other students see in the feed.
  bool get isVisibleInBrowse =>
      this == ListingStatus.active || this == ListingStatus.reserved;

  /// What the seller sees in their own listings.
  bool get isVisibleToOwner => this != ListingStatus.removed;
}
