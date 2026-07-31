import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/muto_feature.dart';

Future<MutoLocalizations> _pumpAndRead(
  WidgetTester tester, {
  required Locale hostLocale,
}) async {
  late MutoLocalizations strings;
  await tester.pumpWidget(
    MaterialApp(
      locale: hostLocale,
      supportedLocales: const <Locale>[
        Locale('en'),
        Locale('kk'),
        Locale('ru'),
        Locale('de'),
      ],
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MutoLocalizationsScope(
        child: Builder(
          builder: (context) {
            strings = MutoLocalizations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return strings;
}

void main() {
  group('MutoLocales.resolve', () {
    test('keeps a supported language', () {
      expect(MutoLocales.resolve(const Locale('kk')), MutoLocales.kazakh);
      expect(MutoLocales.resolve(const Locale('ru')), MutoLocales.russian);
    });

    test('matches on language regardless of country', () {
      expect(
        MutoLocales.resolve(const Locale('ru', 'KZ')),
        MutoLocales.russian,
      );
    });

    test('falls back to English for an unsupported or absent locale', () {
      expect(MutoLocales.resolve(const Locale('de')), MutoLocales.english);
      expect(MutoLocales.resolve(null), MutoLocales.english);
    });
  });

  group('MutoLocalizationsScope', () {
    testWidgets('serves each supported language', (tester) async {
      final en = await _pumpAndRead(tester, hostLocale: const Locale('en'));
      expect(en.navBrowse, 'Browse');

      final kk = await _pumpAndRead(tester, hostLocale: const Locale('kk'));
      expect(kk.navBrowse, 'Каталог');
      expect(kk.navFavorites, 'Таңдаулылар');

      final ru = await _pumpAndRead(tester, hostLocale: const Locale('ru'));
      expect(ru.navMyListings, 'Мои объявления');
    });

    testWidgets('falls back to English when the host locale is unsupported', (
      tester,
    ) async {
      final strings = await _pumpAndRead(
        tester,
        hostLocale: const Locale('de'),
      );
      expect(strings.navBrowse, 'Browse');
    });

    testWidgets('applies Russian plural categories', (tester) async {
      final ru = await _pumpAndRead(tester, hostLocale: const Locale('ru'));
      expect(ru.listingCount(0), 'Нет объявлений');
      expect(ru.listingCount(1), '1 объявление');
      expect(ru.listingCount(3), '3 объявления');
      expect(ru.listingCount(7), '7 объявлений');
    });

    testWidgets('applies English plural categories', (tester) async {
      final en = await _pumpAndRead(tester, hostLocale: const Locale('en'));
      expect(en.listingCount(0), 'No listings');
      expect(en.listingCount(1), '1 listing');
      expect(en.listingCount(5), '5 listings');
    });
  });
}
