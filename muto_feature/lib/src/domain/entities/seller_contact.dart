/// How to reach the seller outside the app.
///
/// These are structured fields, never URLs — the client builds every external
/// link itself, which removes the possibility of following a link supplied by
/// someone else. Contact details belong to the detail view only.
final class SellerContact {
  const SellerContact({
    this.telegramUsername,
    this.whatsappPhone,
    this.email,
    this.phone,
  });

  /// Without the leading `@`.
  final String? telegramUsername;
  final String? whatsappPhone;
  final String? email;

  /// E.164, including the leading `+`.
  final String? phone;

  bool get isEmpty =>
      (telegramUsername == null || telegramUsername!.isEmpty) &&
      (whatsappPhone == null || whatsappPhone!.isEmpty) &&
      (email == null || email!.isEmpty) &&
      (phone == null || phone!.isEmpty);

  bool get isNotEmpty => !isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SellerContact &&
          other.telegramUsername == telegramUsername &&
          other.whatsappPhone == whatsappPhone &&
          other.email == email &&
          other.phone == phone;

  @override
  int get hashCode =>
      Object.hash(telegramUsername, whatsappPhone, email, phone);
}
