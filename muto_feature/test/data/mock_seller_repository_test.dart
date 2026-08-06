import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/src/data/mock/mock_environment.dart';
import 'package:muto_feature/src/data/mock/mock_listing_repository.dart';
import 'package:muto_feature/src/data/mock/mock_seller_repository.dart';
import 'package:muto_feature/src/data/mock/sample_data.dart';
import 'package:muto_feature/src/domain/entities/identity.dart';
import 'package:muto_feature/src/domain/entities/listing_status.dart';
import 'package:muto_feature/src/domain/entities/page.dart';
import 'package:muto_feature/src/domain/failures.dart';

const Identity _madina = Identity(
  userId: 'usr_004',
  displayName: 'Madina',
  isVerified: true,
);

void main() {
  late SampleData data;
  late MockListingRepository listings;
  late MockSellerRepository sellers;

  setUpAll(() {
    data = SampleData.decode(
      File('assets/sample/listings.json').readAsStringSync(),
    );
  });

  MockSellerRepository build({Identity? viewer, MockFaults? faults}) {
    listings = MockListingRepository(
      seed: data.listings,
      viewer: () => viewer ?? data.viewer,
      latency: const MockLatency.none(),
      faults: faults,
    );
    return MockSellerRepository(
      source: () => listings.all,
      latency: const MockLatency.none(),
      faults: faults,
    );
  }

  setUp(() => sellers = build());

  test('a profile counts only what is still in circulation', () async {
    final profile = await sellers.profile('usr_002');

    expect(profile.displayName, 'Aizhan');
    expect(profile.activeListingCount, greaterThan(0));
    expect(profile.isVerified, isTrue);
  });

  test('a seller nobody has ever listed under does not exist', () {
    expect(
      () => sellers.profile('usr_nobody'),
      throwsA(isA<NotFoundFailure>()),
    );
  });

  test(
    'their page shows what another student may see and nothing else',
    () async {
      final page = await sellers.listings('usr_004');

      expect(page.items, isNotEmpty);
      for (final listing in page.items) {
        expect(listing.sellerId, 'usr_004');
        expect(listing.status.isVisibleInBrowse, isTrue);
        // a list-shaped response never carries contact details, however the seed
        // was written
        expect(listing.contact, isNull);
      }
    },
  );

  test('a listing leaves the page the moment its owner sells it', () async {
    sellers = build(viewer: _madina);
    final before = await sellers.listings(_madina.userId);
    final target = before.items.first;

    await listings.changeStatus(
      target.id,
      ListingStatus.sold,
      expected: target.version,
    );

    final after = await sellers.listings(_madina.userId);
    expect(
      after.items.map((listing) => listing.id),
      isNot(contains(target.id)),
    );
  });

  test('the page stops handing out a cursor once it is exhausted', () async {
    Cursor? cursor;
    var pages = 0;

    do {
      final page = await sellers.listings('usr_002', cursor: cursor);
      cursor = page.nextCursor;
      pages++;
    } while (cursor != null && pages < 10);

    expect(cursor, isNull);
  });

  test('a profile fails as a network failure while offline', () {
    final offline = build(faults: MockFaults()..offline = true);

    expect(() => offline.profile('usr_002'), throwsA(isA<NetworkFailure>()));
  });
}
