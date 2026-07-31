/// The fixed set of campus categories a listing can belong to.
///
/// This is an enum rather than server-supplied data because the set is small,
/// stable, and has to be translated into three languages — a slug maps to a
/// localized name, so no display text ever travels over the wire.
enum ListingCategory {
  textbooks('textbooks'),
  electronics('electronics'),
  furniture('furniture'),
  clothing('clothing'),
  sports('sports'),
  dorm('dorm'),
  tickets('tickets'),
  other('other');

  const ListingCategory(this.slug);

  final String slug;

  static ListingCategory? fromSlug(String? slug) {
    for (final category in ListingCategory.values) {
      if (category.slug == slug) return category;
    }
    return null;
  }
}
