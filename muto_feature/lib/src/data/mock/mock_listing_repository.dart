import 'dart:collection';
import 'dart:math';

import '../../domain/entities/client_request_id.dart';
import '../../domain/entities/identity.dart';
import '../../domain/entities/listing.dart';
import '../../domain/entities/listing_status.dart';
import '../../domain/entities/page.dart';
import '../../domain/failures.dart';
import '../../domain/repositories/listing_repository.dart';
import '../../domain/validation/listing_rules.dart';
import '../../domain/validation/search_rules.dart';
import 'mock_environment.dart';

/// An in-memory stand-in for the listing service.
///
/// It enforces the same rules the real authority will — ownership, expected
/// version, allowed transitions, contact exposure — so the screens that depend
/// on those rules are built against them from the start rather than being
/// retrofitted when a server appears.
final class MockListingRepository implements ListingRepository {
  MockListingRepository({
    required List<Listing> seed,
    required Identity Function() viewer,
    this.latency = const MockLatency(),
    MockFaults? faults,
    Random? random,
  }) : _listings = List<Listing>.of(seed),
       _viewer = viewer,
       faults = faults ?? MockFaults(),
       _random = random ?? Random(20260730);

  static const int pageSize = 8;

  /// A live view of what this repository holds, so a sibling mock reads the
  /// same listings a write just changed rather than a copy taken at startup.
  late final List<Listing> all = UnmodifiableListView(_listings);

  final List<Listing> _listings;
  final Identity Function() _viewer;
  final MockLatency latency;
  final MockFaults faults;
  final Random _random;

  /// requestId to the listing it produced, plus the payload it was made with,
  /// so a repeat with a changed draft can be told apart from a plain retry.
  final Map<String, ({String listingId, int fingerprint})> _idempotency = {};

  @override
  Future<Page<Listing>> browse({
    required ListingQuery query,
    Cursor? cursor,
  }) async {
    await Future<void>.delayed(latency.read);
    faults.checkReadable();
    _expireDue();

    final matches =
        _listings
            .where((listing) => listing.status.isVisibleInBrowse)
            .where((listing) => _matchesQuery(listing, query))
            .toList()
          ..sort((a, b) => _compare(a, b, query.sort));

    return _paginate(matches.map(_withoutContact).toList(), cursor);
  }

  @override
  Future<Listing> byId(String id) async {
    await Future<void>.delayed(latency.read);
    faults.checkReadable();
    _expireDue();

    final listing = _find(id);
    if (listing == null) throw const NotFoundFailure();
    if (listing.status == ListingStatus.removed) throw const GoneFailure();

    final viewer = _viewer();
    final isOwner = listing.isOwnedBy(viewer);
    if (listing.status == ListingStatus.hidden && !isOwner) {
      throw const NotFoundFailure();
    }

    // contact belongs to a detail read, and only for a verified viewer
    return viewer.isVerified ? listing : _withoutContact(listing);
  }

  @override
  Future<List<String>> suggestions(String prefix) async {
    await Future<void>.delayed(latency.read);
    faults.checkReadable();
    _expireDue();

    final term = SearchRules.normalizeTerm(prefix)?.toLowerCase();
    if (term == null || !SearchRules.isSuggestible(term)) return const [];

    final titles = <String>[];
    for (final listing in _listings) {
      if (!listing.status.isVisibleInBrowse) continue;
      if (!listing.title.toLowerCase().startsWith(term)) continue;
      if (!titles.contains(listing.title)) titles.add(listing.title);
    }
    return titles.take(SearchRules.suggestionMax).toList();
  }

  @override
  Future<Page<Listing>> mine({ListingStatus? status, Cursor? cursor}) async {
    await Future<void>.delayed(latency.read);
    faults.checkReadable();
    _expireDue();

    final viewer = _viewer();
    final matches =
        _listings
            .where((listing) => listing.sellerId == viewer.userId)
            .where((listing) => listing.status.isVisibleToOwner)
            .where((listing) => status == null || listing.status == status)
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return _paginate(matches.map(_withoutContact).toList(), cursor);
  }

  @override
  Future<Listing> create(
    ListingDraft draft, {
    required ClientRequestId requestId,
  }) async {
    await Future<void>.delayed(latency.write);
    faults.checkWritable();

    final normalized = ListingRules.normalize(draft);
    final fingerprint = _fingerprint(normalized);

    final seen = _idempotency[requestId.value];
    if (seen != null) {
      // a retry of the same publish returns the listing it already made; the
      // same token with a changed draft is a different intent
      if (seen.fingerprint != fingerprint) throw const ConflictFailure();
      final existing = _find(seen.listingId);
      if (existing != null) return existing;
    }

    if (!ListingRules.validate(normalized).isValid) {
      throw const UnexpectedFailure(statusCode: 422);
    }

    final viewer = _viewer();
    final now = DateTime.now();
    final created = Listing(
      id: 'lst_${_random.nextInt(0x7FFFFFFF).toRadixString(16)}',
      version: const Version(1),
      kind: normalized.kind,
      status: ListingStatus.active,
      title: normalized.title,
      description: normalized.description,
      condition: normalized.condition,
      category: normalized.category,
      images: normalized.images,
      sellerId: viewer.userId,
      sellerDisplayName: viewer.displayName,
      createdAt: now,
      updatedAt: now,
      expiresAt: now.add(const Duration(days: 30)),
      price: normalized.price,
      wantedItems: normalized.wantedItems,
    );

    _listings.insert(0, created);
    _idempotency[requestId.value] = (
      listingId: created.id,
      fingerprint: fingerprint,
    );
    return created;
  }

  @override
  Future<Listing> update(
    String id,
    ListingDraft draft, {
    required Version expected,
  }) async {
    await Future<void>.delayed(latency.write);
    faults.checkWritable();

    final current = _requireOwned(id);
    _requireVersion(current, expected);
    if (!current.status.isEditable) {
      throw ConflictFailure(current: current.version);
    }

    final normalized = ListingRules.normalize(draft);
    if (!ListingRules.validate(normalized).isValid) {
      throw const UnexpectedFailure(statusCode: 422);
    }

    final updated = Listing(
      id: current.id,
      version: Version(current.version.value + 1),
      kind: normalized.kind,
      status: current.status,
      title: normalized.title,
      description: normalized.description,
      condition: normalized.condition,
      category: normalized.category,
      images: normalized.images,
      sellerId: current.sellerId,
      sellerDisplayName: current.sellerDisplayName,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
      expiresAt: current.expiresAt,
      price: normalized.price,
      wantedItems: normalized.wantedItems,
      contact: current.contact,
    );
    _replace(updated);
    return updated;
  }

  @override
  Future<Listing> changeStatus(
    String id,
    ListingStatus next, {
    required Version expected,
  }) async {
    await Future<void>.delayed(latency.write);
    faults.checkWritable();

    final current = _requireOwned(id);
    _requireVersion(current, expected);
    if (!current.status.canTransitionTo(next)) {
      throw ConflictFailure(current: current.version);
    }

    final updated = current.copyWith(
      status: next,
      version: Version(current.version.value + 1),
      expiresAt: next == ListingStatus.active
          ? DateTime.now().add(const Duration(days: 30))
          : current.expiresAt,
    );
    _replace(updated);
    return updated;
  }

  @override
  Future<void> remove(String id, {required Version expected}) async {
    await Future<void>.delayed(latency.write);
    faults.checkWritable();

    final current = _requireOwned(id);
    _requireVersion(current, expected);
    if (!current.status.canTransitionTo(ListingStatus.removed)) {
      throw ConflictFailure(current: current.version);
    }
    _replace(
      current.copyWith(
        status: ListingStatus.removed,
        version: Version(current.version.value + 1),
      ),
    );
  }

  Listing? _find(String id) {
    for (final listing in _listings) {
      if (listing.id == id) return listing;
    }
    return null;
  }

  Listing _requireOwned(String id) {
    final listing = _find(id);
    if (listing == null) throw const NotFoundFailure();
    if (listing.status == ListingStatus.removed) throw const GoneFailure();
    if (!listing.isOwnedBy(_viewer())) throw const ForbiddenFailure();
    return listing;
  }

  void _requireVersion(Listing listing, Version expected) {
    if (faults.consumeConflict() || listing.version != expected) {
      throw ConflictFailure(current: listing.version);
    }
  }

  void _replace(Listing listing) {
    final index = _listings.indexWhere((item) => item.id == listing.id);
    if (index >= 0) _listings[index] = listing;
  }

  void _expireDue() {
    final now = DateTime.now();
    for (var index = 0; index < _listings.length; index++) {
      final listing = _listings[index];
      if (!listing.isExpiredAt(now) || !listing.status.isVisibleInBrowse) {
        continue;
      }
      _listings[index] = listing.copyWith(
        status: ListingStatus.hidden,
        version: Version(listing.version.value + 1),
      );
    }
  }

  static Listing _withoutContact(Listing listing) {
    if (listing.contact == null) return listing;
    return Listing(
      id: listing.id,
      version: listing.version,
      kind: listing.kind,
      status: listing.status,
      title: listing.title,
      description: listing.description,
      condition: listing.condition,
      category: listing.category,
      images: listing.images,
      sellerId: listing.sellerId,
      sellerDisplayName: listing.sellerDisplayName,
      createdAt: listing.createdAt,
      updatedAt: listing.updatedAt,
      expiresAt: listing.expiresAt,
      price: listing.price,
      wantedItems: listing.wantedItems,
    );
  }

  bool _matchesQuery(Listing listing, ListingQuery query) {
    final text = query.text?.trim().toLowerCase();
    if (text != null && text.isNotEmpty) {
      final haystack = '${listing.title} ${listing.description}'.toLowerCase();
      if (!haystack.contains(text)) return false;
    }
    if (query.category != null && listing.category != query.category) {
      return false;
    }
    if (query.kind != null && listing.kind != query.kind) return false;
    if (query.condition != null && listing.condition != query.condition) {
      return false;
    }

    if (query.hasPriceRange) {
      final price = listing.price;
      if (price == null || price.currency != query.currency) return false;
      final min = query.minMinorUnits;
      final max = query.maxMinorUnits;
      if (min != null && price.minorUnits < min) return false;
      if (max != null && price.minorUnits > max) return false;
    } else if (query.currency != null) {
      final price = listing.price;
      if (price == null || price.currency != query.currency) return false;
    }

    return true;
  }

  static int _compare(Listing a, Listing b, ListingSort sort) {
    switch (sort) {
      case ListingSort.newest:
        return b.createdAt.compareTo(a.createdAt);
      case ListingSort.priceAscending:
      case ListingSort.priceDescending:
        final left = a.price;
        final right = b.price;
        // a listing without a price sorts last either way, and cross-currency
        // ordering is not attempted
        if (left == null && right == null) return 0;
        if (left == null) return 1;
        if (right == null) return -1;
        if (left.currency != right.currency) {
          return left.currency.index.compareTo(right.currency.index);
        }
        return sort == ListingSort.priceAscending
            ? left.compareTo(right)
            : right.compareTo(left);
    }
  }

  static Page<Listing> _paginate(List<Listing> all, Cursor? cursor) {
    final start = _offsetOf(cursor).clamp(0, all.length);
    final end = (start + pageSize).clamp(0, all.length);
    final slice = all.sublist(start, end);
    return Page<Listing>(
      items: slice,
      nextCursor: end < all.length ? Cursor('offset:$end') : null,
    );
  }

  static int _offsetOf(Cursor? cursor) {
    if (cursor == null) return 0;
    final parts = cursor.value.split(':');
    if (parts.length != 2) return 0;
    return int.tryParse(parts[1]) ?? 0;
  }

  static int _fingerprint(ListingDraft draft) {
    return Object.hash(
      draft.kind,
      draft.title,
      draft.description,
      draft.condition,
      draft.category,
      draft.price,
      draft.wantedItems,
      Object.hashAll(draft.images),
    );
  }
}
