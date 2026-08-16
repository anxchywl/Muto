import 'dart:io';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

    testWidgets('names the page, not the seller, in the bar', (tester) async {
      await _openListing(tester, _lamp);
      await _openSeller(tester);

      expect(find.text('Seller info'), findsOneWidget);
      // the name belongs to the page, and is not repeated above it
      expect(find.text('Madina'), findsOneWidget);
    });

    testWidgets('says how to reach them, right on the page', (tester) async {
      final handle = tester.ensureSemantics();
      await _openListing(tester, _lamp);
      await _openSeller(tester);

      expect(find.text('How to reach'), findsOneWidget);
      // a row of text, not a button — the label reads "Telegram: @handle" in
      // one line, so the row is found by what it announces rather than by an
      // exact match on a standalone "Telegram"
      expect(
        find.bySemanticsLabel('Copy Telegram @sample_madina'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('copies the handle when a contact row is tapped', (
      tester,
    ) async {
      await _openListing(tester, _lamp);
      await _openSeller(tester);

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

      await tester.tap(find.textContaining('Telegram:'));
      await tester.pumpAndSettle();

      expect(copied, '@sample_madina');

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    });

    testWidgets('withholds the handles from an unverified student', (
      tester,
    ) async {
      await _openListing(
        tester,
        _lamp,
        viewer: const Identity(
          userId: 'usr_009',
          displayName: 'Aruzhan',
          isVerified: false,
        ),
      );
      await _openSeller(tester);

      expect(find.text('How to reach them'), findsNothing);
      expect(
        find.bySemanticsLabel('Copy Telegram @sample_madina'),
        findsNothing,
      );
      expect(
        find.text('Verify your student account to see contact details.'),
        findsWidgets,
      );
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

      // the detail screen has no title bar of its own; its seller card is
      // what says we are looking at one listing rather than a profile
      expect(find.text('Seller'), findsOneWidget);
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

      expect(find.text(_lamp), findsWidgets);
      expect(find.text('Seller'), findsOneWidget);
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
    });

    testWidgets('sends once a reason is written, and says so', (tester) async {
      await _openListing(tester, _lamp);

      await tester.tap(find.byTooltip('Report this listing'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'the listing is not what it claims to be',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send report'));
      await tester.pumpAndSettle();

      // the flag button turns into a tick that says so, rather than a toast
      expect(find.byTooltip('Report sent'), findsOneWidget);
      expect(find.byTooltip('Report this listing'), findsNothing);

      await _settleToast(tester);

      // and quietly goes back to offering the action again
      expect(find.byTooltip('Report this listing'), findsOneWidget);
    });

    testWidgets('keeps sending disabled until a note is written', (
      tester,
    ) async {
      await _openListing(tester, _lamp);

      await tester.tap(find.byTooltip('Report this listing'));
      await tester.pumpAndSettle();

      // nothing written yet: the button offers no action to tap
      final sendButton = find.ancestor(
        of: find.text('Send report'),
        matching: find.byType(AppPrimaryButton),
      );
      expect(tester.widget<AppPrimaryButton>(sendButton).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'wrong price listed');
      await tester.pumpAndSettle();

      expect(tester.widget<AppPrimaryButton>(sendButton).onPressed, isNotNull);
    });

    testWidgets('keeps the sheet open and explains when it cannot send', (
      tester,
    ) async {
      final faults = MockFaults();
      await _openListing(tester, _lamp, faults: faults);

      await tester.tap(find.byTooltip('Report this listing'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'this is not allowed');
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
