/// Currencies the marketplace accepts.
///
/// Amounts are always held in the smallest indivisible unit, so a currency has
/// to declare how many decimal digits that unit represents. No conversion
/// happens between currencies anywhere in the app.
enum Currency {
  kzt(code: 'KZT', minorUnitDigits: 0, maxMinorUnits: 50000000),
  usd(code: 'USD', minorUnitDigits: 2, maxMinorUnits: 10000000);

  const Currency({
    required this.code,
    required this.minorUnitDigits,
    required this.maxMinorUnits,
  });

  /// ISO 4217 code, used as the stable wire value.
  final String code;

  /// 0 for tenge, 2 for cents.
  final int minorUnitDigits;

  /// Upper bound a listing price may take, guarding against absurd input.
  final int maxMinorUnits;

  static Currency? fromCode(String? code) {
    if (code == null) return null;
    final normalized = code.toUpperCase();
    for (final currency in Currency.values) {
      if (currency.code == normalized) return currency;
    }
    return null;
  }
}
