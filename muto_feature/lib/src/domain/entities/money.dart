import 'currency.dart';

/// An amount held in the smallest indivisible unit of its currency — tenge for
/// KZT, cents for USD.
///
/// Money is never stored or passed around as a formatted string; presentation
/// formats it for the active locale at the moment it is drawn.
final class Money implements Comparable<Money> {
  const Money({required this.minorUnits, required this.currency})
    : assert(minorUnits >= 0, 'a listing amount cannot be negative');

  const Money.zero(this.currency) : minorUnits = 0;

  final int minorUnits;
  final Currency currency;

  bool get isZero => minorUnits == 0;

  bool get isWithinBounds =>
      minorUnits >= 0 && minorUnits <= currency.maxMinorUnits;

  /// Comparison across currencies is meaningless without a conversion rate,
  /// which v1 deliberately does not have.
  @override
  int compareTo(Money other) {
    if (other.currency != currency) {
      throw ArgumentError(
        'cannot compare ${currency.code} with ${other.currency.code}',
      );
    }
    return minorUnits.compareTo(other.minorUnits);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Money &&
          other.minorUnits == minorUnits &&
          other.currency == currency;

  @override
  int get hashCode => Object.hash(minorUnits, currency);

  @override
  String toString() => 'Money($minorUnits ${currency.code})';
}
