/// Physical condition of the item, chosen by the seller.
enum ListingCondition {
  brandNew('new'),
  likeNew('like_new'),
  good('good'),
  worn('worn');

  const ListingCondition(this.wireValue);

  final String wireValue;

  static ListingCondition? fromWire(String? value) {
    for (final condition in ListingCondition.values) {
      if (condition.wireValue == value) return condition;
    }
    return null;
  }
}
