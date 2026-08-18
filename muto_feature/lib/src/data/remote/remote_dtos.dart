import '../../domain/entities/currency.dart';
import '../../domain/entities/identity.dart';
import '../../domain/entities/image_ref.dart';
import '../../domain/entities/listing.dart';
import '../../domain/entities/listing_category.dart';
import '../../domain/entities/listing_condition.dart';
import '../../domain/entities/listing_kind.dart';
import '../../domain/entities/listing_status.dart';
import '../../domain/entities/money.dart';
import '../../domain/entities/operational_report.dart';
import '../../domain/entities/page.dart';
import '../../domain/entities/report_reason.dart';
import '../../domain/entities/seller_contact.dart';
import '../../domain/entities/seller_profile.dart';
import '../../domain/failures.dart';

Identity identityFromWire(Map<String, Object?> value) => Identity(
  userId: _string(value, 'user_id'),
  displayName: _string(value, 'display_name'),
  isVerified: _bool(value, 'is_verified'),
  isAdmin: _bool(value, 'is_admin'),
);

OperationalReport operationalReportFromWire(Map<String, Object?> value) {
  final reason = ReportReason.fromWire(_string(value, 'reason'));
  if (reason == null) throw const UnexpectedFailure();
  return OperationalReport(
    id: _string(value, 'id'),
    listingId: _string(value, 'listing_id'),
    listingTitle: _string(value, 'listing_title'),
    listingStatus: ListingStatus.fromWire(_string(value, 'listing_status')),
    reason: reason,
    note: _nullableString(value, 'note'),
    createdAt: _date(value, 'created_at'),
  );
}

Listing listingFromWire(Map<String, Object?> value) {
  final kind = ListingKind.fromWire(_string(value, 'kind'));
  final condition = ListingCondition.fromWire(_string(value, 'condition'));
  final category = ListingCategory.fromSlug(_string(value, 'category'));
  if (kind == null || condition == null || category == null) {
    throw const UnexpectedFailure();
  }
  final images = _list(
    value,
    'images',
  ).map((item) => imageRefFromWire(_object(item))).toList(growable: false);
  final priceValue = value['price'];
  final contactValue = value['contact'];
  return Listing(
    id: _string(value, 'id'),
    version: Version(_int(value, 'version')),
    kind: kind,
    status: ListingStatus.fromWire(_string(value, 'status')),
    title: _string(value, 'title'),
    description: _string(value, 'description'),
    condition: condition,
    category: category,
    images: images,
    sellerId: _string(value, 'seller_id'),
    sellerDisplayName: _string(value, 'seller_display_name'),
    createdAt: _date(value, 'created_at'),
    updatedAt: _date(value, 'updated_at'),
    expiresAt:
        _optionalDate(value, 'expires_at') ??
        _date(value, 'created_at').add(const Duration(days: 30)),
    price: priceValue == null ? null : moneyFromWire(_object(priceValue)),
    wantedItems: _nullableString(value, 'wanted_items'),
    contact: contactValue == null
        ? null
        : sellerContactFromWire(_object(contactValue)),
  );
}

DateTime? _optionalDate(Map<String, Object?> value, String key) {
  final raw = value[key];
  return raw is String ? DateTime.tryParse(raw) : null;
}

Money moneyFromWire(Map<String, Object?> value) {
  final currency = Currency.fromCode(_string(value, 'currency'));
  if (currency == null) throw const UnexpectedFailure();
  return Money(minorUnits: _int(value, 'minor_units'), currency: currency);
}

ImageRef imageRefFromWire(Map<String, Object?> value) =>
    ImageRef(id: _string(value, 'id'), version: _string(value, 'version'));

SellerContact sellerContactFromWire(Map<String, Object?> value) =>
    SellerContact(
      telegramUsername: _nullableString(value, 'telegram_username'),
      whatsappPhone: _nullableString(value, 'whatsapp_phone'),
      email: _nullableString(value, 'email'),
      phone: _nullableString(value, 'phone'),
    );

SellerProfile sellerProfileFromWire(Map<String, Object?> value) =>
    SellerProfile(
      sellerId: _string(value, 'seller_id'),
      displayName: _string(value, 'display_name'),
      isVerified: _bool(value, 'is_verified'),
      activeListingCount: _int(value, 'active_listing_count'),
      firstListedAt: _date(value, 'first_listed_at'),
    );

Page<Listing> listingPageFromWire(Map<String, Object?> envelope) {
  final items = _list(
    envelope,
    'data',
  ).map((item) => listingFromWire(_object(item))).toList(growable: false);
  final meta = _object(envelope['meta']);
  final next = _nullableString(meta, 'next_cursor');
  return Page(items: items, nextCursor: next == null ? null : Cursor(next));
}

Page<OperationalReport> operationalReportPageFromWire(
  Map<String, Object?> envelope,
) {
  final items = _list(envelope, 'data')
      .map((item) => operationalReportFromWire(_object(item)))
      .toList(growable: false);
  final meta = _object(envelope['meta']);
  final next = _nullableString(meta, 'next_cursor');
  return Page(items: items, nextCursor: next == null ? null : Cursor(next));
}

Map<String, Object?> listingDraftToWire(ListingDraft draft) => {
  'kind': draft.kind.wireValue,
  'title': draft.title,
  'description': draft.description,
  'condition': draft.condition.wireValue,
  'category': draft.category.slug,
  'price_minor_units': draft.price?.minorUnits,
  'currency': draft.price?.currency.code,
  'wanted_items': draft.wantedItems,
  'images': draft.images
      .map((image) => {'id': image.id, 'version': image.version})
      .toList(growable: false),
};

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) throw const UnexpectedFailure();
  return value;
}

List<Object?> _list(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! List<Object?>) throw const UnexpectedFailure();
  return field;
}

String _string(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String) throw const UnexpectedFailure();
  return field;
}

String? _nullableString(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return null;
  if (field is! String) throw const UnexpectedFailure();
  return field;
}

int _int(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! int) throw const UnexpectedFailure();
  return field;
}

bool _bool(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! bool) throw const UnexpectedFailure();
  return field;
}

DateTime _date(Map<String, Object?> value, String key) {
  final parsed = DateTime.tryParse(_string(value, key));
  if (parsed == null) throw const UnexpectedFailure();
  return parsed;
}
