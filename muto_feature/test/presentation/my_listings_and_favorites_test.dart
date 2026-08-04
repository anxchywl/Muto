import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/muto_feature.dart';
import 'package:muto_feature/src/data/mock/mock_environment.dart';
import 'package:muto_feature/src/data/mock/sample_data.dart';
import 'package:muto_feature/src/data/mock/sample_dependencies.dart';
import 'package:muto_feature/src/domain/entities/listing_status.dart';
import 'package:muto_ui/muto_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

late SampleData _data;

Future<void> _pump(WidgetTester tester, {SampleData? data}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
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
          data ?? _data,
          latency: const MockLatency.none(),
        ),
        config: const MutoConfig.sample(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel(label).last);
  await tester.pumpAndSettle();
}

Future<void> _settleToast(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    _data = SampleData.decode(
      File('assets/sample/listings.json').readAsStringSync(),
    );
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('favorites', () {
    testWidgets('starts empty and says so', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      await _openTab(tester, 'Favorites');

      expect(find.text('Nothing saved yet'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('saving from the feed puts a listing in favorites', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      await tester.tap(find.bySemanticsLabel('Save listing').first);
      await tester.pumpAndSettle();

      await _openTab(tester, 'Favorites');
      expect(find.byType(ListingCard), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the heart reflects what is saved', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      expect(find.bySemanticsLabel('Remove from saved'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Save listing').first);
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Remove from saved'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('unsaving puts the heart back', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      await tester.tap(find.bySemanticsLabel('Save listing').first);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Remove from saved').first);
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Remove from saved'), findsNothing);
      handle.dispose();
    });
  });

  group('my listings', () {
    testWidgets('shows what the student has published', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      await _openTab(tester, 'My listings');

      expect(find.text('University Physics, volume 1'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('includes sold and hidden listings the feed hides', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      await _openTab(tester, 'My listings');

      expect(find.text('Кроссовки для зала, 41 размер'), findsOneWidget);
      expect(find.text('Old wifi router, still works'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('offers no heart on your own listings', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      await _openTab(tester, 'My listings');

      expect(find.bySemanticsLabel('Save listing'), findsNothing);
      handle.dispose();
    });
  });

  group('owner actions', () {
    testWidgets('offers only the moves the rules allow', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      await _openTab(tester, 'My listings');

      await tester.tap(find.text('University Physics, volume 1'));
      await tester.pumpAndSettle();

      // an active listing can be reserved, sold, hidden or removed
      expect(find.text('Your listing'), findsOneWidget);
      expect(find.text('Mark as reserved'), findsOneWidget);
      expect(find.text('Mark as sold'), findsOneWidget);
      expect(find.text('Hide'), findsOneWidget);
      expect(find.text('Remove listing'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a sold listing offers relisting, not reserving', (
      tester,
    ) async {
      final sold = _data.listings.firstWhere(
        (listing) =>
            listing.status == ListingStatus.sold &&
            listing.sellerId == _data.viewer.userId,
      );

      final handle = tester.ensureSemantics();
      await _pump(tester);
      await _openTab(tester, 'My listings');

      await tester.tap(find.text(sold.title));
      await tester.pumpAndSettle();

      expect(find.text('Make available again'), findsOneWidget);
      expect(find.text('Mark as reserved'), findsNothing);
      expect(
        find.text('Edit'),
        findsNothing,
        reason: 'a sold listing is not editable',
      );
      handle.dispose();
    });

    testWidgets('a sold listing offers no way to contact its seller', (
      tester,
    ) async {
      final sold = _data.listings.firstWhere(
        (listing) =>
            listing.status == ListingStatus.sold &&
            listing.sellerId == _data.viewer.userId,
      );

      final handle = tester.ensureSemantics();
      await _pump(tester);
      await _openTab(tester, 'My listings');

      await tester.tap(find.text(sold.title));
      await tester.pumpAndSettle();

      expect(find.text('This item has been sold.'), findsOneWidget);
      expect(find.text('Contact seller'), findsNothing);
      handle.dispose();
    });

    testWidgets('marking a listing reserved applies it', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      await _openTab(tester, 'My listings');

      await tester.tap(find.text('University Physics, volume 1'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mark as reserved'));
      await _settleToast(tester);

      expect(find.text('Reserved'), findsWidgets);
      handle.dispose();
    });

    testWidgets('removing asks first and cannot be done by accident', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      await _openTab(tester, 'My listings');

      await tester.tap(find.text('University Physics, volume 1'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove listing'));
      await tester.pumpAndSettle();

      expect(find.text('Remove this listing?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Your listing'), findsOneWidget);
      handle.dispose();
    });
  });
}
