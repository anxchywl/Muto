import '../entities/listing.dart';
import '../entities/page.dart';

/// Saved listings, scoped to the signed-in student.
abstract interface class FavoritesRepository {
  Future<Page<Listing>> page({Cursor? cursor});

  /// The ids the current account has saved, used to render the toggle state
  /// without loading every favorite listing.
  Future<Set<String>> savedIds();

  Future<void> add(String listingId);

  Future<void> remove(String listingId);
}
