import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/failures.dart';
import '../domain/repositories/listing_repository.dart';
import '../domain/repositories/search_history_store.dart';
import '../domain/validation/search_rules.dart';
import 'cache/generation.dart';

/// Drives what the search field offers before a search is run.
///
/// Both halves live here rather than in the screen: recent terms belong to the
/// account and have to be discarded with it, and suggestions have to be
/// debounced and cancelled, neither of which a widget should be deciding.
final class MutoSearchController extends ChangeNotifier {
  MutoSearchController({
    required ListingRepository listings,
    required SearchHistoryStore history,
    required CacheGeneration generation,
    required VoidCallback onUnauthorized,
    this.debounce = const Duration(milliseconds: 250),
  }) : _listings = listings,
       _history = history,
       _generation = generation,
       _onUnauthorized = onUnauthorized;

  final ListingRepository _listings;
  final SearchHistoryStore _history;
  final CacheGeneration _generation;
  final VoidCallback _onUnauthorized;
  final Duration debounce;

  String? _userId;
  Timer? _pending;
  int _attempt = 0;

  List<String> _recent = const [];
  List<String> _suggestions = const [];
  bool _isSuggesting = false;

  List<String> get recent => _recent;
  List<String> get suggestions => _suggestions;
  bool get isSuggesting => _isSuggesting;

  /// Names the account whose searches these are. A different account starts
  /// from nothing rather than inheriting what is on screen.
  Future<void> start(String userId) async {
    if (_userId == userId) return;
    _userId = userId;
    _attempt++;
    _recent = const [];
    _suggestions = const [];
    notifyListeners();
    await _readRecent();
  }

  /// Asks for suggestions for what has been typed so far. Safe to call on
  /// every keystroke: the request is debounced and an answer that arrives
  /// after the text moved on is dropped.
  void textChanged(String raw) {
    _pending?.cancel();
    final term = SearchRules.normalizeTerm(raw);

    if (term == null || !SearchRules.isSuggestible(term)) {
      _attempt++;
      if (_suggestions.isEmpty && !_isSuggesting) return;
      _suggestions = const [];
      _isSuggesting = false;
      notifyListeners();
      return;
    }

    _pending = Timer(debounce, () => unawaited(_suggest(term)));
  }

  /// Records a term that was actually searched for. Called on submit only, so
  /// the list holds searches rather than keystrokes.
  Future<void> submitted(String raw) async {
    final userId = _userId;
    final term = SearchRules.normalizeTerm(raw);
    if (userId == null || term == null) return;

    final generation = _generation.value;
    final updated = await _history.add(userId, term);
    if (!_generation.isCurrent(generation) || _userId != userId) return;
    _recent = updated;
    notifyListeners();
  }

  Future<void> forget(String term) async {
    final userId = _userId;
    if (userId == null) return;

    final generation = _generation.value;
    final updated = await _history.remove(userId, term);
    if (!_generation.isCurrent(generation) || _userId != userId) return;
    _recent = updated;
    notifyListeners();
  }

  Future<void> forgetAll() async {
    final userId = _userId;
    if (userId == null) return;

    _recent = const [];
    notifyListeners();
    await _history.clear(userId);
  }

  Future<void> _readRecent() async {
    final userId = _userId;
    if (userId == null) return;

    final generation = _generation.value;
    final stored = await _history.read(userId);
    if (!_generation.isCurrent(generation) || _userId != userId) return;
    _recent = stored;
    notifyListeners();
  }

  Future<void> _suggest(String term) async {
    final attempt = ++_attempt;
    final generation = _generation.value;
    _isSuggesting = true;
    notifyListeners();

    try {
      final terms = await _listings.suggestions(term);
      if (!_isCurrent(attempt, generation)) return;
      _suggestions = List<String>.unmodifiable(terms);
    } on MutoFailure catch (failure) {
      if (!_isCurrent(attempt, generation)) return;
      // suggestions are a convenience, so a failure empties them quietly and
      // leaves the student's own typing alone
      _suggestions = const [];
      if (failure is UnauthorizedFailure) _onUnauthorized();
    } finally {
      if (_isCurrent(attempt, generation)) {
        _isSuggesting = false;
        notifyListeners();
      }
    }
  }

  bool _isCurrent(int attempt, int generation) =>
      attempt == _attempt && _generation.isCurrent(generation);

  @override
  void dispose() {
    _pending?.cancel();
    super.dispose();
  }
}
