import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../domain/entities/currency.dart';
import '../../domain/entities/identity.dart';
import '../../domain/entities/image_ref.dart';
import '../../domain/entities/listing.dart';
import '../../domain/entities/listing_category.dart';
import '../../domain/entities/listing_condition.dart';
import '../../domain/entities/listing_kind.dart';
import '../../domain/entities/listing_status.dart';
import '../../domain/entities/money.dart';
import '../../domain/entities/page.dart';
import '../../domain/entities/seller_contact.dart';

/// Package-qualified on purpose. A package's own assets are bundled under
/// `packages/<name>/` once another package depends on it, so the bare path
/// only ever resolves when this package is the root — which it is in tests and
/// is not in a real host.
const String kSampleListingsAsset =
    'packages/muto_feature/assets/sample/listings.json';

/// The seed the mock repositories start from.
final class SampleData {
  const SampleData({required this.viewer, required this.listings});

  final Identity viewer;
  final List<Listing> listings;

  static Future<SampleData> load() async {
    return decode(await rootBundle.loadString(kSampleListingsAsset));
  }

  /// Decoding is deliberately tolerant: a listing this build cannot make sense
  /// of is skipped rather than taking the whole feed down, which is the same
  /// contract a real response has to be read under.
  static SampleData decode(String source) {
    final root = jsonDecode(source) as Map<String, dynamic>;

    final listings = <Listing>[];
    for (final entry in root['listings'] as List<dynamic>) {
      final listing = _tryListing(entry);
      if (listing != null) listings.add(listing);
    }

    return SampleData(
      viewer: _identity(root['viewer'] as Map<String, dynamic>),
      listings: listings,
    );
  }

  static Identity _identity(Map<String, dynamic> json) {
    return Identity(
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String,
      isVerified: json['is_verified'] as bool,
    );
  }

  static Listing? _tryListing(Object? entry) {
    if (entry is! Map<String, dynamic>) return null;
    try {
      return _listing(entry);
    } on Object {
      return null;
    }
  }

  static Listing _listing(Map<String, dynamic> json) {
    final kind = ListingKind.fromWire(json['kind'] as String?);
    final condition = ListingCondition.fromWire(json['condition'] as String?);
    final category = ListingCategory.fromSlug(json['category'] as String?);
    if (kind == null || condition == null || category == null) {
      throw const FormatException('unusable listing');
    }

    return Listing(
      id: json['id'] as String,
      version: Version(json['version'] as int),
      kind: kind,
      status: ListingStatus.fromWire(json['status'] as String?),
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      condition: condition,
      category: category,
      images: _images(json['images']),
      sellerId: json['seller_id'] as String,
      sellerDisplayName: json['seller_display_name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      expiresAt: json['expires_at'] is String
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      price: _money(json['price']),
      wantedItems: json['wanted_items'] as String?,
      contact: _contact(json['contact']),
    );
  }

  static List<ImageRef> _images(Object? raw) {
    if (raw is! List) return const [];
    final images = <ImageRef>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final id = entry['id'];
      final version = entry['version'];
      if (id is String && version is String) {
        images.add(ImageRef(id: id, version: version));
      }
    }
    return images;
  }

  static Money? _money(Object? raw) {
    if (raw is! Map) return null;
    final minorUnits = raw['minor_units'];
    final currency = Currency.fromCode(raw['currency'] as String?);
    if (minorUnits is! int || currency == null) return null;
    return Money(minorUnits: minorUnits, currency: currency);
  }

  static SellerContact? _contact(Object? raw) {
    if (raw is! Map) return null;
    return SellerContact(
      telegramUsername: raw['telegram_username'] as String?,
      whatsappPhone: raw['whatsapp_phone'] as String?,
      email: raw['email'] as String?,
      phone: raw['phone'] as String?,
    );
  }
}
