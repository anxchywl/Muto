import 'package:shared_preferences/shared_preferences.dart';

import '../../application/cache/cache_keys.dart';
import '../../domain/repositories/search_history_store.dart';
import '../../domain/validation/search_rules.dart';

/// Keeps recent searches on the device, under the account that made them.
///
/// Everything read back goes through [SearchRules.sanitize] rather than being
/// trusted, because what is on disk may have been written by an older build.
final class PreferencesSearchHistoryStore implements SearchHistoryStore {
  const PreferencesSearchHistoryStore();

  @override
  Future<List<String>> read(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(CacheKeys.searchHistory(userId));
    return SearchRules.sanitize(stored ?? const []);
  }

  @override
  Future<List<String>> add(String userId, String term) async {
    final normalized = SearchRules.normalizeTerm(term);
    if (normalized == null) return read(userId);
    return _write(userId, SearchRules.remember(await read(userId), normalized));
  }

  @override
  Future<List<String>> remove(String userId, String term) async {
    return _write(userId, SearchRules.forget(await read(userId), term));
  }

  @override
  Future<void> clear(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(CacheKeys.searchHistory(userId));
  }

  Future<List<String>> _write(String userId, List<String> terms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      CacheKeys.searchHistory(userId),
      List<String>.of(terms),
    );
    return terms;
  }
}
