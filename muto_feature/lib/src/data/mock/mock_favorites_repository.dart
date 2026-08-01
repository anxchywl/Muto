import '../../domain/entities/listing.dart';
import '../../domain/entities/page.dart';
import '../../domain/repositories/favorites_repository.dart';
import '../../domain/repositories/listing_repository.dart';
import 'mock_environment.dart';

/// Favorites belong to one account and never outlive it, which is why this
/// holds its state in memory rather than persisting it.
final class MockFavoritesRepository implements FavoritesRepository {
  MockFavoritesRepository({
    required ListingRepository listings,
    Set<String>? initial,
    this.latency = const MockLatency(),
    MockFaults? faults,
  }) : _listings = listings,
       _saved = <String>{...?initial},
       faults = faults ?? MockFaults();

  final ListingRepository _listings;
  final Set<String> _saved;
  final MockLatency latency;
  final MockFaults faults;

  @override
  Future<Set<String>> savedIds() async {
    await Future<void>.delayed(latency.read);
    faults.checkReadable();
    return Set<String>.unmodifiable(_saved);
  }

  @override
  Future<Page<Listing>> page({Cursor? cursor}) async {
    await Future<void>.delayed(latency.read);
    faults.checkReadable();

    final resolved = <Listing>[];
    for (final id in _saved) {
      try {
        final listing = await _listings.byId(id);
        // a listing the seller took down stops appearing, it does not linger
        if (listing.status.isVisibleInBrowse) resolved.add(listing);
      } on Object {
        continue;
      }
    }
    resolved.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return Page<Listing>(items: resolved);
  }

  @override
  Future<void> add(String listingId) async {
    await Future<void>.delayed(latency.write);
    faults.checkWritable();
    _saved.add(listingId);
  }

  @override
  Future<void> remove(String listingId) async {
    await Future<void>.delayed(latency.write);
    faults.checkWritable();
    _saved.remove(listingId);
  }
}
