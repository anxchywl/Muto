import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/muto_feature.dart';
import 'package:muto_feature/src/data/mock/mock_environment.dart';
import 'package:muto_feature/src/data/mock/sample_data.dart';
import 'package:muto_feature/src/data/mock/sample_dependencies.dart';
import 'package:muto_feature/src/domain/entities/identity.dart';
import 'package:muto_feature/src/domain/entities/listing_status.dart';
import 'package:muto_ui/muto_ui.dart';

late SampleData _data;

SampleData _viewedBy(Identity viewer) =>
    SampleData(viewer: viewer, listings: _data.listings);

Future<void> _openListing(
  WidgetTester tester,
  String title, {
  SampleData? data,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
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
        dependencies: buildSampleDependencies(
          data ?? _data,
          latency: const MockLatency.none(),
        ),
        config: const MutoConfig.sample(),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    _data = SampleData.decode(
      File('assets/sample/listings.json').readAsStringSync(),
    );
  });

  testWidgets('opens a listing from the feed', (tester) async {
    await _openListing(tester, 'Small study lamp, clip-on');

    expect(find.text('Listing'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Seller'), findsOneWidget);
    expect(find.text('Madina'), findsOneWidget);
  });

  testWidgets('offers contact to a verified student', (tester) async {
    await _openListing(tester, 'Small study lamp, clip-on');
    expect(find.text('Contact seller'), findsOneWidget);
  });

  testWidgets('withholds contact from an unverified student', (tester) async {
    await _openListing(
      tester,
      'Small study lamp, clip-on',
      data: _viewedBy(
        const Identity(
          userId: 'usr_001',
          displayName: 'Aruzhan',
          isVerified: false,
        ),
      ),
    );

    expect(find.text('Contact seller'), findsNothing);
    expect(
      find.text('Verify your student account to see contact details.'),
      findsOneWidget,
    );
  });

  testWidgets('shows the seller contact only after asking', (tester) async {
    await _openListing(tester, 'Small study lamp, clip-on');

    // the detail screen itself never prints the contact
    expect(find.textContaining('@sample_madina'), findsNothing);

    await tester.tap(find.text('Contact seller'));
    await tester.pumpAndSettle();

    expect(find.text('@sample_madina'), findsOneWidget);
    expect(find.text('Telegram'), findsOneWidget);
  });

  testWidgets('names the destination before leaving the app', (tester) async {
    await _openListing(tester, 'Small study lamp, clip-on');
    await tester.tap(find.text('Contact seller'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open').first);
    await tester.pumpAndSettle();

    expect(find.text('Open outside Muto?'), findsOneWidget);
    expect(find.textContaining('https://t.me/sample_madina'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('an exchange says what the seller is looking for', (
    tester,
  ) async {
    await _openListing(tester, 'Акустическая гитара, меняю');

    expect(find.text('Looking for'), findsOneWidget);
    expect(find.text('Микрофон или аудиоинтерфейс'), findsOneWidget);
    expect(find.text('Open to swaps'), findsWidgets);
  });

  testWidgets('a reserved listing says so plainly', (tester) async {
    final reserved = _data.listings.firstWhere(
      (listing) => listing.status == ListingStatus.reserved,
    );

    await _openListing(
      tester,
      reserved.title,
      data: SampleData(viewer: _data.viewer, listings: [reserved]),
    );

    expect(
      find.text('This item is reserved for someone else.'),
      findsOneWidget,
    );
  });

  testWidgets('translates the detail screen', (tester) async {
    await _openListing(
      tester,
      'Small study lamp, clip-on',
      locale: const Locale('ru'),
    );

    expect(find.text('Объявление'), findsOneWidget);
    expect(find.text('Описание'), findsOneWidget);
    expect(find.text('Продавец'), findsOneWidget);
    expect(find.text('Связаться с продавцом'), findsOneWidget);
  });

  testWidgets('an image that cannot resolve still renders the screen', (
    tester,
  ) async {
    // this listing points at an image id the bundle does not contain
    await _openListing(tester, 'Small study lamp, clip-on');

    expect(find.byType(ListingImage), findsWidgets);
    expect(find.text('Small study lamp, clip-on'), findsWidgets);
  });
}
