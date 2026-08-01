import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/src/data/mock/mock_environment.dart';
import 'package:muto_feature/src/data/mock/mock_listing_repository.dart';
import 'package:muto_feature/src/data/mock/sample_data.dart';
import 'package:muto_feature/src/domain/entities/client_request_id.dart';
import 'package:muto_feature/src/domain/entities/currency.dart';
import 'package:muto_feature/src/domain/entities/identity.dart';
import 'package:muto_feature/src/domain/entities/listing.dart';
import 'package:muto_feature/src/domain/entities/listing_category.dart';
import 'package:muto_feature/src/domain/entities/listing_condition.dart';
import 'package:muto_feature/src/domain/entities/listing_kind.dart';
import 'package:muto_feature/src/domain/entities/listing_status.dart';
import 'package:muto_feature/src/domain/entities/money.dart';
import 'package:muto_feature/src/domain/entities/page.dart';
import 'package:muto_feature/src/domain/failures.dart';
import 'package:muto_feature/src/domain/repositories/listing_repository.dart';

late SampleData _data;

MockListingRepository _repository({Identity? viewer, MockFaults? faults}) {
  final identity = viewer ?? _data.viewer;
  return MockListingRepository(
    seed: _data.listings,
    viewer: () => identity,
    latency: const MockLatency.none(),
    faults: faults,
  );
}

ListingDraft _draft({
  ListingKind kind = ListingKind.sale,
  String title = 'Desk lamp',
  Money? price = const Money(minorUnits: 3000, currency: Currency.kzt),
}) {
  return ListingDraft(
    kind: kind,
    title: title,
    description: 'Works fine',
    condition: ListingCondition.good,
    category: ListingCategory.dorm,
    images: const [],
    price: price,
  );
}

void main() {
  setUpAll(() {
    _data = SampleData.decode(
      File('assets/sample/listings.json').readAsStringSync(),
    );
  });

  group('browse', () {
    test('shows only listings that belong in the feed', () async {
      final page = await _repository().browse(query: const ListingQuery());
      for (final listing in page.items) {
        expect(listing.status.isVisibleInBrowse, isTrue, reason: listing.id);
      }
    });

    test('never exposes seller contact in a list', () async {
      final page = await _repository().browse(query: const ListingQuery());
      for (final listing in page.items) {
        expect(listing.contact, isNull, reason: listing.id);
      }
    });

    test('walks pages with the cursor it was handed', () async {
      final repository = _repository();
      final seen = <String>[];
      Cursor? cursor;
      var guard = 0;

      do {
        final page = await repository.browse(
          query: const ListingQuery(),
          cursor: cursor,
        );
        seen.addAll(page.items.map((listing) => listing.id));
        cursor = page.nextCursor;
      } while (cursor != null && ++guard < 20);

      expect(seen.toSet().length, seen.length, reason: 'no id repeats');
      expect(guard, lessThan(20), reason: 'pagination terminates');
    });

    test('filters by category', () async {
      final page = await _repository().browse(
        query: const ListingQuery(category: ListingCategory.textbooks),
      );
      expect(page.items, isNotEmpty);
      for (final listing in page.items) {
        expect(listing.category, ListingCategory.textbooks);
      }
    });

    test('filters by kind', () async {
      final page = await _repository().browse(
        query: const ListingQuery(kind: ListingKind.giveaway),
      );
      expect(page.items, isNotEmpty);
      for (final listing in page.items) {
        expect(listing.kind, ListingKind.giveaway);
      }
    });

    test('matches free text against title and description', () async {
      final page = await _repository().browse(
        query: const ListingQuery(text: 'calculus'),
      );
      expect(page.items.map((listing) => listing.id), contains('lst_001'));
    });

    test('a price range applies inside one currency only', () async {
      final page = await _repository().browse(
        query: const ListingQuery(
          currency: Currency.kzt,
          minMinorUnits: 5000,
          maxMinorUnits: 10000,
        ),
      );
      expect(page.items, isNotEmpty);
      for (final listing in page.items) {
        expect(listing.price!.currency, Currency.kzt);
        expect(listing.price!.minorUnits, inInclusiveRange(5000, 10000));
      }
    });

    test('sorts by price without mixing currencies', () async {
      final page = await _repository().browse(
        query: const ListingQuery(
          currency: Currency.kzt,
          sort: ListingSort.priceAscending,
        ),
      );
      final amounts = page.items
          .map((listing) => listing.price!.minorUnits)
          .toList();
      expect(amounts, orderedEquals(List.of(amounts)..sort()));
    });
  });

  group('byId', () {
    test('gives contact details to a verified viewer', () async {
      final listing = await _repository().byId('lst_001');
      expect(listing.contact, isNotNull);
    });

    test('withholds contact details from an unverified viewer', () async {
      final repository = _repository(
        viewer: const Identity(
          userId: 'usr_001',
          displayName: 'Aruzhan',
          isVerified: false,
        ),
      );
      final listing = await repository.byId('lst_001');
      expect(listing.contact, isNull);
    });

    test('a removed listing is gone, not merely missing', () async {
      expect(() => _repository().byId('lst_016'), throwsA(isA<GoneFailure>()));
    });

    test('an unknown id is not found', () async {
      expect(
        () => _repository().byId('lst_nope'),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test('a hidden listing is invisible to everyone but its owner', () async {
      final stranger = _repository(
        viewer: const Identity(
          userId: 'usr_999',
          displayName: 'Someone',
          isVerified: true,
        ),
      );
      expect(() => stranger.byId('lst_014'), throwsA(isA<NotFoundFailure>()));

      final owner = await _repository().byId('lst_014');
      expect(owner.status, ListingStatus.hidden);
    });
  });

  group('mine', () {
    test(
      'returns only the viewer\'s listings and hides removed ones',
      () async {
        final page = await _repository().mine();
        expect(page.items, isNotEmpty);
        for (final listing in page.items) {
          expect(listing.sellerId, _data.viewer.userId);
          expect(listing.status, isNot(ListingStatus.removed));
        }
      },
    );

    test('can be narrowed to one status', () async {
      final page = await _repository().mine(status: ListingStatus.sold);
      expect(page.items, isNotEmpty);
      for (final listing in page.items) {
        expect(listing.status, ListingStatus.sold);
      }
    });
  });

  group('create', () {
    test('publishes an active listing owned by the viewer', () async {
      final created = await _repository().create(
        _draft(),
        requestId: const ClientRequestId('req-1'),
      );
      expect(created.status, ListingStatus.active);
      expect(created.sellerId, _data.viewer.userId);
      expect(created.version, const Version(1));
    });

    test('a retry with the same token returns the same listing', () async {
      final repository = _repository();
      const token = ClientRequestId('req-retry');
      final first = await repository.create(_draft(), requestId: token);
      final second = await repository.create(_draft(), requestId: token);
      expect(second.id, first.id);
    });

    test('the same token with a changed draft is a conflict', () async {
      final repository = _repository();
      const token = ClientRequestId('req-changed');
      await repository.create(_draft(), requestId: token);
      expect(
        () => repository.create(
          _draft(title: 'Different lamp'),
          requestId: token,
        ),
        throwsA(isA<ConflictFailure>()),
      );
    });

    test('normalises away a price the kind does not allow', () async {
      final created = await _repository().create(
        _draft(kind: ListingKind.giveaway),
        requestId: const ClientRequestId('req-free'),
      );
      expect(created.price, isNull);
    });
  });

  group('mutation authority', () {
    test('refuses to change a listing the viewer does not own', () async {
      expect(
        () => _repository().changeStatus(
          'lst_001',
          ListingStatus.sold,
          expected: const Version(1),
        ),
        throwsA(isA<ForbiddenFailure>()),
      );
    });

    test('refuses a stale version', () async {
      expect(
        () => _repository().changeStatus(
          'lst_011',
          ListingStatus.sold,
          expected: const Version(99),
        ),
        throwsA(isA<ConflictFailure>()),
      );
    });

    test('reports the current version alongside a conflict', () async {
      try {
        await _repository().changeStatus(
          'lst_011',
          ListingStatus.sold,
          expected: const Version(99),
        );
        fail('expected a conflict');
      } on ConflictFailure catch (failure) {
        expect(failure.current, const Version(1));
      }
    });

    test('refuses a transition the machine does not allow', () async {
      final repository = _repository();
      // lst_013 is sold; sold cannot go straight to reserved
      expect(
        () => repository.changeStatus(
          'lst_013',
          ListingStatus.reserved,
          expected: const Version(4),
        ),
        throwsA(isA<ConflictFailure>()),
      );
    });

    test('allows an owner transition and bumps the version', () async {
      final repository = _repository();
      final updated = await repository.changeStatus(
        'lst_011',
        ListingStatus.reserved,
        expected: const Version(1),
      );
      expect(updated.status, ListingStatus.reserved);
      expect(updated.version, const Version(2));
    });

    test('refuses to edit a sold listing', () async {
      expect(
        () => _repository().update(
          'lst_013',
          _draft(),
          expected: const Version(4),
        ),
        throwsA(isA<ConflictFailure>()),
      );
    });

    test('removal is a status change, not a disappearance', () async {
      final repository = _repository();
      await repository.remove('lst_011', expected: const Version(1));
      expect(() => repository.byId('lst_011'), throwsA(isA<GoneFailure>()));
    });
  });

  group('injected faults', () {
    test('offline fails every read', () async {
      final faults = MockFaults()..offline = true;
      expect(
        () => _repository(faults: faults).browse(query: const ListingQuery()),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('an expired session fails before anything else', () async {
      final faults = MockFaults()..sessionExpired = true;
      expect(
        () => _repository(faults: faults).byId('lst_001'),
        throwsA(isA<UnauthorizedFailure>()),
      );
    });

    test('a forced conflict applies once and then clears', () async {
      final faults = MockFaults()..conflictOnNextWrite = true;
      final repository = _repository(faults: faults);

      expect(
        () => repository.changeStatus(
          'lst_011',
          ListingStatus.reserved,
          expected: const Version(1),
        ),
        throwsA(isA<ConflictFailure>()),
      );

      await Future<void>.delayed(Duration.zero);
      final updated = await repository.changeStatus(
        'lst_011',
        ListingStatus.reserved,
        expected: const Version(1),
      );
      expect(updated.status, ListingStatus.reserved);
    });
  });
}
