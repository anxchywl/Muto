import '../../application/muto_scope.dart';
import '../local/preferences_draft_store.dart';
import 'mock_environment.dart';
import 'mock_favorites_repository.dart';
import 'mock_image_repository.dart';
import 'mock_listing_repository.dart';
import 'mock_session_repository.dart';
import 'sample_data.dart';

/// Image ids the bundle actually contains. A reference to anything else
/// resolves to nothing, which is how the sample set exercises the failure
/// state without shipping a corrupt file.
const Set<String> kBundledSampleImageIds = {
  'sample-01',
  'sample-02',
  'sample-03',
  'sample-04',
  'sample-05',
  'sample-06',
  'sample-07',
  'sample-08',
};

/// Assembles a working feature backed entirely by the bundled sample file.
///
/// Nothing here reaches the network and nothing needs a credential, which is
/// why development never carries a password that could be committed.
Future<MutoDependencies> createSampleDependencies({
  MockLatency latency = const MockLatency(),
  MockFaults? faults,
}) async {
  return buildSampleDependencies(
    await SampleData.load(),
    latency: latency,
    faults: faults,
  );
}

/// The synchronous half, so a test can supply its own seed instead of reading
/// the bundle.
MutoDependencies buildSampleDependencies(
  SampleData data, {
  MockLatency latency = const MockLatency(),
  MockFaults? faults,
}) {
  final shared = faults ?? MockFaults();
  final store = StagedImageStore();

  final listings = MockListingRepository(
    seed: data.listings,
    viewer: () => data.viewer,
    latency: latency,
    faults: shared,
  );

  return MutoDependencies(
    session: MockSessionRepository(
      identity: data.viewer,
      latency: latency,
      faults: shared,
    ),
    listings: listings,
    favorites: MockFavoritesRepository(
      listings: listings,
      latency: latency,
      faults: shared,
    ),
    images: MockImageRepository(store: store, latency: latency, faults: shared),
    imageLocator: MockImageLocator(
      store: store,
      bundled: kBundledSampleImageIds,
    ),
    drafts: const PreferencesDraftStore(),
  );
}
