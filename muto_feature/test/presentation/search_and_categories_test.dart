import 'dart:io';

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/muto_feature.dart';
import 'package:muto_feature/src/data/mock/mock_environment.dart';
import 'package:muto_feature/src/data/mock/sample_data.dart';
import 'package:muto_feature/src/data/mock/sample_dependencies.dart';
import 'package:muto_ui/muto_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

late SampleData _data;

Future<void> _pump(
  WidgetTester tester, {
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
          _data,
          latency: const MockLatency.none(),
        ),
        config: const MutoConfig.sample(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The field replaces the pill strip rather than sitting beside it, so every
/// search starts by opening it.
Future<void> _openSearch(WidgetTester tester) async {
  await tester.tap(find.byType(FilterPill).first);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String term) async {
  await tester.enterText(find.byType(TextField).first, term);
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester, String term) async {
  await _openSearch(tester);
  await _type(tester, term);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    _data = SampleData.decode(
      File('assets/sample/listings.json').readAsStringSync(),
    );
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('categories', () {
    testWidgets('narrow the feed from the row, without opening filters', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.text('Small study lamp, clip-on'), findsOneWidget);

      await tester.tap(find.text('Textbooks'));
      await tester.pumpAndSettle();

      expect(find.text('Small study lamp, clip-on'), findsNothing);
      expect(
        find.text('Calculus: Early Transcendentals, 8th edition'),
        findsOneWidget,
      );
    });

    testWidgets('let go of the choice when it is tapped again', (tester) async {
      await _pump(tester);

      await tester.tap(find.text('Textbooks'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Textbooks'));
      await tester.pumpAndSettle();

      expect(find.text('Small study lamp, clip-on'), findsOneWidget);
    });

    testWidgets('are announced as a button, and as chosen once chosen', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      final chip = find.ancestor(
        of: find.text('Textbooks'),
        matching: find.byType(SelectableChip),
      );
      expect(tester.getSemantics(chip).flagsCollection.isButton, isTrue);
      expect(
        tester.getSemantics(chip).flagsCollection.isSelected,
        Tristate.isFalse,
      );

      await tester.tap(chip);
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(chip).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      handle.dispose();
    });
  });

  group('search', () {
    testWidgets('suggests terms from what is actually listed', (tester) async {
      await _pump(tester);

      await _openSearch(tester);
      await _type(tester, 'lam');
      // past the debounce, which no amount of settling reaches on its own
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('lamp'), findsWidgets);
    });

    testWidgets('keeps a term once it has been searched for', (tester) async {
      await _pump(tester);
      await _search(tester, 'lamp');

      // the feed narrowed, and the field kept what was typed
      expect(find.text('Small study lamp, clip-on'), findsOneWidget);

      await _openSearch(tester);
      await _type(tester, '');

      expect(find.text('Recent searches'), findsOneWidget);
      expect(find.text('lamp'), findsWidgets);
    });

    testWidgets('does not remember what was only typed', (tester) async {
      await _pump(tester);

      await _openSearch(tester);
      await _type(tester, 'guitar');
      await _type(tester, '');

      expect(find.text('Recent searches'), findsNothing);
    });

    testWidgets('runs the search again when a recent term is tapped', (
      tester,
    ) async {
      await _pump(tester);
      await _search(tester, 'lamp');

      await _openSearch(tester);
      await _type(tester, '');
      await tester.tap(find.text('lamp').last);
      await tester.pumpAndSettle();

      expect(find.text('Small study lamp, clip-on'), findsOneWidget);
      expect(find.text('Recent searches'), findsNothing);
    });

    testWidgets('forgets a term on request', (tester) async {
      await _pump(tester);
      await _search(tester, 'lamp');

      await _openSearch(tester);
      await _type(tester, '');
      await tester.tap(find.byTooltip('Remove lamp from recent searches'));
      await tester.pumpAndSettle();

      expect(find.text('Recent searches'), findsNothing);
    });

    testWidgets('says nothing matched rather than showing an empty list', (
      tester,
    ) async {
      await _pump(tester);
      await _search(tester, 'zzzzzz');

      expect(find.text('Nothing here yet'), findsOneWidget);
    });
  });
}
