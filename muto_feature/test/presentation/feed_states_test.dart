import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/src/application/cache/generation.dart';
import 'package:muto_feature/src/application/cache/listing_cache.dart';
import 'package:muto_feature/src/application/listing_feed_controller.dart';
import 'package:muto_feature/src/domain/entities/listing.dart';
import 'package:muto_feature/src/domain/entities/page.dart';
import 'package:muto_feature/src/domain/failures.dart';

/// A feed that has never loaded is not the same as one that came back empty,
/// and a screen must not say "nothing matches" before anything has arrived.
void main() {
  late ListingFeedController feed;

  setUp(() {
    feed = ListingFeedController(
      cache: ListingCache(),
      generation: CacheGeneration(),
      onUnauthorized: () {},
    );
  });

  test('a feed reports not loaded until a result arrives', () async {
    feed.configure(key: 'k', loader: (_) async => const Page<Listing>.empty());
    expect(feed.hasLoaded, isFalse);
    expect(feed.items, isEmpty);

    await feed.load();

    expect(feed.hasLoaded, isTrue);
    expect(feed.items, isEmpty);
  });

  test('a failed first load leaves it not loaded', () async {
    feed.configure(key: 'k', loader: (_) async => throw const NetworkFailure());
    await feed.load();

    expect(feed.hasLoaded, isFalse);
    expect(feed.failure, isA<NetworkFailure>());
  });

  test('the two states are distinguishable to a screen', () async {
    // guards the ordering the view depends on: loaded-and-empty must be the
    // only path that reaches the empty message
    feed.configure(key: 'k', loader: (_) async => const Page<Listing>.empty());

    expect(feed.hasLoaded, isFalse, reason: 'before any load');
    await feed.load();
    expect(feed.hasLoaded, isTrue, reason: 'after an empty result');
  });
}
