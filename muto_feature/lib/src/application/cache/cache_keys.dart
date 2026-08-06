import '../../domain/entities/listing_status.dart';
import '../../domain/repositories/listing_repository.dart';

/// Names for everything the feature keeps, in memory or on disk.
///
/// Persisted keys carry the schema version and the account they belong to, so
/// one student's data can never be read under another's session and a layout
/// change discards old entries instead of misreading them.
abstract final class CacheKeys {
  static const int schemaVersion = 1;
  static const String _prefix = 'muto_v$schemaVersion';

  static String namespace(String userId) => '${_prefix}_$userId';

  static String draft(String userId) => '${namespace(userId)}_draft';

  static String searchHistory(String userId) =>
      '${namespace(userId)}_search_history';

  /// True for any key this feature owns, which is what makes a wipe on account
  /// switch exhaustive without touching what the host stored.
  static bool isOwned(String key) => key.startsWith('${_prefix}_');

  static bool belongsTo(String key, String userId) =>
      key.startsWith('${namespace(userId)}_');

  // in-memory feed keys
  static const String favorites = 'favorites';

  static String mine(ListingStatus? status) =>
      'mine:${status?.wireValue ?? ''}';

  static String seller(String sellerId) => 'seller:$sellerId';

  /// A stable name for one filter combination, so two identical browses share
  /// a cache entry and two different ones never collide.
  static String browse(ListingQuery query) {
    final parts = <String>[
      'q=${query.text?.trim().toLowerCase() ?? ''}',
      'cat=${query.category?.slug ?? ''}',
      'kind=${query.kind?.wireValue ?? ''}',
      'cond=${query.condition?.wireValue ?? ''}',
      'cur=${query.currency?.code ?? ''}',
      'min=${query.minMinorUnits ?? ''}',
      'max=${query.maxMinorUnits ?? ''}',
      'sort=${query.sort.name}',
    ];
    return 'browse:${parts.join('&')}';
  }
}
