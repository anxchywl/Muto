import 'package:flutter/foundation.dart';

import '../domain/entities/identity.dart';
import '../domain/failures.dart';
import '../domain/repositories/session_repository.dart';
import 'cache/generation.dart';
import 'cache/listing_cache.dart';

enum SessionStatus { idle, resolving, ready, expired, failed }

/// Owns who the feature believes it is acting for.
///
/// It never inspects or stores the host's token beyond the call that exchanges
/// it, and it never decides verification or ownership — those come back from
/// the authority that resolved the session.
final class SessionController extends ChangeNotifier {
  SessionController({
    required SessionRepository repository,
    required CacheGeneration generation,
    required ListingCache cache,
    VoidCallback? onSessionExpired,
  }) : _repository = repository,
       _generation = generation,
       _cache = cache,
       _onSessionExpired = onSessionExpired;

  final SessionRepository _repository;
  final CacheGeneration _generation;
  final ListingCache _cache;
  final VoidCallback? _onSessionExpired;

  SessionStatus _status = SessionStatus.idle;
  Identity? _identity;
  MutoFailure? _failure;

  String? _token;
  String? _reportedForToken;
  int _attempt = 0;

  SessionStatus get status => _status;
  Identity? get identity => _identity;
  MutoFailure? get failure => _failure;

  bool get isReady => _status == SessionStatus.ready && _identity != null;

  /// Publishing and seeing contact details both wait on the authority saying
  /// this student is verified.
  bool get canPublish => isReady && _identity!.isVerified;

  Future<void> resolve(String accessToken) async {
    final attempt = ++_attempt;
    _token = accessToken;
    _status = SessionStatus.resolving;
    _failure = null;
    notifyListeners();

    try {
      final identity = await _repository.resolve(accessToken);
      if (attempt != _attempt) return;
      _adopt(identity);
      _status = SessionStatus.ready;
    } on UnauthorizedFailure {
      if (attempt != _attempt) return;
      _expire();
    } on MutoFailure catch (failure) {
      if (attempt != _attempt) return;
      _failure = failure;
      _status = SessionStatus.failed;
    }
    if (attempt == _attempt) notifyListeners();
  }

  /// Called when any other call comes back unauthorized, so one expiry is
  /// handled in one place rather than by every screen that noticed it.
  void reportExpired() {
    if (_status == SessionStatus.expired) return;
    _attempt++;
    _expire();
    notifyListeners();
  }

  void _adopt(Identity next) {
    final previous = _identity;
    // a different student means nothing from the last session may survive
    if (previous != null && previous.userId != next.userId) {
      _generation.bump();
      _cache.clear();
    }
    _identity = next;
  }

  void _expire() {
    _status = SessionStatus.expired;
    _identity = null;
    _failure = null;
    _generation.bump();
    _cache.clear();

    // the host is asked for a new session once per token, however many calls
    // came back unauthorized
    if (_reportedForToken != _token) {
      _reportedForToken = _token;
      _onSessionExpired?.call();
    }
  }
}
