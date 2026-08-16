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
import 'package:muto_feature/src/data/mock/mock_report_operations_repository.dart';
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

  testWidgets('gives the feed the whole surface above the tabs', (
    tester,
  ) async {
    await _pumpFeature(tester);

    expect(find.text('Sample data'), findsNothing);
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

  testWidgets('swaps the feed between rows and tiles', (tester) async {
    await _pumpFeature(tester, logicalSize: const Size(400, 800));

    expect(find.byType(ListingCard), findsWidgets);
    expect(find.byType(ListingGridTile), findsNothing);

    // the layout pill sits at the end of the strip, past the filters — bring
    // it on screen the way a reader's own swipe would
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Show as a grid'));
    await tester.pumpAndSettle();

    // the same listings, drawn the other way — nothing was re-fetched
    expect(find.byType(ListingGridTile), findsWidgets);
    expect(find.byType(ListingCard), findsNothing);
    expect(find.text('Small study lamp, clip-on'), findsOneWidget);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Show as a list'));
    await tester.pumpAndSettle();

    expect(find.byType(ListingCard), findsWidgets);
    expect(find.byType(ListingGridTile), findsNothing);
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
      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, -600),
      );
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
    expect(find.text('Бесплатно'), findsWidgets);
  });

  testWidgets('translates the whole surface into Kazakh', (tester) async {
    await _pumpFeature(tester, locale: const Locale('kk'));

    expect(find.text('Таңдаулылар'), findsOneWidget);
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

    // 'Browse' also names the header now sitting above the feed, so this one
    // is only meaningfully absent, not meaningfully singular
    for (final label in ['Favorites', 'My listings']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    expect(find.bySemanticsLabel('Browse'), findsWidgets);
    handle.dispose();
  });

  group('filters', () {
    testWidgets('narrows the feed to one category', (tester) async {
      await _pumpFeature(tester);

      await tester.tap(find.text('Category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Textbooks'));
      await tester.pumpAndSettle();

      expect(find.text('University Physics, volume 1'), findsOneWidget);
      expect(find.text('Small study lamp, clip-on'), findsNothing);
    });

    testWidgets('narrows the feed to giveaways from the type pill', (
      tester,
    ) async {
      await _pumpFeature(tester);

      await tester.tap(find.text('Type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Free').last);
      await tester.pumpAndSettle();

      expect(find.text('Free'), findsWidgets);
      expect(find.text('University Physics, volume 1'), findsNothing);
    });

    testWidgets('the cross on a pill lets go of what it narrowed to', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpFeature(tester);

      await tester.tap(find.text('Category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Textbooks'));
      await tester.pumpAndSettle();
      expect(find.text('Small study lamp, clip-on'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Clear Category'));
      await tester.pumpAndSettle();

      expect(find.text('Category'), findsOneWidget);
      expect(find.text('Small study lamp, clip-on'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('offers no cross until a pill narrows something', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpFeature(tester);

      expect(find.bySemanticsLabel('Clear Category'), findsNothing);
      expect(find.bySemanticsLabel('Clear Type'), findsNothing);
      expect(find.bySemanticsLabel('Clear Condition'), findsNothing);
      handle.dispose();
    });

    testWidgets('the pill names what it is narrowed to', (tester) async {
      await _pumpFeature(tester);

      await tester.tap(find.text('Condition'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Like new').last);
      await tester.pumpAndSettle();

      expect(find.text('Condition'), findsNothing);
      expect(find.text('Like new'), findsWidgets);
    });

    testWidgets('says so when nothing matches', (tester) async {
      await _pumpFeature(tester);

      await tester.tap(find.text('Category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tickets'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Swap').last);
      await tester.pumpAndSettle();

      expect(find.text('Nothing here yet'), findsOneWidget);
    });

    testWidgets('sorts by price without leaving the feed', (tester) async {
      await _pumpFeature(tester);

      await tester.tap(find.bySemanticsLabel('Sort'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Price, low to high'));
      await tester.pumpAndSettle();

      expect(find.byType(ListingCard), findsWidgets);
      // the pill stays highlighted, which is the only sign a sort is applied
      expect(find.text('Price, low to high'), findsNothing);
    });

    testWidgets('translates the pills and their sheets', (tester) async {
      await _pumpFeature(tester, locale: const Locale('kk'));

      await tester.tap(find.text('Түрі'));
      await tester.pumpAndSettle();

      expect(find.text('Сатылады'), findsOneWidget);
      expect(find.text('Тегін'), findsWidgets);
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
        reportOperations: const MockReportOperationsRepository(),
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
