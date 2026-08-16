import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/src/application/cache/generation.dart';
import 'package:muto_feature/src/application/search_controller.dart';
import 'package:muto_feature/src/domain/entities/client_request_id.dart';
import 'package:muto_feature/src/domain/entities/listing.dart';
import 'package:muto_feature/src/domain/entities/listing_status.dart';
import 'package:muto_feature/src/domain/entities/page.dart';
import 'package:muto_feature/src/domain/failures.dart';
import 'package:muto_feature/src/domain/repositories/listing_repository.dart';

import '../support/fake_search_history_store.dart';

/// Only the suggestion call matters here, so everything else refuses rather
/// than pretending to work.
final class _FakeListings implements ListingRepository {
  _FakeListings({this.failure});

  static const List<String> terms = ['lamp', 'lamps'];

  final MutoFailure? failure;

  int calls = 0;
  final List<String> prefixes = [];

  @override
  Future<List<String>> suggestions(String prefix) async {
    calls++;
    prefixes.add(prefix);
    final thrown = failure;
    if (thrown != null) throw thrown;
    return terms;
  }

  @override
  Future<Page<Listing>> browse({required ListingQuery query, Cursor? cursor}) =>
      throw UnimplementedError();

  @override
  Future<Listing> byId(String id) => throw UnimplementedError();

  @override
  Future<Page<Listing>> mine({ListingStatus? status, Cursor? cursor}) =>
      throw UnimplementedError();

  @override
  Future<Listing> create(
    ListingDraft draft, {
    required ClientRequestId requestId,
  }) => throw UnimplementedError();

  @override
  Future<Listing> update(
    String id,
    ListingDraft draft, {
    required Version expected,
  }) => throw UnimplementedError();

  @override
  Future<Listing> changeStatus(
    String id,
    ListingStatus next, {
    required Version expected,
  }) => throw UnimplementedError();

  @override
  Future<void> remove(String id, {required Version expected}) =>
      throw UnimplementedError();
}

void main() {
  late CacheGeneration generation;
  late FakeSearchHistoryStore history;
  late _FakeListings listings;
  late MutoSearchController controller;
  var unauthorized = 0;

  MutoSearchController build({_FakeListings? source}) {
    listings = source ?? _FakeListings();
    return MutoSearchController(
      listings: listings,
      history: history,
      generation: generation,
      onUnauthorized: () => unauthorized++,
      debounce: const Duration(milliseconds: 10),
    );
  }

  setUp(() {
    generation = CacheGeneration();
    history = FakeSearchHistoryStore();
    unauthorized = 0;
    controller = build();
  });

  tearDown(() => controller.dispose());

  test('recent terms belong to the account that searched for them', () async {
    await controller.start('usr_001');
    await controller.submitted('lamp');
    expect(controller.recent, ['lamp']);

    await controller.start('usr_002');
    expect(controller.recent, isEmpty);
  });

  test('only a submitted term is remembered', () async {
    await controller.start('usr_001');
    controller.textChanged('lam');
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(controller.recent, isEmpty);
  });

  test('a term too short to mean anything asks for nothing', () async {
    await controller.start('usr_001');
    controller.textChanged('l');
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(listings.calls, 0);
    expect(controller.suggestions, isEmpty);
  });

  test('typing quickly asks once, for the last thing typed', () async {
    await controller.start('usr_001');
    controller
      ..textChanged('la')
      ..textChanged('lam')
      ..textChanged('lamp');
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(listings.calls, 1);
    expect(listings.prefixes.single, 'lamp');
    expect(controller.suggestions, ['lamp', 'lamps']);
  });

  test('clearing the field clears what was on offer', () async {
    await controller.start('usr_001');
    controller.textChanged('lamp');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(controller.suggestions, isNotEmpty);

    controller.textChanged('');
    expect(controller.suggestions, isEmpty);
  });

  test(
    'changing the prefix clears suggestions from the previous prefix',
    () async {
      await controller.start('usr_001');
      controller.textChanged('lamp');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(controller.suggestions, isNotEmpty);

      controller.textChanged('desk');
      expect(controller.suggestions, isEmpty);
    },
  );

  test(
    'a failed suggestion empties the list and leaves the typing alone',
    () async {
      controller.dispose();
      controller = build(
        source: _FakeListings(failure: const NetworkFailure()),
      );
      await controller.start('usr_001');

      controller.textChanged('lamp');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(controller.suggestions, isEmpty);
      expect(controller.isSuggesting, isFalse);
    },
  );

  test(
    'an expired session is reported once, by the suggestion that hit it',
    () async {
      controller.dispose();
      controller = build(
        source: _FakeListings(failure: const UnauthorizedFailure()),
      );
      await controller.start('usr_001');

      controller.textChanged('lamp');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(unauthorized, 1);
    },
  );

  test(
    'a write still in flight when the account changes is discarded',
    () async {
      await controller.start('usr_001');
      await controller.submitted('lamp');

      final held = Completer<void>();
      history.gate = held.future;
      final pending = controller.submitted('desk');

      generation.bump();
      held.complete();
      await pending;

      expect(controller.recent, ['lamp']);
    },
  );

  test(
    'forgetting a term drops it, and forgetting all empties the list',
    () async {
      await controller.start('usr_001');
      await controller.submitted('lamp');
      await controller.submitted('desk');

      await controller.forget('lamp');
      expect(controller.recent, ['desk']);

      await controller.forgetAll();
      expect(controller.recent, isEmpty);
      expect(await history.read('usr_001'), isEmpty);
    },
  );
}
