import 'identity.dart';
import 'image_ref.dart';
import 'listing_category.dart';
import 'listing_condition.dart';
import 'listing_kind.dart';
import 'listing_status.dart';
import 'money.dart';
import 'page.dart';
import 'seller_contact.dart';

/// A published listing.
///
/// [contact] is populated only by a detail read, and only for a viewer the
/// server considers verified. List-shaped responses always leave it null.
final class Listing {
  const Listing({
    required this.id,
    required this.version,
    required this.kind,
    required this.status,
    required this.title,
    required this.description,
    required this.condition,
    required this.category,
    required this.images,
    required this.sellerId,
    required this.sellerDisplayName,
    required this.createdAt,
    required this.updatedAt,
    this.expiresAt,
    this.price,
    this.wantedItems,
    this.contact,
  });

  final String id;
  final Version version;
  final ListingKind kind;
  final ListingStatus status;
  final String title;
  final String description;
  final ListingCondition condition;
  final ListingCategory category;
  final List<ImageRef> images;
  final String sellerId;
  final String sellerDisplayName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? expiresAt;

  bool isExpiredAt(DateTime moment) =>
      expiresAt != null && !moment.isBefore(expiresAt!);

  /// Present only when [kind] is a sale.
  final Money? price;

  /// What the seller wants in return, present only for an exchange.
  final String? wantedItems;

  final SellerContact? contact;

  ImageRef? get coverImage => images.isEmpty ? null : images.first;

  bool isOwnedBy(Identity identity) => identity.userId == sellerId;

  Listing copyWith({
    ListingStatus? status,
    Version? version,
    SellerContact? contact,
    DateTime? expiresAt,
  }) {
    return Listing(
      id: id,
      version: version ?? this.version,
      kind: kind,
      status: status ?? this.status,
      title: title,
      description: description,
      condition: condition,
      category: category,
      images: images,
      sellerId: sellerId,
      sellerDisplayName: sellerDisplayName,
      createdAt: createdAt,
      updatedAt: updatedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      price: price,
      wantedItems: wantedItems,
      contact: contact ?? this.contact,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Listing && other.id == id && other.version == version;

  @override
  int get hashCode => Object.hash(id, version);
}

/// The editable subset of a listing, used to create or update one.
final class ListingDraft {
  const ListingDraft({
    required this.kind,
    required this.title,
    required this.description,
    required this.condition,
    required this.category,
    required this.images,
    this.price,
    this.wantedItems,
  });

  final ListingKind kind;
  final String title;
  final String description;
  final ListingCondition condition;
  final ListingCategory category;
  final List<ImageRef> images;
  final Money? price;
  final String? wantedItems;

  ListingDraft copyWith({
    ListingKind? kind,
    String? title,
    String? description,
    ListingCondition? condition,
    ListingCategory? category,
    List<ImageRef>? images,
    Money? price,
    String? wantedItems,
    bool clearPrice = false,
    bool clearWantedItems = false,
  }) {
    return ListingDraft(
      kind: kind ?? this.kind,
      title: title ?? this.title,
      description: description ?? this.description,
      condition: condition ?? this.condition,
      category: category ?? this.category,
      images: images ?? this.images,
      price: clearPrice ? null : (price ?? this.price),
      wantedItems: clearWantedItems ? null : (wantedItems ?? this.wantedItems),
    );
  }
}
