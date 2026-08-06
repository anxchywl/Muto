/// Local, per-account storage for what a student searched for.
///
/// The account is named on every call rather than held inside, so one
/// student's searches can never be read under another's session. Every method
/// returns the list as it now stands, so a caller never has to guess what the
/// bound did.
abstract interface class SearchHistoryStore {
  Future<List<String>> read(String userId);

  Future<List<String>> add(String userId, String term);

  Future<List<String>> remove(String userId, String term);

  Future<void> clear(String userId);
}
