import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/muto_feature.dart';
import 'package:muto_feature/src/data/local/preferences_draft_store.dart';
import 'package:muto_feature/src/data/mock/mock_environment.dart';
import 'package:muto_feature/src/data/mock/mock_favorites_repository.dart';
import 'package:muto_feature/src/data/mock/mock_image_repository.dart';
import 'package:muto_feature/src/data/mock/mock_listing_repository.dart';
import 'package:muto_feature/src/data/mock/mock_report_repository.dart';
import 'package:muto_feature/src/data/mock/mock_seller_repository.dart';
import 'package:muto_feature/src/data/mock/mock_session_repository.dart';
import 'package:muto_feature/src/data/mock/sample_data.dart';
import 'package:muto_feature/src/data/mock/sample_dependencies.dart';
import 'package:muto_ui/muto_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_search_history_store.dart';

late SampleData _data;

Future<void> _pumpFeature(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  MockFaults? faults,
  MutoDependencies? dependencies,
  Size logicalSize = const Size(1200, 2400),
}) async {
  tester.view.physicalSize = logicalSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: MutoLocales.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        MutoLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MutoFeature(
        session: const MutoHostSession(accessToken: 'test-session'),
        dependencies:
            dependencies ??
            buildSampleDependencies(
              _data,
              latency: const MockLatency.none(),
              faults: faults,
            ),
        config: const MutoConfig.sample(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    _data = SampleData.decode(
      File('assets/sample/listings.json').readAsStringSync(),
    );
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('resolves a session and shows the feed', (tester) async {
    await _pumpFeature(tester);

    expect(find.byType(ListingCard), findsWidgets);
    expect(find.text('Small study lamp, clip-on'), findsOneWidget);
  });

  testWidgets('says plainly that it is running on sample data', (tester) async {
    await _pumpFeature(tester);

    expect(find.byType(SampleDataBanner), findsOneWidget);
    expect(find.text('Sample data'), findsOneWidget);
  });

  testWidgets('shows a price with its currency, in the reader\'s locale', (
    tester,
  ) async {
    await _pumpFeature(tester);

    // tenge has no minor unit, dollars do
    expect(find.textContaining('₸'), findsWidgets);
    expect(find.textContaining(r'$'), findsWidgets);
  });

  testWidgets('shows a giveaway without inventing a price', (tester) async {
    await _pumpFeature(tester);
    expect(find.text('Free'), findsWidgets);
  });

  testWidgets('loads the next page when the feed is scrolled', (tester) async {
    // a phone-sized viewport, so the feed genuinely has somewhere to scroll
    await _pumpFeature(tester, logicalSize: const Size(400, 800));

    // the oldest listings sit on the second page
    expect(
      find.text('Calculus: Early Transcendentals, 8th edition'),
      findsNothing,
    );

    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -600));
      await tester.pumpAndSettle();
    }

    expect(
      find.text('Calculus: Early Transcendentals, 8th edition'),
      findsOneWidget,
    );
    expect(find.text('Reserved'), findsWidgets);
  });

  testWidgets('never shows a sold or removed listing in the feed', (
    tester,
  ) async {
    await _pumpFeature(tester);

    expect(find.text('Winter jacket, size M'), findsNothing);
    expect(find.text('Kettle, taken down by the seller'), findsNothing);
  });

  testWidgets('never shows another student a hidden listing', (tester) async {
    await _pumpFeature(tester);
    expect(find.text('Old wifi router, still works'), findsNothing);
  });

  testWidgets('translates the whole surface into Russian', (tester) async {
    await _pumpFeature(tester, locale: const Locale('ru'));

    expect(find.text('Каталог'), findsWidgets);
    expect(find.text('Избранное'), findsOneWidget);
    expect(find.text('Тестовые данные'), findsOneWidget);
    expect(find.text('Бесплатно'), findsWidgets);
  });

  testWidgets('translates the whole surface into Kazakh', (tester) async {
    await _pumpFeature(tester, locale: const Locale('kk'));

    expect(find.text('Таңдаулылар'), findsOneWidget);
    expect(find.text('Сынақ деректері'), findsOneWidget);
    expect(find.text('Тегін'), findsWidgets);
  });

  testWidgets('announces each listing as one thing to a screen reader', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpFeature(tester);

    expect(
      find.bySemanticsLabel(RegExp('Small study lamp, clip-on, .*')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('gives every navigation destination a label', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpFeature(tester);

    for (final label in ['Browse', 'Favorites', 'My listings']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    handle.dispose();
  });

  group('filters', () {
    testWidgets('narrows the feed to one category', (tester) async {
      await _pumpFeature(tester);

      await tester.tap(find.byTooltip('Open filters'));
      await tester.pumpAndSettle();
      expect(find.text('Filters'), findsOneWidget);

      await tester.tap(find.text('Textbooks').last);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.text('University Physics, volume 1'), findsOneWidget);
      expect(find.text('Small study lamp, clip-on'), findsNothing);
    });

    testWidgets('narrows the feed to giveaways', (tester) async {
      await _pumpFeature(tester);

      await tester.tap(find.byTooltip('Open filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Free').last);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.text('Free'), findsWidgets);
      expect(find.text('University Physics, volume 1'), findsNothing);
    });

    testWidgets('says so when nothing matches', (tester) async {
      await _pumpFeature(tester);

      await tester.tap(find.byTooltip('Open filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tickets').last);
      await tester.tap(find.text('Swap').last);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing here yet'), findsOneWidget);
    });

    testWidgets('resetting brings everything back', (tester) async {
      await _pumpFeature(tester);

      await tester.tap(find.byTooltip('Open filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Textbooks').last);
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.text('Small study lamp, clip-on'), findsOneWidget);
    });

    testWidgets('translates the filter sheet', (tester) async {
      await _pumpFeature(tester, locale: const Locale('kk'));

      await tester.tap(find.byTooltip('Сүзгілерді ашу'));
      await tester.pumpAndSettle();

      expect(find.text('Сүзгілер'), findsOneWidget);
      expect(find.text('Оқулықтар'), findsOneWidget);
      expect(find.text('Қолдану'), findsOneWidget);
    });
  });

  testWidgets('being offline at startup fails the session, not the feed', (
    tester,
  ) async {
    await _pumpFeature(tester, faults: MockFaults()..offline = true);

    expect(find.text('Could not start Muto'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('offers a retry when only the feed cannot load', (tester) async {
    // the session resolves, the listing source does not
    final listingFaults = MockFaults()..offline = true;
    final listings = MockListingRepository(
      seed: _data.listings,
      viewer: () => _data.viewer,
      latency: const MockLatency.none(),
      faults: listingFaults,
    );
    final store = StagedImageStore();

    await _pumpFeature(
      tester,
      dependencies: MutoDependencies(
        session: MockSessionRepository(
          identity: _data.viewer,
          latency: const MockLatency.none(),
        ),
        listings: listings,
        sellers: MockSellerRepository(
          source: () => listings.all,
          latency: const MockLatency.none(),
          faults: listingFaults,
        ),
        favorites: MockFavoritesRepository(
          listings: listings,
          latency: const MockLatency.none(),
          faults: listingFaults,
        ),
        reports: MockReportRepository(
          viewer: () => _data.viewer,
          latency: const MockLatency.none(),
        ),
        images: MockImageRepository(
          store: store,
          latency: const MockLatency.none(),
        ),
        imageLocator: MockImageLocator(store: store, bundled: const {}),
        drafts: const PreferencesDraftStore(),
        searchHistory: FakeSearchHistoryStore(),
      ),
    );

    expect(find.text('Could not load listings'), findsOneWidget);
    expect(
      find.text('No connection. Check your network and try again.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('shows the expired screen when the session is gone', (
    tester,
  ) async {
    await _pumpFeature(tester, faults: MockFaults()..sessionExpired = true);

    expect(find.text('Session expired'), findsOneWidget);
    expect(find.byType(ListingCard), findsNothing);
  });

  testWidgets('renders in dark theme without losing its content', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        supportedLocales: MutoLocales.supported,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          MutoLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MutoFeature(
          session: const MutoHostSession(accessToken: 'test-session'),
          dependencies: buildSampleDependencies(
            _data,
            latency: const MockLatency.none(),
          ),
          config: const MutoConfig.sample(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ListingCard), findsWidgets);
  });
}
