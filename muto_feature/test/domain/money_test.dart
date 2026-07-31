import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/src/domain/entities/currency.dart';
import 'package:muto_feature/src/domain/entities/money.dart';

void main() {
  group('Currency', () {
    test('declares the minor unit of each supported currency', () {
      expect(Currency.kzt.minorUnitDigits, 0);
      expect(Currency.usd.minorUnitDigits, 2);
    });

    test('resolves from a wire code case-insensitively', () {
      expect(Currency.fromCode('KZT'), Currency.kzt);
      expect(Currency.fromCode('usd'), Currency.usd);
    });

    test('rejects an unknown or absent code', () {
      expect(Currency.fromCode('EUR'), isNull);
      expect(Currency.fromCode(null), isNull);
    });
  });

  group('Money', () {
    test('holds the amount in minor units without formatting it', () {
      const price = Money(minorUnits: 12000, currency: Currency.kzt);
      expect(price.minorUnits, 12000);
      expect(price.currency, Currency.kzt);
    });

    test('treats identical amount and currency as equal', () {
      expect(
        const Money(minorUnits: 500, currency: Currency.usd),
        const Money(minorUnits: 500, currency: Currency.usd),
      );
      expect(
        const Money(minorUnits: 500, currency: Currency.usd),
        isNot(const Money(minorUnits: 500, currency: Currency.kzt)),
      );
    });

    test('reports whether the amount is within the currency bound', () {
      expect(
        const Money(
          minorUnits: 50000000,
          currency: Currency.kzt,
        ).isWithinBounds,
        isTrue,
      );
      expect(
        const Money(
          minorUnits: 50000001,
          currency: Currency.kzt,
        ).isWithinBounds,
        isFalse,
      );
    });

    test('orders amounts of the same currency', () {
      const cheap = Money(minorUnits: 1000, currency: Currency.kzt);
      const dear = Money(minorUnits: 9000, currency: Currency.kzt);
      expect(cheap.compareTo(dear), lessThan(0));
    });

    test('refuses to compare across currencies', () {
      const tenge = Money(minorUnits: 1000, currency: Currency.kzt);
      const dollars = Money(minorUnits: 1000, currency: Currency.usd);
      expect(() => tenge.compareTo(dollars), throwsArgumentError);
    });

    test('zero is the additive identity of its currency', () {
      const free = Money.zero(Currency.kzt);
      expect(free.isZero, isTrue);
      expect(free.minorUnits, 0);
    });
  });
}
