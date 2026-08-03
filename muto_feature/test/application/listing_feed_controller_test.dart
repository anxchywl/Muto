import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/src/application/cache/generation.dart';
import 'package:muto_feature/src/application/cache/listing_cache.dart';
import 'package:muto_feature/src/application/listing_feed_controller.dart';
import 'package:muto_feature/src/domain/entities/currency.dart';
import 'package:muto_feature/src/domain/entities/listing.dart';
import 'package:muto_feature/src/domain/entities/listing_category.dart';
import 'package:muto_feature/src/domain/entities/listing_condition.dart';
import 'package:muto_feature/src/domain/entities/listing_kind.dart';
import 'package:muto_feature/src/domain/entities/listing_status.dart';
import 'package:muto_feature/src/domain/entities/money.dart';
import 'package:muto_feature/src/domain/entities/page.dart';
import 'package:muto_feature/src/domain/failures.dart';

Listing _listing(String id) {
  final now = DateTime(2026, 7, 20);
  return Listing(
    id: id,
    version: const Version(1),
    kind: ListingKind.sale,
    status: ListingStatus.active,
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

Page<Listing> _page(List<String> ids, {String? next}) => Page<Listing>(
  items: ids.map(_listing).toList(),
  nextCursor: next == null ? null : Cursor(next),
);

({
  ListingFeedController feed,
  ListingCache cache,
  CacheGeneration generation,
  int Function() unauthorizedCount,
})
_build() {
  final cache = ListingCache();
  final generation = CacheGeneration();
  var unauthorized = 0;
  final feed = ListingFeedController(
    cache: cache,
    generation: generation,
    onUnauthorized: () => unauthorized++,
  );
  return (
    feed: feed,
    cache: cache,
    generation: generation,
    unauthorizedCount: () => unauthorized,
  );
}

void main() {
  group('loading', () {
    test('loads the first page and exposes it', () async {
      final harness = _build();
      harness.feed.configure(
        key: 'browse:a',
        loader: (_) async => _page(['a', 'b']),
      );

      expect(harness.feed.hasLoaded, isFalse);
      await harness.feed.load();

      expect(harness.feed.items.map((listing) => listing.id), ['a', 'b']);
      expect(harness.feed.hasLoaded, isTrue);
      expect(harness.feed.isLoading, isFalse);
    });

    test('a fresh feed is reused instead of reloaded', () async {
      final harness = _build();
      var calls = 0;
      harness.feed.configure(
        key: 'browse:a',
        loader: (_) async {
          calls++;
          return _page(['a']);
        },
      );

      await harness.feed.load();
      await harness.feed.load();
      await harness.feed.load();

      expect(calls, 1, reason: 'screens may call load on every build');
    });

    test('refresh reaches the source even when the cache is fresh', () async {
      final harness = _build();
      var calls = 0;
      harness.feed.configure(
        key: 'browse:a',
        loader: (_) async {
          calls++;
          return _page(['a']);
        },
      );

      await harness.feed.load();
      await harness.feed.refresh();

      expect(calls, 2);
    });

    test('concurrent loads collapse into one request', () async {
      final harness = _build();
      final gate = Completer<Page<Listing>>();
      var calls = 0;
      harness.feed.configure(
        key: 'browse:a',
        loader: (_) {
          calls++;
          return gate.future;
        },
      );

      final first = harness.feed.load();
      final second = harness.feed.load();
      gate.complete(_page(['a']));
      await Future.wait([first, second]);

      expect(calls, 1);
    });
  });

  group('pagination', () {
    test('appends the next page', () async {
      final harness = _build();
      harness.feed.configure(
        key: 'browse:a',
        loader: (cursor) async =>
            cursor == null ? _page(['a', 'b'], next: 'offset:2') : _page(['c']),
      );

      await harness.feed.load();
      expect(harness.feed.hasMore, isTrue);

      await harness.feed.loadMore();
      expect(harness.feed.items.map((listing) => listing.id), ['a', 'b', 'c']);
      expect(harness.feed.hasMore, isFalse);
    });

    test('does nothing when there is no next page', () async {
      final harness = _build();
      var calls = 0;
      harness.feed.configure(
        key: 'browse:a',
        loader: (_) async {
          calls++;
          return _page(['a']);
        },
      );

      await harness.feed.load();
      await harness.feed.loadMore();

      expect(calls, 1);
    });

    test('stops when the source keeps handing back the same cursor', () async {
      final harness = _build();
      var calls = 0;
      harness.feed.configure(
        key: 'browse:a',
        loader: (_) async {
          calls++;
          return _page(['a'], next: 'stuck');
        },
      );

      await harness.feed.load();
      await harness.feed.loadMore();
      await harness.feed.loadMore();
      await harness.feed.loadMore();

      expect(
        calls,
        2,
        reason: 'a repeated cursor would otherwise page forever',
      );
    });

    test('a duplicated id across pages appears once', () async {
      final harness = _build();
      harness.feed.configure(
        key: 'browse:a',
        loader: (cursor) async => cursor == null
            ? _page(['a', 'b'], next: 'offset:2')
            : _page(['b', 'c']),
      );

      await harness.feed.load();
      await harness.feed.loadMore();

      expect(harness.feed.items.map((listing) => listing.id), ['a', 'b', 'c']);
    });
  });

  group('reconfiguring', () {
    test('switching filters shows the new feed, not the old one', () async {
      final harness = _build();
      harness.feed.configure(
        key: 'browse:a',
        loader: (_) async => _page(['a']),
      );
      await harness.feed.load();

      harness.feed.configure(
        key: 'browse:b',
        loader: (_) async => _page(['b']),
      );
      expect(harness.feed.hasLoaded, isFalse);

      await harness.feed.load();
      expect(harness.feed.items.map((listing) => listing.id), ['b']);
    });

    test('returning to a previous filter paints from cache', () async {
      final harness = _build();
      var calls = 0;
      Future<Page<Listing>> loaderA(Cursor? _) async {
        calls++;
        return _page(['a']);
      }

      harness.feed.configure(key: 'browse:a', loader: loaderA);
      await harness.feed.load();

      harness.feed.configure(
        key: 'browse:b',
        loader: (_) async => _page(['b']),
      );
      await harness.feed.load();

      harness.feed.configure(key: 'browse:a', loader: loaderA);
      expect(harness.feed.items.map((listing) => listing.id), ['a']);

      await harness.feed.load();
      expect(calls, 1, reason: 'the cached page was still fresh');
    });

    test('a page in flight for old filters is discarded', () async {
      final harness = _build();
      final slow = Completer<Page<Listing>>();

      harness.feed.configure(key: 'browse:a', loader: (_) => slow.future);
      final pending = harness.feed.load();

      harness.feed.configure(
        key: 'browse:b',
        loader: (_) async => _page(['b']),
      );
      await harness.feed.load();

      slow.complete(_page(['stale']));
      await pending;

      expect(harness.feed.items.map((listing) => listing.id), ['b']);
    });
  });

  group('account isolation', () {
    test('a response landing after an account switch is dropped', () async {
      final harness = _build();
      final slow = Completer<Page<Listing>>();
      harness.feed.configure(key: 'browse:a', loader: (_) => slow.future);

      final pending = harness.feed.load();
      // the session controller does exactly this when a new student resolves
      harness.generation.bump();
      harness.cache.clear();

      slow.complete(_page(['from-previous-account']));
      await pending;

      expect(
        harness.feed.items,
        isEmpty,
        reason: 'data fetched for one student must never reach the next',
      );
    });
  });

  group('failures', () {
    test('keeps cached data when a refresh fails', () async {
      final harness = _build();
      var shouldFail = false;
      harness.feed.configure(
        key: 'browse:a',
        loader: (_) async {
          if (shouldFail) throw const NetworkFailure();
          return _page(['a']);
        },
      );

      await harness.feed.load();
      shouldFail = true;
      await harness.feed.refresh();

      expect(harness.feed.failure, isA<NetworkFailure>());
      expect(
        harness.feed.items.map((listing) => listing.id),
        ['a'],
        reason: 'losing the connection must not blank the screen',
      );
    });

    test('reports an unauthorized response upwards exactly once', () async {
      final harness = _build();
      harness.feed.configure(
        key: 'browse:a',
        loader: (_) async => throw const UnauthorizedFailure(),
      );

      await harness.feed.load();

      expect(harness.feed.failure, isA<UnauthorizedFailure>());
      expect(harness.unauthorizedCount(), 1);
    });

    test('a later success clears the failure', () async {
      final harness = _build();
      var shouldFail = true;
      harness.feed.configure(
        key: 'browse:a',
        loader: (_) async {
          if (shouldFail) throw const NetworkFailure();
          return _page(['a']);
        },
      );

      await harness.feed.load();
      expect(harness.feed.failure, isNotNull);

      shouldFail = false;
      await harness.feed.refresh();
      expect(harness.feed.failure, isNull);
    });
  });
}
