import '../entities/client_request_id.dart';
import '../entities/currency.dart';
import '../entities/listing.dart';
import '../entities/listing_category.dart';
import '../entities/listing_condition.dart';
import '../entities/listing_kind.dart';
import '../entities/listing_status.dart';
import '../entities/page.dart';

enum ListingSort { newest, priceAscending, priceDescending }

/// A browse request.
///
/// A price range is only meaningful inside one currency, since v1 does no
/// conversion — [currency] must be set for [minMinorUnits] or [maxMinorUnits]
/// to be applied.
final class ListingQuery {
  const ListingQuery({
    this.text,
    this.category,
    this.kind,
    this.condition,
    this.currency,
    this.minMinorUnits,
    this.maxMinorUnits,
    this.sort = ListingSort.newest,
  });

  final String? text;
  final ListingCategory? category;
  final ListingKind? kind;
  final ListingCondition? condition;
  final Currency? currency;
  final int? minMinorUnits;
  final int? maxMinorUnits;
  final ListingSort sort;

  bool get hasPriceRange =>
      currency != null && (minMinorUnits != null || maxMinorUnits != null);

  ListingQuery copyWith({
    String? text,
    ListingCategory? category,
    ListingKind? kind,
    ListingCondition? condition,
    Currency? currency,
    int? minMinorUnits,
    int? maxMinorUnits,
    ListingSort? sort,
    bool clearText = false,
    bool clearCategory = false,
    bool clearKind = false,
    bool clearCondition = false,
    bool clearPriceRange = false,
  }) {
    return ListingQuery(
      text: clearText ? null : (text ?? this.text),
      category: clearCategory ? null : (category ?? this.category),
      kind: clearKind ? null : (kind ?? this.kind),
      condition: clearCondition ? null : (condition ?? this.condition),
      currency: clearPriceRange ? null : (currency ?? this.currency),
      minMinorUnits: clearPriceRange
          ? null
          : (minMinorUnits ?? this.minMinorUnits),
      maxMinorUnits: clearPriceRange
          ? null
          : (maxMinorUnits ?? this.maxMinorUnits),
      sort: sort ?? this.sort,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ListingQuery &&
          other.text == text &&
          other.category == category &&
          other.kind == kind &&
          other.condition == condition &&
          other.currency == currency &&
          other.minMinorUnits == minMinorUnits &&
          other.maxMinorUnits == maxMinorUnits &&
          other.sort == sort;

  @override
  int get hashCode => Object.hash(
    text,
    category,
    kind,
    condition,
    currency,
    minMinorUnits,
    maxMinorUnits,
    sort,
  );
}

/// Reads and writes for listings.
///
/// Every method throws a `MutoFailure` subtype and nothing else. Ownership and
/// status transitions are decided by the implementation's authority, not here.
abstract interface class ListingRepository {
  Future<Page<Listing>> browse({required ListingQuery query, Cursor? cursor});

  /// A detail read. This is the only call that may return seller contact
  /// details, and only for a viewer the authority considers verified.
  Future<Listing> byId(String id);

  /// Terms that complete what the student is typing.
  ///
  /// A hint and nothing more: it carries no ids, no prices and no contact
  /// details, so an autocomplete list can never become a way to read something
  /// the feed would not show.
  Future<List<String>> suggestions(String prefix);

  Future<Page<Listing>> mine({ListingStatus? status, Cursor? cursor});

  Future<Listing> create(
    ListingDraft draft, {
    required ClientRequestId requestId,
  });

  Future<Listing> update(
    String id,
    ListingDraft draft, {
    required Version expected,
  });

  Future<Listing> changeStatus(
    String id,
    ListingStatus next, {
    required Version expected,
  });

  Future<void> remove(String id, {required Version expected});
}
