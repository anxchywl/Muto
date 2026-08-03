import 'package:flutter/foundation.dart';

import '../domain/entities/listing.dart';
import '../domain/entities/page.dart';
import '../domain/failures.dart';
import 'cache/generation.dart';
import 'cache/listing_cache.dart';

typedef PageLoader = Future<Page<Listing>> Function(Cursor? cursor);

/// Drives one paginated list of listings.
///
/// Browse, the owner's listings and favorites are the same problem with a
/// different loader, so they share this rather than repeating the freshness,
/// pagination and cancellation rules three times.
final class ListingFeedController extends ChangeNotifier {
  ListingFeedController({
    required ListingCache cache,
    required CacheGeneration generation,
    required VoidCallback onUnauthorized,
  }) : _cache = cache,
       _generation = generation,
       _onUnauthorized = onUnauthorized;

  final ListingCache _cache;
  final CacheGeneration _generation;
  final VoidCallback _onUnauthorized;

  String? _key;
  PageLoader? _loader;
  Cursor? _lastRequestedCursor;

  /// Bumped whenever the feed is reconfigured, which is how a page still in
  /// flight for the previous filters is discarded when it lands.
  int _attempt = 0;

  bool _isLoading = false;
  bool _isLoadingMore = false;
  MutoFailure? _failure;

  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  MutoFailure? get failure => _failure;

  List<Listing> get items {
    final key = _key;
    if (key == null) return const [];
    return _cache.peekFeed(key) ?? const [];
  }

  /// False until a first result exists, so a screen can tell "nothing yet"
  /// apart from "nothing matches".
  bool get hasLoaded => _key != null && _cache.peekFeed(_key!) != null;

  bool get hasMore => _key != null && _cache.hasMore(_key!);

  /// Data old enough that showing it without saying so would be misleading.
  bool get isShowingStaleData =>
      _key != null && _cache.isStale(_key!) && items.isNotEmpty;

  DateTime? get fetchedAt => _key == null ? null : _cache.fetchedAt(_key!);

  /// Points the feed at a different query. Reconfiguring with the same key
  /// keeps whatever is already cached, so returning to a previous filter paints
  /// immediately.
  void configure({required String key, required PageLoader loader}) {
    _loader = loader;
    if (_key == key) return;
    _key = key;
    _attempt++;
    _lastRequestedCursor = null;
    _isLoading = false;
    _isLoadingMore = false;
    _failure = null;
    notifyListeners();
  }

  /// Loads the first page. Fresh cache short-circuits unless [force] is set,
  /// which is what lets a screen call this on every build without hammering
  /// the source.
  Future<void> load({bool force = false}) async {
    final key = _key;
    final loader = _loader;
    if (key == null || loader == null) return;
    if (_isLoading) return;
    if (!force && _cache.isFresh(key)) return;

    final attempt = _attempt;
    final generation = _generation.value;
    _isLoading = true;
    _failure = null;
    notifyListeners();

    try {
      final page = await loader(null);
      if (!_isCurrent(attempt, generation)) return;
      _lastRequestedCursor = null;
      _cache.absorbPage(key, page, replace: true);
    } on MutoFailure catch (failure) {
      if (!_isCurrent(attempt, generation)) return;
      _record(failure);
    } finally {
      if (_isCurrent(attempt, generation)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() async {
    final key = _key;
    final loader = _loader;
    if (key == null || loader == null) return;
    if (_isLoading || _isLoadingMore) return;

    final cursor = _cache.nextCursor(key);
    if (cursor == null) return;
    // a source that hands back the cursor it was given would page forever
    if (cursor == _lastRequestedCursor) return;

    final attempt = _attempt;
    final generation = _generation.value;
    _isLoadingMore = true;
    _lastRequestedCursor = cursor;
    notifyListeners();

    try {
      final page = await loader(cursor);
      if (!_isCurrent(attempt, generation)) return;
      _cache.absorbPage(key, page, replace: false);
    } on MutoFailure catch (failure) {
      if (!_isCurrent(attempt, generation)) return;
      _record(failure);
    } finally {
      if (_isCurrent(attempt, generation)) {
        _isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() => load(force: true);

  bool _isCurrent(int attempt, int generation) =>
      attempt == _attempt && _generation.isCurrent(generation);

  void _record(MutoFailure failure) {
    _failure = failure;
    if (failure is UnauthorizedFailure) _onUnauthorized();
  }
}
