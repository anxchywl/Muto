import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../domain/entities/listing.dart';
import '../../domain/entities/page.dart';

abstract final class CacheTtl {
  /// How long a feed may be reused before it is refetched behind the scenes.
  static const Duration feed = Duration(seconds: 45);

  /// Past this age, a feed that cannot be refreshed says so rather than
  /// pretending to be current.
  static const Duration staleness = Duration(minutes: 10);
}

abstract final class CacheCapacity {
  static const int feeds = 32;
  static const int standaloneListings = 64;
}

final class _FeedState {
  _FeedState({required this.ids, required this.fetchedAt, this.nextCursor});

  List<String> ids;
  DateTime fetchedAt;
  Cursor? nextCursor;
}

/// The one place listing data lives while the feature is mounted.
///
/// A listing exists once, in [_listings], and every feed refers to it by id.
/// Patching a status therefore updates the feed, the detail screen and the
/// favorites list at the same moment, with no screen re-fetching on its own.
final class ListingCache extends ChangeNotifier {
  final Map<String, Listing> _listings = {};
  final Map<String, _FeedState> _feeds = {};
  final LinkedHashSet<String> _standaloneListingIds = LinkedHashSet();

  Listing? peek(String id) {
    final listing = _listings[id];
    if (listing != null && _standaloneListingIds.remove(id)) {
      _standaloneListingIds.add(id);
    }
    return listing;
  }

  /// Null when the feed has never loaded, which is what separates "empty" from
  /// "not yet known".
  List<Listing>? peekFeed(String key) {
    final state = _feed(key);
    if (state == null) return null;
    return [
      for (final id in state.ids)
        if (_listings[id] != null) _listings[id]!,
    ];
  }

  DateTime? fetchedAt(String key) => _feed(key)?.fetchedAt;

  Cursor? nextCursor(String key) => _feed(key)?.nextCursor;

  bool hasMore(String key) => _feed(key)?.nextCursor != null;

  bool isFresh(String key, [Duration ttl = CacheTtl.feed]) {
    final state = _feed(key);
    if (state == null) return false;
    return DateTime.now().difference(state.fetchedAt) < ttl;
  }

  bool isStale(String key) {
    final state = _feed(key);
    if (state == null) return false;
    return DateTime.now().difference(state.fetchedAt) >= CacheTtl.staleness;
  }

  /// Stores a page. [replace] starts the feed again, otherwise the page is
  /// appended and ids already present are not repeated.
  void absorbPage(String key, Page<Listing> page, {required bool replace}) {
    for (final listing in page.items) {
      _listings[listing.id] = listing;
    }

    final existing = _feed(key);
    if (replace || existing == null) {
      _feeds[key] = _FeedState(
        ids: page.items.map((listing) => listing.id).toList(),
        fetchedAt: DateTime.now(),
        nextCursor: page.nextCursor,
      );
    } else {
      final seen = existing.ids.toSet();
      for (final listing in page.items) {
        if (seen.add(listing.id)) existing.ids.add(listing.id);
      }
      existing.fetchedAt = DateTime.now();
      existing.nextCursor = page.nextCursor;
    }
    _trimFeeds();
    notifyListeners();
  }

  /// Records a listing loaded on its own, without joining any feed.
  void absorb(Listing listing) {
    _listings[listing.id] = listing;
    _retainStandalone(listing.id);
    notifyListeners();
  }

  /// Applies a mutation result. A listing that no longer belongs in a browse
  /// feed leaves it immediately rather than lingering until the next refresh.
  void patch(Listing listing) {
    _listings[listing.id] = listing;
    _retainStandalone(listing.id);
    if (!listing.status.isVisibleInBrowse) {
      for (final entry in _feeds.entries) {
        if (entry.key.startsWith('browse:')) entry.value.ids.remove(listing.id);
      }
    }
    if (!listing.status.isVisibleToOwner) {
      for (final state in _feeds.values) {
        state.ids.remove(listing.id);
      }
    }
    _markAllStale();
    notifyListeners();
  }

  void forget(String id) {
    _listings.remove(id);
    _standaloneListingIds.remove(id);
    for (final state in _feeds.values) {
      state.ids.remove(id);
    }
    _markAllStale();
    notifyListeners();
  }

  void markStale(String key) {
    final state = _feed(key);
    if (state != null) {
      state.fetchedAt = DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  void _markAllStale() {
    for (final key in _feeds.keys.toList()) {
      markStale(key);
    }
  }

  _FeedState? _feed(String key) {
    final state = _feeds.remove(key);
    if (state != null) _feeds[key] = state;
    return state;
  }

  void _trimFeeds() {
    while (_feeds.length > CacheCapacity.feeds) {
      _feeds.remove(_feeds.keys.first);
    }
    _removeUnreferencedListings();
  }

  void _retainStandalone(String id) {
    _standaloneListingIds.remove(id);
    _standaloneListingIds.add(id);
    while (_standaloneListingIds.length > CacheCapacity.standaloneListings) {
      _standaloneListingIds.remove(_standaloneListingIds.first);
    }
    _removeUnreferencedListings();
  }

  void _removeUnreferencedListings() {
    final referenced = <String>{
      ..._standaloneListingIds,
      for (final state in _feeds.values) ...state.ids,
    };
    _listings.removeWhere((id, _) => !referenced.contains(id));
  }

  /// Drops everything. Called when the account changes, so nothing from one
  /// session can be read in the next.
  void clear() {
    _listings.clear();
    _feeds.clear();
    _standaloneListingIds.clear();
    notifyListeners();
  }

  @visibleForTesting
  int get listingCount => _listings.length;
}
