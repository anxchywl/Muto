import '../../domain/entities/listing.dart';
import '../../domain/entities/page.dart';
import '../../domain/entities/seller_profile.dart';
import '../../domain/failures.dart';
import '../../domain/repositories/seller_repository.dart';
import 'mock_environment.dart';

/// An in-memory stand-in for the seller service.
///
/// It reads the same listings the listing repository holds, so a listing sold
/// a moment ago leaves the seller's page at the same time it leaves the feed.
final class MockSellerRepository implements SellerRepository {
  MockSellerRepository({
    required List<Listing> Function() source,
    this.latency = const MockLatency(),
    MockFaults? faults,
  }) : _source = source,
       faults = faults ?? MockFaults();

  static const int pageSize = 8;

  final List<Listing> Function() _source;
  final MockLatency latency;
  final MockFaults faults;

  @override
  Future<SellerProfile> profile(String sellerId) async {
    await Future<void>.delayed(latency.read);
    faults.checkReadable();

    final theirs = _source()
        .where((listing) => listing.sellerId == sellerId)
        .toList();
    // a seller with nothing left in circulation still exists, but one nobody
    // has ever heard of does not
    if (theirs.isEmpty) throw const NotFoundFailure();

    final visible = theirs
        .where((listing) => listing.status.isVisibleInBrowse)
        .length;
    final first = theirs
        .map((listing) => listing.createdAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);

    return SellerProfile(
      sellerId: sellerId,
      displayName: theirs.first.sellerDisplayName,
      // the sample set has no unverified seller, since an unverified account
      // cannot publish in the first place
      isVerified: true,
      activeListingCount: visible,
      firstListedAt: first,
    );
  }

  @override
  Future<Page<Listing>> listings(String sellerId, {Cursor? cursor}) async {
    await Future<void>.delayed(latency.read);
    faults.checkReadable();

    final matches =
        _source()
            .where((listing) => listing.sellerId == sellerId)
            .where((listing) => listing.status.isVisibleInBrowse)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final start = _offsetOf(cursor).clamp(0, matches.length);
    final end = (start + pageSize).clamp(0, matches.length);
    return Page<Listing>(
      items: [
        for (final listing in matches.sublist(start, end))
          _withoutContact(listing),
      ],
      nextCursor: end < matches.length ? Cursor('offset:$end') : null,
    );
  }

  /// Contact details belong to a detail read alone, so they never survive a
  /// list-shaped response even though the seed carries them.
  static Listing _withoutContact(Listing listing) {
    if (listing.contact == null) return listing;
    return Listing(
      id: listing.id,
      version: listing.version,
      kind: listing.kind,
      status: listing.status,
      title: listing.title,
      description: listing.description,
      condition: listing.condition,
      category: listing.category,
      images: listing.images,
      sellerId: listing.sellerId,
      sellerDisplayName: listing.sellerDisplayName,
      createdAt: listing.createdAt,
      updatedAt: listing.updatedAt,
      price: listing.price,
      wantedItems: listing.wantedItems,
    );
  }

  static int _offsetOf(Cursor? cursor) {
    if (cursor == null) return 0;
    final parts = cursor.value.split(':');
    if (parts.length != 2) return 0;
    return int.tryParse(parts[1]) ?? 0;
  }
}
