import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/src/data/mock/sample_data.dart';
import 'package:muto_feature/src/domain/entities/currency.dart';
import 'package:muto_feature/src/domain/entities/listing_kind.dart';
import 'package:muto_feature/src/domain/entities/listing_status.dart';

// reads the file that actually ships, so a broken sample fails the suite
SampleData _shipped() =>
    SampleData.decode(File('assets/sample/listings.json').readAsStringSync());

void main() {
  group('shipped sample data', () {
    test('decodes and names a verified viewer', () {
      final data = _shipped();
      expect(data.viewer.userId, isNotEmpty);
      expect(data.viewer.isVerified, isTrue);
    });

    test('drops the entry this build cannot read', () {
      final data = _shipped();
      expect(
        data.listings.map((listing) => listing.id),
        isNot(contains('lst_unusable')),
        reason: 'an unknown category must skip one listing, not the feed',
      );
      expect(data.listings, isNotEmpty);
    });

    test('covers every listing kind', () {
      final kinds = _shipped().listings.map((listing) => listing.kind).toSet();
      expect(kinds, containsAll(ListingKind.values));
    });

    test('covers both currencies', () {
      final currencies = _shipped().listings
          .map((listing) => listing.price?.currency)
          .nonNulls
          .toSet();
      expect(currencies, containsAll(Currency.values));
    });

    test('covers the statuses the screens have to handle', () {
      final statuses = _shipped().listings
          .map((listing) => listing.status)
          .toSet();
      expect(
        statuses,
        containsAll(const [
          ListingStatus.active,
          ListingStatus.reserved,
          ListingStatus.sold,
          ListingStatus.hidden,
          ListingStatus.removed,
        ]),
      );
    });

    test('includes a listing whose image cannot resolve', () {
      final broken = _shipped().listings.where(
        (listing) =>
            listing.images.any((image) => image.id == 'sample-missing'),
      );
      expect(broken, isNotEmpty, reason: 'the failure state needs a subject');
    });

    test('includes a listing with no images at all', () {
      expect(
        _shipped().listings.where((listing) => listing.images.isEmpty),
        isNotEmpty,
      );
    });

    test('every price obeys its currency bounds', () {
      for (final listing in _shipped().listings) {
        final price = listing.price;
        if (price == null) continue;
        expect(price.isWithinBounds, isTrue, reason: listing.id);
      }
    });

    test('only a sale carries a price', () {
      for (final listing in _shipped().listings) {
        expect(
          listing.price != null,
          listing.kind == ListingKind.sale,
          reason: listing.id,
        );
      }
    });

    test('contact details use reserved example values only', () {
      for (final listing in _shipped().listings) {
        final email = listing.contact?.email;
        if (email == null) continue;
        expect(
          email.endsWith('@example.edu'),
          isTrue,
          reason: 'sample contacts must not be able to reach anyone',
        );
      }
    });
  });

  group('tolerant decoding', () {
    test('skips a listing missing a required field', () {
      const source = '''
      {
        "viewer": {"user_id": "u1", "display_name": "A", "is_verified": true},
        "listings": [
          {"id": "keep", "version": 1, "kind": "giveaway", "status": "active",
           "title": "Kept", "condition": "good", "category": "dorm",
           "images": [], "seller_id": "u2", "seller_display_name": "B",
           "created_at": "2026-07-01T00:00:00Z",
           "updated_at": "2026-07-01T00:00:00Z"},
          {"id": "drop", "version": 1, "kind": "giveaway", "status": "active",
           "condition": "good", "category": "dorm", "images": [],
           "seller_id": "u2", "seller_display_name": "B",
           "created_at": "2026-07-01T00:00:00Z",
           "updated_at": "2026-07-01T00:00:00Z"}
        ]
      }
      ''';
      final data = SampleData.decode(source);
      expect(data.listings.map((listing) => listing.id), ['keep']);
    });

    test('an absent description becomes empty rather than failing', () {
      const source = '''
      {
        "viewer": {"user_id": "u1", "display_name": "A", "is_verified": true},
        "listings": [
          {"id": "keep", "version": 1, "kind": "giveaway", "status": "active",
           "title": "Kept", "condition": "good", "category": "dorm",
           "images": [], "seller_id": "u2", "seller_display_name": "B",
           "created_at": "2026-07-01T00:00:00Z",
           "updated_at": "2026-07-01T00:00:00Z"}
        ]
      }
      ''';
      expect(SampleData.decode(source).listings.single.description, isEmpty);
    });

    test('an unrecognised status decodes to unknown, not a crash', () {
      const source = '''
      {
        "viewer": {"user_id": "u1", "display_name": "A", "is_verified": true},
        "listings": [
          {"id": "keep", "version": 1, "kind": "giveaway", "status": "archived",
           "title": "Kept", "condition": "good", "category": "dorm",
           "images": [], "seller_id": "u2", "seller_display_name": "B",
           "created_at": "2026-07-01T00:00:00Z",
           "updated_at": "2026-07-01T00:00:00Z"}
        ]
      }
      ''';
      expect(
        SampleData.decode(source).listings.single.status,
        ListingStatus.unknown,
      );
    });

    test('a malformed image entry is skipped without losing the listing', () {
      const source = '''
      {
        "viewer": {"user_id": "u1", "display_name": "A", "is_verified": true},
        "listings": [
          {"id": "keep", "version": 1, "kind": "giveaway", "status": "active",
           "title": "Kept", "condition": "good", "category": "dorm",
           "images": [{"id": "ok", "version": "v1"}, {"id": 7}, "nonsense"],
           "seller_id": "u2", "seller_display_name": "B",
           "created_at": "2026-07-01T00:00:00Z",
           "updated_at": "2026-07-01T00:00:00Z"}
        ]
      }
      ''';
      final listing = SampleData.decode(source).listings.single;
      expect(listing.images.map((image) => image.id), ['ok']);
    });
  });
}
