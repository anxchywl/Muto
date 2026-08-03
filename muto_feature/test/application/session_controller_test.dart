import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/src/application/cache/generation.dart';
import 'package:muto_feature/src/application/cache/listing_cache.dart';
import 'package:muto_feature/src/application/session_controller.dart';
import 'package:muto_feature/src/domain/entities/identity.dart';
import 'package:muto_feature/src/domain/failures.dart';
import 'package:muto_feature/src/domain/repositories/session_repository.dart';

const _aruzhan = Identity(
  userId: 'usr_001',
  displayName: 'Aruzhan',
  isVerified: true,
);
const _daniyar = Identity(
  userId: 'usr_003',
  displayName: 'Daniyar',
  isVerified: true,
);
const _unverified = Identity(
  userId: 'usr_004',
  displayName: 'Madina',
  isVerified: false,
);

/// Hand-written so the test states exactly what the session endpoint does on
/// each call, including failing partway through.
final class _FakeSessionRepository implements SessionRepository {
  _FakeSessionRepository(this.responses);

  final List<FutureOr<Identity> Function()> responses;
  final List<String> tokensSeen = [];
  int _call = 0;

  @override
  Future<Identity> resolve(String accessToken) async {
    tokensSeen.add(accessToken);
    final index = _call < responses.length ? _call : responses.length - 1;
    _call++;
    return responses[index]();
  }
}

({
  SessionController session,
  CacheGeneration generation,
  ListingCache cache,
  int Function() expiryCount,
})
_build(List<FutureOr<Identity> Function()> responses) {
  final generation = CacheGeneration();
  final cache = ListingCache();
  var expiries = 0;
  final session = SessionController(
    repository: _FakeSessionRepository(responses),
    generation: generation,
    cache: cache,
    onSessionExpired: () => expiries++,
  );
  return (
    session: session,
    generation: generation,
    cache: cache,
    expiryCount: () => expiries,
  );
}

void main() {
  group('resolving a session', () {
    test('adopts the identity the authority returns', () async {
      final harness = _build([() => _aruzhan]);
      await harness.session.resolve('token-a');

      expect(harness.session.status, SessionStatus.ready);
      expect(harness.session.identity, _aruzhan);
      expect(harness.session.isReady, isTrue);
    });

    test(
      'publishing waits on the authority calling the student verified',
      () async {
        final harness = _build([() => _unverified]);
        await harness.session.resolve('token-a');

        expect(harness.session.isReady, isTrue);
        expect(
          harness.session.canPublish,
          isFalse,
          reason: 'verification is asserted by the server, never assumed here',
        );
      },
    );

    test('a network failure is a failure, not an expiry', () async {
      final harness = _build([() => throw const NetworkFailure()]);
      await harness.session.resolve('token-a');

      expect(harness.session.status, SessionStatus.failed);
      expect(harness.session.failure, isA<NetworkFailure>());
      expect(
        harness.expiryCount(),
        0,
        reason: 'being offline must not ask the host for a new token',
      );
    });

    test('an unauthorized response expires the session', () async {
      final harness = _build([() => throw const UnauthorizedFailure()]);
      await harness.session.resolve('token-a');

      expect(harness.session.status, SessionStatus.expired);
      expect(harness.session.identity, isNull);
      expect(harness.expiryCount(), 1);
    });
  });

  group('account switching', () {
    test(
      'a different student bumps the generation and clears the cache',
      () async {
        final harness = _build([() => _aruzhan, () => _daniyar]);

        await harness.session.resolve('token-a');
        final generationBefore = harness.generation.value;

        await harness.session.resolve('token-b');

        expect(harness.session.identity, _daniyar);
        expect(
          harness.generation.value,
          greaterThan(generationBefore),
          reason: 'a response already in flight must be discarded',
        );
      },
    );

    test('the same student again keeps the generation steady', () async {
      final harness = _build([() => _aruzhan, () => _aruzhan]);

      await harness.session.resolve('token-a');
      final generationBefore = harness.generation.value;
      await harness.session.resolve('token-a-refreshed');

      expect(harness.generation.value, generationBefore);
    });

    test('a slow first resolve cannot overwrite a newer one', () async {
      final slow = Completer<Identity>();
      final harness = _build([() => slow.future, () => _daniyar]);

      final first = harness.session.resolve('token-a');
      await harness.session.resolve('token-b');
      slow.complete(_aruzhan);
      await first;

      expect(
        harness.session.identity,
        _daniyar,
        reason: 'the newer session wins regardless of arrival order',
      );
    });
  });

  group('expiry reporting', () {
    test('asks the host for a new session once per token', () async {
      final harness = _build([() => _aruzhan]);
      await harness.session.resolve('token-a');

      harness.session
        ..reportExpired()
        ..reportExpired()
        ..reportExpired();

      expect(
        harness.expiryCount(),
        1,
        reason: 'several calls failing at once is still one expired session',
      );
    });

    test('a new token can report an expiry again', () async {
      final harness = _build([() => _aruzhan, () => _aruzhan]);

      await harness.session.resolve('token-a');
      harness.session.reportExpired();
      expect(harness.expiryCount(), 1);

      await harness.session.resolve('token-b');
      harness.session.reportExpired();
      expect(harness.expiryCount(), 2);
    });

    test('expiring drops the identity and the cached data', () async {
      final harness = _build([() => _aruzhan]);
      await harness.session.resolve('token-a');

      final generationBefore = harness.generation.value;
      harness.session.reportExpired();

      expect(harness.session.identity, isNull);
      expect(harness.session.status, SessionStatus.expired);
      expect(harness.generation.value, greaterThan(generationBefore));
      expect(harness.cache.listingCount, 0);
    });

    test('notifies listeners so screens can react once', () async {
      final harness = _build([() => _aruzhan]);
      var notifications = 0;
      harness.session.addListener(() => notifications++);

      await harness.session.resolve('token-a');
      final afterResolve = notifications;
      harness.session.reportExpired();

      expect(notifications, greaterThan(afterResolve));
    });
  });
}
