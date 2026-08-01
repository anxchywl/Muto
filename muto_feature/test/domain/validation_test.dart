import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/src/domain/entities/currency.dart';
import 'package:muto_feature/src/domain/entities/image_ref.dart';
import 'package:muto_feature/src/domain/entities/listing.dart';
import 'package:muto_feature/src/domain/entities/listing_category.dart';
import 'package:muto_feature/src/domain/entities/listing_condition.dart';
import 'package:muto_feature/src/domain/entities/listing_kind.dart';
import 'package:muto_feature/src/domain/entities/money.dart';
import 'package:muto_feature/src/domain/entities/seller_contact.dart';
import 'package:muto_feature/src/domain/validation/contact_rules.dart';
import 'package:muto_feature/src/domain/validation/listing_rules.dart';
import 'package:muto_feature/src/domain/validation/text_rules.dart';

// built from code points so the test source stays readable
String _char(int codePoint) => String.fromCharCode(codePoint);

ListingDraft _draft({
  ListingKind kind = ListingKind.sale,
  String title = 'Calculus textbook',
  String description = 'Third edition, no marks',
  Money? price = const Money(minorUnits: 8000, currency: Currency.kzt),
  String? wantedItems,
  List<ImageRef> images = const [],
}) {
  return ListingDraft(
    kind: kind,
    title: title,
    description: description,
    condition: ListingCondition.good,
    category: ListingCategory.textbooks,
    images: images,
    price: price,
    wantedItems: wantedItems,
  );
}

void main() {
  group('TextRules', () {
    test('strips bidi overrides and zero-width marks', () {
      final crafted = 'Text${_char(0x202E)}book${_char(0x200B)}';
      expect(TextRules.normalizeLine(crafted), 'Textbook');
    });

    test('strips c0 and c1 control characters', () {
      final crafted = 'Lamp${_char(0x0007)}${_char(0x009F)}';
      expect(TextRules.normalizeLine(crafted), 'Lamp');
    });

    test('strips the byte order mark', () {
      expect(TextRules.normalizeLine('${_char(0xFEFF)}Chair'), 'Chair');
    });

    test('collapses runs of spaces and trims the edges', () {
      expect(TextRules.normalizeLine('  desk    lamp  '), 'desk lamp');
    });

    test('a single-line field loses its line breaks', () {
      expect(TextRules.normalizeLine('desk\nlamp'), 'desk lamp');
    });

    test('a multi-line field keeps paragraphs but caps blank runs', () {
      expect(TextRules.normalizeBlock('one\n\n\n\n\ntwo'), 'one\n\ntwo');
    });

    test('treats whitespace-only input as blank', () {
      expect(TextRules.isBlank('   '), isTrue);
      expect(TextRules.isBlank(_char(0x200B)), isTrue);
      expect(TextRules.isBlank(null), isTrue);
      expect(TextRules.isBlank('desk'), isFalse);
    });
  });

  group('ContactRules', () {
    test('accepts a telegram username with or without the at sign', () {
      expect(ContactRules.normalizeTelegramUsername('@nu_seller'), 'nu_seller');
      expect(ContactRules.normalizeTelegramUsername('nu_seller'), 'nu_seller');
    });

    test('rejects a telegram username of the wrong shape', () {
      expect(ContactRules.normalizeTelegramUsername('abc'), isNull);
      expect(ContactRules.normalizeTelegramUsername('has space'), isNull);
      expect(ContactRules.normalizeTelegramUsername('a' * 33), isNull);
      expect(ContactRules.normalizeTelegramUsername('drop;table'), isNull);
    });

    test('accepts a well-formed email and rejects a malformed one', () {
      expect(
        ContactRules.normalizeEmail(' student@nu.edu.kz '),
        'student@nu.edu.kz',
      );
      expect(ContactRules.normalizeEmail('student@nu'), isNull);
      expect(ContactRules.normalizeEmail('not an email'), isNull);
    });

    test('normalises a phone number to strict E.164', () {
      expect(ContactRules.normalizePhone('+7 (700) 123-45-67'), '+77001234567');
      expect(ContactRules.normalizePhone('87001234567'), isNull);
      expect(ContactRules.normalizePhone('+0123456789'), isNull);
    });

    test('sanitize drops every field that fails its shape check', () {
      const contact = SellerContact(
        telegramUsername: 'bad name',
        email: 'student@nu.edu.kz',
        phone: 'call me',
      );
      final sanitized = ContactRules.sanitize(contact);
      expect(sanitized.telegramUsername, isNull);
      expect(sanitized.email, 'student@nu.edu.kz');
      expect(sanitized.phone, isNull);
      expect(sanitized.isNotEmpty, isTrue);
    });

    test('an entirely invalid contact sanitises to empty', () {
      const contact = SellerContact(telegramUsername: 'no', phone: 'nope');
      expect(ContactRules.sanitize(contact).isEmpty, isTrue);
    });
  });

  group('ListingRules.validate', () {
    test('accepts a well-formed sale', () {
      expect(ListingRules.validate(_draft()).isValid, isTrue);
    });

    test('a sale must carry a price', () {
      final result = ListingRules.validate(_draft(price: null));
      expect(result.issues, contains(ListingIssue.priceMissing));
    });

    test('a sale priced at zero is out of range', () {
      final result = ListingRules.validate(
        _draft(price: const Money.zero(Currency.kzt)),
      );
      expect(result.issues, contains(ListingIssue.priceOutOfRange));
    });

    test('a sale above the currency bound is out of range', () {
      final result = ListingRules.validate(
        _draft(
          price: const Money(minorUnits: 50000001, currency: Currency.kzt),
        ),
      );
      expect(result.issues, contains(ListingIssue.priceOutOfRange));
    });

    test('a giveaway must not carry a price', () {
      final result = ListingRules.validate(_draft(kind: ListingKind.giveaway));
      expect(result.issues, contains(ListingIssue.priceNotAllowed));
    });

    test('an exchange must not carry a price', () {
      final result = ListingRules.validate(_draft(kind: ListingKind.exchange));
      expect(result.issues, contains(ListingIssue.priceNotAllowed));
    });

    test('wanted items belong to an exchange only', () {
      final onSale = ListingRules.validate(_draft(wantedItems: 'a monitor'));
      expect(onSale.issues, contains(ListingIssue.wantedItemsNotAllowed));

      final onExchange = ListingRules.validate(
        _draft(kind: ListingKind.exchange, price: null, wantedItems: 'monitor'),
      );
      expect(onExchange.isValid, isTrue);
    });

    test('enforces the title bounds', () {
      expect(
        ListingRules.validate(_draft(title: 'ab')).issues,
        contains(ListingIssue.titleTooShort),
      );
      expect(
        ListingRules.validate(_draft(title: 'a' * 81)).issues,
        contains(ListingIssue.titleTooLong),
      );
    });

    test('a title of only invisible characters is too short', () {
      final result = ListingRules.validate(_draft(title: _char(0x200B) * 10));
      expect(result.issues, contains(ListingIssue.titleTooShort));
    });

    test('enforces the description bound', () {
      final result = ListingRules.validate(_draft(description: 'x' * 2001));
      expect(result.issues, contains(ListingIssue.descriptionTooLong));
    });

    test('caps the number of images', () {
      final images = List.generate(
        7,
        (i) => ImageRef(id: 'img$i', version: 'v1'),
      );
      final result = ListingRules.validate(_draft(images: images));
      expect(result.issues, contains(ListingIssue.tooManyImages));
    });

    test('reports the field each issue belongs to', () {
      final result = ListingRules.validate(_draft(title: 'ab', price: null));
      expect(result.firstFor(ListingField.title), ListingIssue.titleTooShort);
      expect(result.firstFor(ListingField.price), ListingIssue.priceMissing);
      expect(result.firstFor(ListingField.images), isNull);
    });
  });

  group('ListingRules.normalize', () {
    test('drops a price the kind does not allow', () {
      final normalized = ListingRules.normalize(
        _draft(kind: ListingKind.giveaway),
      );
      expect(normalized.price, isNull);
      expect(ListingRules.validate(normalized).isValid, isTrue);
    });

    test('drops wanted items the kind does not allow', () {
      final normalized = ListingRules.normalize(
        _draft(wantedItems: 'a monitor'),
      );
      expect(normalized.wantedItems, isNull);
    });

    test('cleans the text fields', () {
      final normalized = ListingRules.normalize(
        _draft(title: '  Desk${_char(0x202E)}  lamp '),
      );
      expect(normalized.title, 'Desk lamp');
    });
  });
}
