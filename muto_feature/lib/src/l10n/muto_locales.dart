import 'package:flutter/widgets.dart';

/// Locales the marketplace ships translations for.
///
/// A host application may run in any locale. Anything outside this set falls
/// back to English rather than rendering message keys.
abstract final class MutoLocales {
  static const Locale english = Locale('en');
  static const Locale kazakh = Locale('kk');
  static const Locale russian = Locale('ru');

  static const List<Locale> supported = <Locale>[english, kazakh, russian];

  static const Locale fallback = english;

  static Locale resolve(Locale? hostLocale) {
    if (hostLocale == null) return fallback;
    for (final locale in supported) {
      if (locale.languageCode == hostLocale.languageCode) return locale;
    }
    return fallback;
  }
}
