import '../entities/listing.dart';
import '../entities/page.dart';
import '../entities/seller_profile.dart';

/// Reads about someone else's listings.
///
/// Separate from the listing repository because a profile is a different
/// resource with a different shape, and because neither call may ever carry
/// contact details — those belong to a detail read alone.
abstract interface class SellerRepository {
  Future<SellerProfile> profile(String sellerId);

  /// Only what another student may see: the seller's listings still in
  /// circulation, page by page.
  Future<Page<Listing>> listings(String sellerId, {Cursor? cursor});
}
