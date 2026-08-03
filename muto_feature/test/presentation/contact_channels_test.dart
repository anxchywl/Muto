import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/src/domain/entities/seller_contact.dart';
import 'package:muto_feature/src/presentation/listing/contact_channels.dart';

void main() {
  group('building contact destinations', () {
    test('a telegram username becomes a t.me link built here', () {
      final channels = contactChannelsOf(
        const SellerContact(telegramUsername: 'sample_aizhan'),
      );

      expect(channels.single.medium, ContactMedium.telegram);
      expect(channels.single.display, '@sample_aizhan');
      expect(channels.single.uri.toString(), 'https://t.me/sample_aizhan');
    });

    test('an email becomes a mailto link', () {
      final channels = contactChannelsOf(
        const SellerContact(email: 'sample.seller.02@example.edu'),
      );

      expect(
        channels.single.uri.toString(),
        'mailto:sample.seller.02@example.edu',
      );
    });

    test('a phone number becomes a tel link', () {
      final channels = contactChannelsOf(
        const SellerContact(phone: '+7 700 123 45 67'),
      );

      expect(channels.single.uri.toString(), 'tel:+77001234567');
    });

    test('offers every channel the seller supplied', () {
      final channels = contactChannelsOf(
        const SellerContact(
          telegramUsername: 'sample_user',
          email: 'sample@example.edu',
          phone: '+77001234567',
        ),
      );

      expect(channels.map((channel) => channel.medium), [
        ContactMedium.telegram,
        ContactMedium.email,
        ContactMedium.phone,
      ]);
    });
  });

  group('refusing what does not pass validation', () {
    test('drops a telegram username of the wrong shape', () {
      expect(
        contactChannelsOf(const SellerContact(telegramUsername: 'no')),
        isEmpty,
      );
    });

    test('drops a malformed email and phone', () {
      final channels = contactChannelsOf(
        const SellerContact(email: 'not an email', phone: 'call me'),
      );
      expect(channels, isEmpty);
    });

    test('an absent contact offers nothing', () {
      expect(contactChannelsOf(null), isEmpty);
      expect(contactChannelsOf(const SellerContact()), isEmpty);
    });

    test('every destination uses an expected scheme', () {
      final channels = contactChannelsOf(
        const SellerContact(
          telegramUsername: 'sample_user',
          email: 'sample@example.edu',
          phone: '+77001234567',
        ),
      );

      for (final channel in channels) {
        expect(
          channel.uri.scheme,
          anyOf('https', 'mailto', 'tel'),
          reason: 'nothing else may be handed to the platform',
        );
      }
    });

    test('a username that looks like a url cannot become one', () {
      // the shape check rejects it, so no link is ever built from it
      final channels = contactChannelsOf(
        const SellerContact(telegramUsername: 'evil.example.com/path'),
      );
      expect(channels, isEmpty);
    });

    test('a telegram username is never taken as a whole path', () {
      final channels = contactChannelsOf(
        const SellerContact(telegramUsername: 'sample_user'),
      );
      expect(channels.single.uri.host, 't.me');
      expect(channels.single.uri.path, '/sample_user');
    });
  });
}
