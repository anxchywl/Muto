import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/src/application/cache/cache_keys.dart';
import 'package:muto_feature/src/application/cache/generation.dart';
import 'package:muto_feature/src/application/cache/listing_cache.dart';
import 'package:muto_feature/src/domain/entities/currency.dart';
import 'package:muto_feature/src/domain/entities/listing.dart';
import 'package:muto_feature/src/domain/entities/listing_category.dart';
import 'package:muto_feature/src/domain/entities/listing_condition.dart';
import 'package:muto_feature/src/domain/entities/listing_kind.dart';
import 'package:muto_feature/src/domain/entities/listing_status.dart';
import 'package:muto_feature/src/domain/entities/money.dart';
import 'package:muto_feature/src/domain/entities/page.dart';
import 'package:muto_feature/src/domain/repositories/listing_repository.dart';

Listing _listing(
  String id, {
  ListingStatus status = ListingStatus.active,
  int version = 1,
}) {
  final now = DateTime(2026, 7, 20);
  return Listing(
    id: id,
    version: Version(version),
    kind: ListingKind.sale,
    status: status,
    title: 'Listing $id',
    description: '',
    condition: ListingCondition.good,
    category: ListingCategory.dorm,
    images: const [],
    sellerId: 'usr_002',
    sellerDisplayName: 'Aizhan',
    createdAt: now,
    updatedAt: now,
    price: const Money(minorUnits: 1000, currency: Currency.kzt),
  );
}

const String _browseKey = 'browse:default';

void main() {
  group('ListingCache feeds', () {
    test('an unloaded feed is unknown, not empty', () {
      final cache = ListingCache();
      expect(cache.peekFeed(_browseKey), isNull);

      cache.absorbPage(
        _browseKey,
        const Page<Listing>(items: []),
        replace: true,
      );
      expect(cache.peekFeed(_browseKey), isEmpty);
    });

    test('appends a page without repeating an id', () {
      final cache = ListingCache()
        ..absorbPage(
          _browseKey,
          Page<Listing>(
            items: [_listing('a'), _listing('b')],
            nextCursor: const Cursor('offset:2'),
          ),
          replace: true,
        )
        ..absorbPage(
          _browseKey,
          Page<Listing>(items: [_listing('b'), _listing('c')]),
          replace: false,
        );

      expect(cache.peekFeed(_browseKey)!.map((listing) => listing.id), [
        'a',
        'b',
        'c',
      ]);
      expect(cache.hasMore(_browseKey), isFalse);
    });

    test('replacing a feed starts it again', () {
      final cache = ListingCache()
        ..absorbPage(
          _browseKey,
          Page<Listing>(items: [_listing('a'), _listing('b')]),
          replace: true,
        )
        ..absorbPage(
          _browseKey,
          Page<Listing>(items: [_listing('z')]),
          replace: true,
        );

      expect(cache.peekFeed(_browseKey)!.map((listing) => listing.id), ['z']);
    });

    test('carries the cursor for the next page', () {
      final cache = ListingCache()
        ..absorbPage(
          _browseKey,
          Page<Listing>(
            items: [_listing('a')],
            nextCursor: const Cursor('offset:1'),
          ),
          replace: true,
        );

      expect(cache.hasMore(_browseKey), isTrue);
      expect(cache.nextCursor(_browseKey), const Cursor('offset:1'));
    });
  });

  group('ListingCache freshness', () {
    test('a just-loaded feed is fresh and not stale', () {
      final cache = ListingCache()
        ..absorbPage(
          _browseKey,
          Page<Listing>(items: [_listing('a')]),
          replace: true,
        );

      expect(cache.isFresh(_browseKey), isTrue);
      expect(cache.isStale(_browseKey), isFalse);
    });

    test('marking stale forces the next load to reach the source', () {
      final cache = ListingCache()
        ..absorbPage(
          _browseKey,
          Page<Listing>(items: [_listing('a')]),
          replace: true,
        )
        ..markStale(_browseKey);

      expect(cache.isFresh(_browseKey), isFalse);
      expect(cache.isStale(_browseKey), isTrue);
      expect(
        cache.peekFeed(_browseKey),
        isNotNull,
        reason: 'stale data still renders while a refresh runs',
      );
    });

    test('an unknown feed is neither fresh nor stale', () {
      final cache = ListingCache();
      expect(cache.isFresh('nothing'), isFalse);
      expect(cache.isStale('nothing'), isFalse);
    });
  });

  group('ListingCache patching', () {
    test('one listing is shared by every feed that shows it', () {
      final cache = ListingCache()
        ..absorbPage(
          _browseKey,
          Page<Listing>(items: [_listing('a')]),
          replace: true,
        )
        ..absorbPage(
          'mine:',
          Page<Listing>(items: [_listing('a')]),
          replace: true,
        )
        ..patch(_listing('a', status: ListingStatus.reserved, version: 2));

      expect(cache.peek('a')!.status, ListingStatus.reserved);
      expect(cache.peekFeed('mine:')!.single.status, ListingStatus.reserved);
    });

    test('a sold listing leaves browse but stays in the owner feed', () {
      final cache = ListingCache()
        ..absorbPage(
          _browseKey,
          Page<Listing>(items: [_listing('a')]),
          replace: true,
        )
        ..absorbPage(
          'mine:',
          Page<Listing>(items: [_listing('a')]),
          replace: true,
        )
        ..patch(_listing('a', status: ListingStatus.sold, version: 2));

      expect(cache.peekFeed(_browseKey), isEmpty);
      expect(cache.peekFeed('mine:')!.single.id, 'a');
    });

    test('a removed listing leaves every feed', () {
      final cache = ListingCache()
        ..absorbPage(
          _browseKey,
          Page<Listing>(items: [_listing('a')]),
          replace: true,
        )
        ..absorbPage(
          'mine:',
          Page<Listing>(items: [_listing('a')]),
          replace: true,
        )
        ..patch(_listing('a', status: ListingStatus.removed, version: 2));

      expect(cache.peekFeed(_browseKey), isEmpty);
      expect(cache.peekFeed('mine:'), isEmpty);
    });

    test('a patch marks feeds stale so the next read reconciles', () {
      final cache = ListingCache()
        ..absorbPage(
          _browseKey,
          Page<Listing>(items: [_listing('a')]),
          replace: true,
        );
      expect(cache.isFresh(_browseKey), isTrue);

      cache.patch(_listing('a', status: ListingStatus.reserved, version: 2));
      expect(cache.isFresh(_browseKey), isFalse);
    });

    test('notifies listeners when data changes', () {
      var notifications = 0;
      final cache = ListingCache()..addListener(() => notifications++);

      cache
        ..absorbPage(
          _browseKey,
          Page<Listing>(items: [_listing('a')]),
          replace: true,
        )
        ..patch(_listing('a', version: 2))
        ..forget('a');

      expect(notifications, 3);
    });

    test('clearing drops every listing and feed', () {
      final cache = ListingCache()
        ..absorbPage(
          _browseKey,
          Page<Listing>(items: [_listing('a'), _listing('b')]),
          replace: true,
        )
        ..clear();

      expect(cache.listingCount, 0);
      expect(cache.peekFeed(_browseKey), isNull);
    });
  });

  group('CacheGeneration', () {
    test('a captured generation stops being current after a bump', () {
      final generation = CacheGeneration();
      final captured = generation.value;

      expect(generation.isCurrent(captured), isTrue);
      generation.bump();
      expect(
        generation.isCurrent(captured),
        isFalse,
        reason: 'a response from the previous account must be discarded',
      );
    });
  });

  group('CacheKeys', () {
    test('separates one account from another', () {
      expect(CacheKeys.draft('usr_001'), isNot(CacheKeys.draft('usr_002')));
      expect(
        CacheKeys.belongsTo(CacheKeys.draft('usr_001'), 'usr_001'),
        isTrue,
      );
      expect(
        CacheKeys.belongsTo(CacheKeys.draft('usr_001'), 'usr_002'),
        isFalse,
      );
    });

    test('recognises only the keys this feature owns', () {
      expect(CacheKeys.isOwned(CacheKeys.draft('usr_001')), isTrue);
      expect(CacheKeys.isOwned('host_session_token'), isFalse);
    });

    test('carries the schema version so an old layout is discarded', () {
      expect(CacheKeys.draft('usr_001'), startsWith('muto_v1_'));
    });

    test('two identical queries share a key', () {
      const a = ListingQuery(text: ' Lamp ', category: ListingCategory.dorm);
      const b = ListingQuery(text: 'lamp', category: ListingCategory.dorm);
      expect(CacheKeys.browse(a), CacheKeys.browse(b));
    });

    test('two different queries do not collide', () {
      const a = ListingQuery(category: ListingCategory.dorm);
      const b = ListingQuery(category: ListingCategory.textbooks);
      const c = ListingQuery(
        category: ListingCategory.dorm,
        sort: ListingSort.priceAscending,
      );

      expect(CacheKeys.browse(a), isNot(CacheKeys.browse(b)));
      expect(CacheKeys.browse(a), isNot(CacheKeys.browse(c)));
    });

    test('a status narrows the owner feed key', () {
      expect(CacheKeys.mine(ListingStatus.sold), isNot(CacheKeys.mine(null)));
    });
  });
}
