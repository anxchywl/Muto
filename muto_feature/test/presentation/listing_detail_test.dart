import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/muto_feature.dart';
import 'package:muto_feature/src/data/mock/mock_environment.dart';
import 'package:muto_feature/src/data/mock/sample_data.dart';
import 'package:muto_feature/src/data/mock/sample_dependencies.dart';
import 'package:muto_feature/src/domain/entities/identity.dart';
import 'package:muto_feature/src/domain/entities/listing_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('opens a listing from the feed', (tester) async {
    await _openListing(tester, 'Small study lamp, clip-on');

    expect(find.text('Small study lamp, clip-on'), findsWidgets);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Seller'), findsOneWidget);
    expect(find.text('Madina'), findsOneWidget);
    expect(find.text('29.07.2026'), findsOneWidget);
  });

  testWidgets('offers contact to a verified student', (tester) async {
    await _openListing(tester, 'Small study lamp, clip-on');
    // the contact bar pinned at the foot of the screen, one button per channel
    expect(find.text('Telegram'), findsOneWidget);
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

    expect(find.text('Telegram'), findsNothing);
    expect(
      find.text('Verify your student account to see contact details.'),
      findsOneWidget,
    );
  });

  testWidgets('says which handle the contact button copies', (tester) async {
    final handle = tester.ensureSemantics();
    await _openListing(tester, 'Small study lamp, clip-on');

    // the button shows only the channel, so the handle it puts on the
    // clipboard has to reach a screen reader some other way
    expect(
      find.bySemanticsLabel('Copy Telegram @sample_madina'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('opens the chat as well as copying the handle', (tester) async {
    await _openListing(tester, 'Small study lamp, clip-on');

    final launched = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async {
        if (call.method == 'launch' || call.method == 'launchUrl') {
          launched.add((call.arguments as Map)['url'] as String);
        }
        // 'canLaunch' and the rest answer yes so the plugin gets as far as
        // trying, which is the part under test
        return true;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'),
        null,
      ),
    );

    await tester.tap(find.text('Telegram'));
    await tester.pumpAndSettle();

    expect(launched, ['https://t.me/sample_madina']);
    // and the handle is on the clipboard either way
    expect(find.text('Copied'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('copies a contact channel when its button is tapped', (
    tester,
  ) async {
    await _openListing(tester, 'Small study lamp, clip-on');

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.tap(find.text('Telegram'));
    await tester.pumpAndSettle();

    expect(copied, '@sample_madina');
    // the button says so itself rather than raising a toast over the listing
    expect(find.text('Copied'), findsOneWidget);

    // the button holds a timer to change back, which the test has to let expire
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Telegram'), findsOneWidget);
  });

  testWidgets('a second channel copies from its own compact button', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _openListing(tester, 'One spare ticket, student orchestra concert');

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    // only the first channel carries a label; the rest are squares beside it
    expect(find.text('Email'), findsNothing);
    await tester.tap(
      find.bySemanticsLabel('Copy Email sample.seller.02@example.edu'),
    );
    await tester.pumpAndSettle();

    expect(copied, 'sample.seller.02@example.edu');

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    handle.dispose();
  });

  testWidgets('an exchange says what the seller is looking for', (
    tester,
  ) async {
    await _openListing(tester, 'Акустическая гитара, меняю');

    expect(find.text('Looking for'), findsOneWidget);
    expect(find.text('Микрофон или аудиоинтерфейс'), findsOneWidget);
    expect(find.text('Open to swaps'), findsWidgets);
  });

  testWidgets('a reserved listing is visibly inactive', (tester) async {
    final reserved = _data.listings.firstWhere(
      (listing) => listing.status == ListingStatus.reserved,
    );

    await _openListing(
      tester,
      reserved.title,
      data: SampleData(viewer: _data.viewer, listings: [reserved]),
    );

    expect(find.text('This item is reserved for someone else.'), findsNothing);
    expect(find.text(reserved.title), findsOneWidget);
  });

  testWidgets('translates the detail screen', (tester) async {
    await _openListing(
      tester,
      'Small study lamp, clip-on',
      locale: const Locale('ru'),
    );

    expect(find.text('Описание'), findsOneWidget);
    expect(find.text('Продавец'), findsOneWidget);
    // the controls floating over the photo carry no visible words, so their
    // tooltips are the only place their translation shows
    expect(find.byTooltip('Пожаловаться на объявление'), findsOneWidget);
  });
}
