import '../../domain/entities/seller_contact.dart';
import '../../domain/validation/contact_rules.dart';

enum ContactMedium { telegram, email, phone }

/// A way to reach the seller, with the destination already built.
///
/// The [uri] is constructed here from a value that passed its shape check. No
/// URL ever arrives from outside and is opened as given, so there is nothing
/// for a crafted listing to point at.
final class ContactChannel {
  const ContactChannel({
    required this.medium,
    required this.display,
    required this.uri,
  });

  final ContactMedium medium;

  /// What the student sees and can copy, such as `@username`.
  final String display;

  final Uri uri;
}

/// Every channel that survives validation, in the order they are offered.
List<ContactChannel> contactChannelsOf(SellerContact? contact) {
  if (contact == null) return const [];
  final sanitized = ContactRules.sanitize(contact);
  final channels = <ContactChannel>[];

  final telegram = sanitized.telegramUsername;
  if (telegram != null) {
    channels.add(
      ContactChannel(
        medium: ContactMedium.telegram,
        display: '@$telegram',
        uri: Uri.https('t.me', '/$telegram'),
      ),
    );
  }

  final email = sanitized.email;
  if (email != null) {
    channels.add(
      ContactChannel(
        medium: ContactMedium.email,
        display: email,
        uri: Uri(scheme: 'mailto', path: email),
      ),
    );
  }

  final phone = sanitized.phone;
  if (phone != null) {
    channels.add(
      ContactChannel(
        medium: ContactMedium.phone,
        display: phone,
        uri: Uri(scheme: 'tel', path: phone),
      ),
    );
  }

  return channels;
}
