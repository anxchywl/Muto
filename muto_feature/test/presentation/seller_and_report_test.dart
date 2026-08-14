import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/muto_feature.dart';
import 'package:muto_feature/src/data/mock/mock_environment.dart';
import 'package:muto_feature/src/data/mock/sample_data.dart';
import 'package:muto_feature/src/data/mock/sample_dependencies.dart';
import 'package:muto_feature/src/domain/entities/identity.dart';
import 'package:muto_ui/muto_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

late SampleData _data;

/// The seller of the lamp, so the same listing can be opened as its owner and
/// as anyone else.
const Identity _madina = Identity(
  userId: 'usr_004',
  displayName: 'Madina',
  isVerified: true,
);

const String _lamp = 'Small study lamp, clip-on';

/// Madina's other listing, reserved rather than sold.
const String _bicycle = 'Велосипед горный, 26 дюймов';

Future<void> _openListing(
  WidgetTester tester,
  String title, {
  Identity? viewer,
  MockFaults? faults,
}) async {
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
          SampleData(viewer: viewer ?? _data.viewer, listings: _data.listings),
          latency: const MockLatency.none(),
          faults: faults,
        ),
        config: const MutoConfig.sample(),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

Future<void> _openSeller(WidgetTester tester) async {
  await tester.tap(find.text('Madina').last);
  await tester.pumpAndSettle();
}

/// A toast holds a timer of its own, which a test has to let expire.
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

  group('seller profile', () {
    testWidgets('opens from the listing and says who the seller is', (
      tester,
    ) async {
      await _openListing(tester, _lamp);
      await _openSeller(tester);

      expect(find.text('Madina'), findsWidgets);
    });

    testWidgets('lists what else they have, and not what they sold', (
      tester,
    ) async {
      await _openListing(tester, _lamp);
      await _openSeller(tester);

      expect(find.text(_bicycle), findsOneWidget);
      expect(find.text('Winter jacket, size M'), findsNothing);
    });

    testWidgets('opens a listing from the profile', (tester) async {
      await _openListing(tester, _lamp);
      await _openSeller(tester);

      await tester.tap(find.byType(ListingCard).first);
      await tester.pumpAndSettle();

      expect(find.text('Listing'), findsOneWidget);
    });

    testWidgets('keeps the name on screen when the profile cannot load', (
      tester,
    ) async {
      final faults = MockFaults();
      await _openListing(tester, _lamp, faults: faults);

      faults.offline = true;
      await _openSeller(tester);

      expect(find.text('Madina'), findsWidgets);
      expect(find.text('Could not load this seller.'), findsOneWidget);
    });

    testWidgets('names where the seller row leads', (tester) async {
      final handle = tester.ensureSemantics();
      await _openListing(tester, _lamp);

      expect(find.bySemanticsLabel("Open Madina's listings"), findsOneWidget);
      handle.dispose();
    });

    testWidgets('goes back to the listing it came from', (tester) async {
      await _openListing(tester, _lamp);
      await _openSeller(tester);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Listing'), findsOneWidget);
    });
  });

  group('reporting', () {
    testWidgets('is offered on someone else\'s listing', (tester) async {
      await _openListing(tester, _lamp);

      expect(find.byTooltip('Report this listing'), findsOneWidget);
    });

    testWidgets('is never offered on your own', (tester) async {
      await _openListing(tester, _lamp, viewer: _madina);

      expect(find.byTooltip('Report this listing'), findsNothing);
      expect(find.text('Your listing'), findsOneWidget);
    });

    testWidgets('sends once a reason is chosen, and says so', (tester) async {
      await _openListing(tester, _lamp);

      await tester.tap(find.byTooltip('Report this listing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Misleading'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send report'));
      await tester.pumpAndSettle();

      expect(find.text('Report sent'), findsOneWidget);
      await _settleToast(tester);
    });

    testWidgets('asks for a note when the reason does not say enough', (
      tester,
    ) async {
      await _openListing(tester, _lamp);

      await tester.tap(find.byTooltip('Report this listing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Something else'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send report'));
      await tester.pumpAndSettle();

      expect(
        find.text('Say briefly what is wrong with this listing.'),
        findsOneWidget,
      );
    });

    testWidgets('keeps the sheet open and explains when it cannot send', (
      tester,
    ) async {
      final faults = MockFaults();
      await _openListing(tester, _lamp, faults: faults);

      await tester.tap(find.byTooltip('Report this listing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not allowed'));
      await tester.pumpAndSettle();

      faults.offline = true;
      await tester.tap(find.text('Send report'));
      await tester.pumpAndSettle();

      expect(
        find.text('No connection. Check your network and try again.'),
        findsOneWidget,
      );
      expect(find.text('Send report'), findsOneWidget);
    });
  });
}
