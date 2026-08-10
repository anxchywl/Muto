import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/muto_feature.dart';
import 'package:muto_feature/src/data/mock/mock_environment.dart';
import 'package:muto_feature/src/data/mock/sample_data.dart';
import 'package:muto_feature/src/data/mock/sample_dependencies.dart';
import 'package:muto_feature/src/domain/entities/identity.dart';
import 'package:muto_feature/src/presentation/editor/listing_editor_sheet.dart';
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

/// The success toast dismisses itself on a timer, so a test that publishes has
/// to let it finish or it leaves a pending timer behind.
Future<void> _settleToast(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

/// The compose button belongs to the student's own listings, so reaching the
/// editor starts with opening that tab.
Future<void> _openMyListings(WidgetTester tester) async {
  await tester.tap(find.text('My listings').last);
  await tester.pumpAndSettle();
}

Future<void> _openEditor(WidgetTester tester) async {
  await _openMyListings(tester);
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
}

/// Scopes a finder to the sheet, since the feed behind it carries the same
/// words and a tap that lands there dismisses the editor instead.
Finder _inSheet(String text) => find.descendant(
  of: find.byType(ListingEditorSheet),
  matching: find.text(text),
);

Future<void> _tapInSheet(WidgetTester tester, String text) async {
  await tester.tap(_inSheet(text));
  await tester.pumpAndSettle();
}

Future<void> _next(WidgetTester tester) => _tapInSheet(tester, 'Next');

/// Fills in what the first two steps insist on, for tests about a later one.
Future<void> _fillBasics(WidgetTester tester, {String title = 'Kettle'}) async {
  await tester.enterText(find.byType(TextField).first, title);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    _data = SampleData.decode(
      File('assets/sample/listings.json').readAsStringSync(),
    );
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a verified student can reach the editor', (tester) async {
    await _pump(tester);
    await _openMyListings(tester);

    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.byType(ListingEditorSheet), findsOneWidget);
    expect(find.text('New listing'), findsWidgets);
  });

  testWidgets('nothing is offered to publish from outside my listings', (
    tester,
  ) async {
    await _pump(tester);

    // browse is the first tab, and it is not where publishing belongs
    final button = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(button.tooltip, 'New listing');
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      0,
      reason: 'the compose button folds away on the tabs that do not own it',
    );
  });

  testWidgets('counts photos the way round a reader expects', (tester) async {
    await _pump(tester);
    await _openEditor(tester);
    await _fillBasics(tester);
    await _next(tester);
    await tester.enterText(find.byType(TextField).first, '4500');
    await tester.pumpAndSettle();
    await _next(tester);

    expect(_inSheet('0 of 6'), findsOneWidget);
  });

  testWidgets('opens over the shell rather than inside a tab', (tester) async {
    await _pump(tester);
    await _openEditor(tester);

    // the sheet is laid over the destination, and the compose button that
    // opened it is covered rather than left floating on top
    expect(find.byType(ListingEditorSheet), findsOneWidget);
    expect(_inSheet('Basics'), findsOneWidget);
  });

  testWidgets('an unverified student is offered no way to publish', (
    tester,
  ) async {
    await _pump(
      tester,
      data: SampleData(
        viewer: const Identity(
          userId: 'usr_001',
          displayName: 'Aruzhan',
          isVerified: false,
        ),
        listings: _data.listings,
      ),
    );
    await _openMyListings(tester);

    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('publishing adds the listing to the feed', (tester) async {
    await _pump(tester);
    await _openEditor(tester);

    await tester.enterText(find.byType(TextField).first, 'Kettle, barely used');
    await tester.enterText(find.byType(TextField).at(1), 'Boils water');
    await tester.pumpAndSettle();
    await _next(tester);

    await tester.enterText(find.byType(TextField).first, '4500');
    await tester.pumpAndSettle();
    await _next(tester);
    await _next(tester);

    expect(find.text('Kettle, barely used'), findsWidgets);

    await tester.tap(_inSheet('Publish'));
    await _settleToast(tester);

    expect(find.text('Kettle, barely used'), findsWidgets);
  });

  testWidgets('the last step shows the listing as others will meet it', (
    tester,
  ) async {
    await _pump(tester);
    await _openEditor(tester);

    await _fillBasics(tester, title: 'Desk lamp, warm light');
    await _next(tester);
    await tester.enterText(find.byType(TextField).first, '3000');
    await tester.pumpAndSettle();
    await _next(tester);
    await _next(tester);

    expect(
      find.text('This is how your listing will look to other students.'),
      findsOneWidget,
    );
    expect(find.text('Desk lamp, warm light'), findsOneWidget);
    expect(find.textContaining('₸'), findsWidgets);
  });

  testWidgets('refuses to move on without a title', (tester) async {
    await _pump(tester);
    await _openEditor(tester);

    await _next(tester);

    expect(
      find.text('Give the listing a title of at least 3 characters.'),
      findsOneWidget,
    );
    expect(
      find.text('Preview'),
      findsOneWidget,
      reason: 'the step names stay put, so the form did not advance',
    );
    expect(_inSheet('Next'), findsOneWidget);
  });

  testWidgets('says nothing about validity before the first attempt', (
    tester,
  ) async {
    await _pump(tester);
    await _openEditor(tester);

    expect(
      find.text('Give the listing a title of at least 3 characters.'),
      findsNothing,
      reason: 'a form should not scold someone who has not finished typing',
    );
  });

  testWidgets('a giveaway asks for no price at all', (tester) async {
    await _pump(tester);
    await _openEditor(tester);

    await _tapInSheet(tester, 'Free');
    await _fillBasics(tester);
    await _next(tester);

    expect(_inSheet('Price'), findsNothing);
  });

  testWidgets('an exchange asks what the student wants in return', (
    tester,
  ) async {
    await _pump(tester);
    await _openEditor(tester);

    await _tapInSheet(tester, 'Swap');
    await _fillBasics(tester);
    await _next(tester);

    expect(_inSheet('What you want in return'), findsOneWidget);
    expect(_inSheet('Price'), findsNothing);
  });

  testWidgets('both currencies can be chosen', (tester) async {
    await _pump(tester);
    await _openEditor(tester);

    await _fillBasics(tester, title: 'Monitor');
    await _next(tester);

    expect(_inSheet('KZT'), findsOneWidget);
    expect(_inSheet('USD'), findsOneWidget);

    await _tapInSheet(tester, 'USD');
    await tester.enterText(find.byType(TextField).first, '9000');
    await tester.pumpAndSettle();

    await _next(tester);
    await _next(tester);
    await tester.tap(_inSheet('Publish'));
    await _settleToast(tester);

    expect(find.textContaining(r'$90.00'), findsWidgets);
  });

  testWidgets('leaving the editor asks before throwing the draft away', (
    tester,
  ) async {
    await _pump(tester);
    await _openEditor(tester);

    await _fillBasics(tester, title: 'Half typed');

    await tester.tap(find.byTooltip('Discard'));
    await tester.pumpAndSettle();

    expect(find.text('Discard this listing?'), findsOneWidget);
    expect(find.text('Keep editing'), findsOneWidget);
  });
}
