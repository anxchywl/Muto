import 'dart:io';

import 'package:app_ui/app_ui.dart';
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

Future<void> _pump(
  WidgetTester tester, {
  SampleData? data,
  MockLatency latency = const MockLatency.none(),
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
        dependencies: buildSampleDependencies(data ?? _data, latency: latency),
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

    testWidgets('does not show seller info above your listings', (
      tester,
    ) async {
      await _pump(tester);
      await _openTab(tester, 'My listings');

      expect(find.text('Aruzhan'), findsNothing);
      expect(find.text('Your contact info'), findsNothing);
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
      // the bar captions each action in a word; the sentence stays as the
      // label a screen reader reads out
      expect(find.text('Reserve'), findsOneWidget);
      expect(find.text('Sold'), findsOneWidget);
      expect(find.text('Hide'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.bySemanticsLabel('Mark as reserved'), findsOneWidget);
      expect(find.bySemanticsLabel('Remove listing'), findsOneWidget);
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

      expect(find.text('Relist'), findsOneWidget);
      expect(find.text('Reserve'), findsNothing);
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

      // worded for the person looking at it, who is the seller here
      expect(find.textContaining('Sold ('), findsOneWidget);
      expect(find.text('Telegram'), findsNothing);
      handle.dispose();
    });

    testWidgets('marking a listing reserved applies it', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      await _openTab(tester, 'My listings');

      await tester.tap(find.text('University Physics, volume 1'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reserve'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // no toast, and the button that was pressed is still under the finger
      // wearing its tick rather than having been retired mid-animation
      expect(find.text('Listing updated'), findsNothing);
      expect(find.text('Reserve'), findsOneWidget);

      // only once the tick has been seen does the bar rebuild
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      // the owner is left looking at the listing, not dropped back on the list
      expect(find.text('University Physics, volume 1'), findsWidgets);

      // repainted around the new status, in the owner's own terms
      expect(find.textContaining('Reserved ('), findsOneWidget);
      expect(
        find.text('This item is reserved for someone else.'),
        findsNothing,
      );

      // and what was reserved can now only be relisted or sold
      expect(find.text('Reserve'), findsNothing);
      expect(find.text('Relist'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('reserving sweeps the clock hand round', (tester) async {
      await _pump(tester);
      await _openTab(tester, 'My listings');

      await tester.tap(find.text('University Physics, volume 1'));
      await tester.pumpAndSettle();

      // the hour faces are only ever on screen mid-sweep; at rest the button
      // wears the plain clock
      AppIconData? sweepFrame() {
        for (final icon in tester.widgetList<AppIcon>(find.byType(AppIcon))) {
          if (AppIcons.clockHours.contains(icon.icon)) return icon.icon;
        }
        return null;
      }

      expect(sweepFrame(), isNull);

      await tester.tap(find.text('Reserve'));
      // one frame for the write to land and the ticker to start, then the
      // sweep is running
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      await tester.pump(const Duration(milliseconds: 60));
      final early = sweepFrame();
      expect(early, isNotNull, reason: 'the hand should be going round');

      await tester.pump(const Duration(milliseconds: 180));
      expect(
        sweepFrame(),
        isNot(early),
        reason: 'and should have moved on to another hour',
      );

      await tester.pumpAndSettle();
    });

    testWidgets('the icon starts moving on the press, not on the answer', (
      tester,
    ) async {
      // a write slow enough that the two are tellable apart
      await _pump(
        tester,
        latency: const MockLatency(
          read: Duration.zero,
          write: Duration(milliseconds: 400),
        ),
      );
      await _openTab(tester, 'My listings');

      await tester.tap(find.text('University Physics, volume 1'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reserve'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // the write has not come back yet — the listing still reads as active —
      // and the hand is already going round
      expect(find.text('You marked this as reserved.'), findsNothing);
      expect(
        AppIcons.clockHours.any(
          (face) => tester
              .widgetList<AppIcon>(find.byType(AppIcon))
              .any((widget) => widget.icon == face),
        ),
        isTrue,
        reason: 'the motion should not wait for the round trip',
      );

      // and once both the write and the motion are done, the screen catches up
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.textContaining('Reserved ('), findsOneWidget);
    });

    testWidgets('removing asks first and cannot be done by accident', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      await _openTab(tester, 'My listings');

      await tester.tap(find.text('University Physics, volume 1'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Remove this listing?'), findsOneWidget);
      // it rises from the bottom like every other question this app asks,
      // rather than dropping into the middle of the screen
      expect(find.byType(AlertDialog), findsNothing);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      handle.dispose();
    });
  });
}
