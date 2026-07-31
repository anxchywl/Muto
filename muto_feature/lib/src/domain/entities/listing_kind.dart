/// What the seller wants in return for the item.
///
/// The kind decides whether a price is meaningful: only [sale] carries one.
enum ListingKind {
  sale('sale'),
  exchange('exchange'),
  giveaway('giveaway');

  const ListingKind(this.wireValue);

  final String wireValue;

  bool get requiresPrice => this == ListingKind.sale;

  bool get allowsWantedItems => this == ListingKind.exchange;

  static ListingKind? fromWire(String? value) {
    for (final kind in ListingKind.values) {
      if (kind.wireValue == value) return kind;
    }
    return null;
  }
}
