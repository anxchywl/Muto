import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/src/application/cache/generation.dart';
import 'package:muto_feature/src/application/favorites_controller.dart';
import 'package:muto_feature/src/domain/entities/listing.dart';
import 'package:muto_feature/src/domain/entities/page.dart';
import 'package:muto_feature/src/domain/failures.dart';
import 'package:muto_feature/src/domain/repositories/favorites_repository.dart';

/// Records what was asked of it and can be told to fail, so the optimistic
/// toggle can be observed from both sides.
final class _FakeFavorites implements FavoritesRepository {
  _FakeFavorites({Set<String>? initial}) : saved = {...?initial};

  final Set<String> saved;
  final List<String> calls = [];
  bool failWrites = false;
  MutoFailure failure = const NetworkFailure();
  Completer<void>? gate;

  @override
  Future<Set<String>> savedIds() async {
    await gate?.future;
    return saved;
  }

  @override
  Future<Page<Listing>> page({Cursor? cursor}) async =>
      const Page<Listing>.empty();

  @override
  Future<void> add(String listingId) async {
    calls.add('add:$listingId');
    await gate?.future;
    if (failWrites) throw failure;
    saved.add(listingId);
  }

  @override
  Future<void> remove(String listingId) async {
    calls.add('remove:$listingId');
    await gate?.future;
    if (failWrites) throw failure;
    saved.remove(listingId);
  }
}

({
  FavoritesController controller,
  _FakeFavorites repository,
  CacheGeneration generation,
  int Function() unauthorizedCount,
})
_build({Set<String>? initial}) {
  final repository = _FakeFavorites(initial: initial);
  final generation = CacheGeneration();
  var unauthorized = 0;
  return (
    controller: FavoritesController(
      repository: repository,
      generation: generation,
      onUnauthorized: () => unauthorized++,
    ),
    repository: repository,
    generation: generation,
    unauthorizedCount: () => unauthorized,
  );
}

void main() {
  group('loading', () {
    test('reads what the account already saved', () async {
      final harness = _build(initial: {'lst_001'});
      await harness.controller.load();

      expect(harness.controller.isSaved('lst_001'), isTrue);
      expect(harness.controller.isSaved('lst_002'), isFalse);
      expect(harness.controller.isLoaded, isTrue);
    });

    test('a response landing after an account switch is dropped', () async {
      final harness = _build(initial: {'lst_001'});
      harness.repository.gate = Completer<void>();

      final pending = harness.controller.load();
      // the session controller does exactly this when a new student resolves
      harness.generation.bump();
      harness.repository.gate!.complete();
      await pending;

      expect(
        harness.controller.isSaved('lst_001'),
        isFalse,
        reason: 'one account\'s favorites must not surface as another\'s',
      );
    });
  });

  group('toggling', () {
    test('flips the heart before the write finishes', () async {
      final harness = _build();
      harness.repository.gate = Completer<void>();

      final pending = harness.controller.toggle('lst_001');
      expect(
        harness.controller.isSaved('lst_001'),
        isTrue,
        reason: 'the control must respond at once, not after a round trip',
      );

      harness.repository.gate!.complete();
      await pending;
      expect(harness.controller.isSaved('lst_001'), isTrue);
    });

    test('puts the heart back when the write fails', () async {
      final harness = _build();
      harness.repository.failWrites = true;

      await harness.controller.toggle('lst_001');

      expect(
        harness.controller.isSaved('lst_001'),
        isFalse,
        reason: 'a failed save must not look like it worked',
      );
    });

    test('unsaving restores the heart when the write fails', () async {
      final harness = _build(initial: {'lst_001'});
      await harness.controller.load();
      harness.repository.failWrites = true;

      await harness.controller.toggle('lst_001');
      expect(harness.controller.isSaved('lst_001'), isTrue);
    });

    test('ignores a second tap while one is in flight', () async {
      final harness = _build();
      harness.repository.gate = Completer<void>();

      final first = harness.controller.toggle('lst_001');
      final second = harness.controller.toggle('lst_001');

      harness.repository.gate!.complete();
      await Future.wait([first, second]);

      expect(harness.repository.calls, ['add:lst_001']);
    });

    test('reports an expired session upwards', () async {
      final harness = _build();
      harness.repository
        ..failWrites = true
        ..failure = const UnauthorizedFailure();

      await harness.controller.toggle('lst_001');
      expect(harness.unauthorizedCount(), 1);
    });

    test('notifies listeners so every card showing it updates', () async {
      final harness = _build();
      var notifications = 0;
      harness.controller.addListener(() => notifications++);

      await harness.controller.toggle('lst_001');
      expect(notifications, greaterThan(0));
    });
  });
}
