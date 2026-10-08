import '../entities/seller_contact.dart';

/// Shape checks for the seller's external contact details.
///
/// These decide whether the app is willing to build an external link at all.
/// Nothing here trusts a string enough to open it without passing these.
abstract final class ContactRules {
  static final RegExp _telegram = RegExp(r'^[A-Za-z0-9_]{5,32}$');
  static final RegExp _email = RegExp(
    r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$',
  );
  static final RegExp _phone = RegExp(r'^\+[1-9]\d{7,14}$');

  /// Accepts an optional leading `@` and returns the bare username.
  static String? normalizeTelegramUsername(String? input) {
    if (input == null) return null;
    final trimmed = input.trim();
    final bare = trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;
    return _telegram.hasMatch(bare) ? bare : null;
  }

  static String? normalizeEmail(String? input) {
    if (input == null) return null;
    final trimmed = input.trim();
    if (trimmed.length > 254) return null;
    return _email.hasMatch(trimmed) ? trimmed : null;
  }

  /// Accepts spaces and dashes as typed, returns strict E.164.
  static String? normalizePhone(String? input) {
    if (input == null) return null;
    final compact = input.replaceAll(RegExp(r'[\s\-()]'), '');
    return _phone.hasMatch(compact) ? compact : null;
  }

  /// Drops every field that does not survive normalisation, so an invalid
  /// value can never reach link construction.
  static SellerContact sanitize(SellerContact contact) {
    return SellerContact(
      telegramUsername: normalizeTelegramUsername(contact.telegramUsername),
      whatsappPhone: normalizePhone(contact.whatsappPhone),
      email: normalizeEmail(contact.email),
      phone: normalizePhone(contact.phone),
    );
  }
}
