import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../application/cache/cache_keys.dart';
import '../../domain/entities/client_request_id.dart';
import '../../domain/entities/currency.dart';
import '../../domain/entities/image_ref.dart';
import '../../domain/entities/listing.dart';
import '../../domain/entities/listing_category.dart';
import '../../domain/entities/listing_condition.dart';
import '../../domain/entities/listing_kind.dart';
import '../../domain/entities/money.dart';
import '../../domain/entities/page.dart';
import '../../domain/repositories/draft_store.dart';

/// Keeps the unfinished listing on the device.
///
/// This is ordinary preference storage, not secure storage, which is exactly
/// why nothing sensitive is ever written here — a draft is the student's own
/// text and nothing else.
final class PreferencesDraftStore implements DraftStore {
  const PreferencesDraftStore();

  @override
  Future<StoredDraft?> read(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(CacheKeys.draft(userId));
    if (raw == null) return null;
    try {
      return _decode(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      // a draft written by an older layout is dropped, never half-read
      await prefs.remove(CacheKeys.draft(userId));
      return null;
    }
  }

  @override
  Future<void> write(String userId, StoredDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(CacheKeys.draft(userId), jsonEncode(_encode(draft)));
  }

  @override
  Future<void> clear(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(CacheKeys.draft(userId));
  }

  static Map<String, dynamic> _encode(StoredDraft stored) {
    final draft = stored.draft;
    return {
      'request_id': stored.requestId.value,
      'editing_listing_id': stored.editingListingId,
      'expected_version': stored.expectedVersion?.value,
      'kind': draft.kind.wireValue,
      'title': draft.title,
      'description': draft.description,
      'condition': draft.condition.wireValue,
      'category': draft.category.slug,
      'wanted_items': draft.wantedItems,
      'price': draft.price == null
          ? null
          : {
              'minor_units': draft.price!.minorUnits,
              'currency': draft.price!.currency.code,
            },
      'images': [
        for (final image in draft.images)
          {'id': image.id, 'version': image.version},
      ],
    };
  }

  static StoredDraft _decode(Map<String, dynamic> json) {
    final kind = ListingKind.fromWire(json['kind'] as String?);
    final condition = ListingCondition.fromWire(json['condition'] as String?);
    final category = ListingCategory.fromSlug(json['category'] as String?);
    if (kind == null || condition == null || category == null) {
      throw const FormatException('unusable draft');
    }

    final priceJson = json['price'];
    Money? price;
    if (priceJson is Map) {
      final currency = Currency.fromCode(priceJson['currency'] as String?);
      final minorUnits = priceJson['minor_units'];
      if (currency != null && minorUnits is int) {
        price = Money(minorUnits: minorUnits, currency: currency);
      }
    }

    final images = <ImageRef>[];
    final imagesJson = json['images'];
    if (imagesJson is List) {
      for (final entry in imagesJson) {
        if (entry is! Map) continue;
        final id = entry['id'];
        final version = entry['version'];
        if (id is String && version is String) {
          images.add(ImageRef(id: id, version: version));
        }
      }
    }

    final expectedVersion = json['expected_version'];

    return StoredDraft(
      draft: ListingDraft(
        kind: kind,
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        condition: condition,
        category: category,
        images: images,
        price: price,
        wantedItems: json['wanted_items'] as String?,
      ),
      requestId: ClientRequestId(json['request_id'] as String),
      editingListingId: json['editing_listing_id'] as String?,
      expectedVersion: expectedVersion is int ? Version(expectedVersion) : null,
    );
  }
}
