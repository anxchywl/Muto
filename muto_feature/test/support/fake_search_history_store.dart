import 'package:muto_feature/src/domain/repositories/search_history_store.dart';
import 'package:muto_feature/src/domain/validation/search_rules.dart';

/// The search history, in memory, keyed by account.
///
/// Used wherever a test needs the store to behave without reaching for the
/// platform channel that backs the real one.
final class FakeSearchHistoryStore implements SearchHistoryStore {
  FakeSearchHistoryStore([Map<String, List<String>>? initial])
    : _terms = {...?initial};

  final Map<String, List<String>> _terms;

  int reads = 0;

  /// Set to hold a write open, which is how a test arranges for an account to
  /// change while one is still in flight.
  Future<void>? gate;

  @override
  Future<List<String>> read(String userId) async {
    reads++;
    return SearchRules.sanitize(_terms[userId] ?? const []);
  }

  @override
  Future<List<String>> add(String userId, String term) async {
    await gate;
    final normalized = SearchRules.normalizeTerm(term);
    if (normalized == null) return read(userId);
    final updated = SearchRules.remember(await read(userId), normalized);
    _terms[userId] = updated;
    return updated;
  }

  @override
  Future<List<String>> remove(String userId, String term) async {
    final updated = SearchRules.forget(await read(userId), term);
    _terms[userId] = updated;
    return updated;
  }

  @override
  Future<void> clear(String userId) async {
    _terms.remove(userId);
  }
}
