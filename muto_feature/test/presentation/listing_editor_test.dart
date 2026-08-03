import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/muto_feature.dart';
import 'package:muto_feature/src/data/mock/mock_environment.dart';
import 'package:muto_feature/src/data/mock/sample_data.dart';
import 'package:muto_feature/src/data/mock/sample_dependencies.dart';
import 'package:muto_feature/src/domain/entities/identity.dart';
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

Future<void> _openEditor(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
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

    expect(find.byType(FloatingActionButton), findsOneWidget);
    await _openEditor(tester);
    expect(find.text('New listing'), findsWidgets);
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

    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('publishing adds the listing to the feed', (tester) async {
    await _pump(tester);
    await _openEditor(tester);

    await tester.enterText(find.byType(TextField).first, 'Kettle, barely used');
    await tester.enterText(find.byType(TextField).at(1), 'Boils water');
    await tester.enterText(find.byType(TextField).at(2), '4500');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Publish'));
    await _settleToast(tester);

    expect(find.text('Kettle, barely used'), findsWidgets);
  });

  testWidgets('refuses to publish without a title', (tester) async {
    await _pump(tester);
    await _openEditor(tester);

    await tester.enterText(find.byType(TextField).at(2), '4500');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    expect(
      find.text('Give the listing a title of at least 3 characters.'),
      findsOneWidget,
    );
    expect(find.text('New listing'), findsWidgets);
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

    expect(find.text('Price'), findsOneWidget);

    await tester.tap(find.text('Free').first);
    await tester.pumpAndSettle();

    expect(find.text('Price'), findsNothing);
  });

  testWidgets('an exchange asks what the student wants in return', (
    tester,
  ) async {
    await _pump(tester);
    await _openEditor(tester);

    await tester.tap(find.text('Swap').first);
    await tester.pumpAndSettle();

    expect(find.text('What you want in return'), findsOneWidget);
    expect(find.text('Price'), findsNothing);
  });

  testWidgets('both currencies can be chosen', (tester) async {
    await _pump(tester);
    await _openEditor(tester);

    expect(find.text('KZT'), findsOneWidget);
    expect(find.text('USD'), findsOneWidget);

    await tester.tap(find.text('USD'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Monitor');
    await tester.enterText(find.byType(TextField).at(2), '9000');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Publish'));
    await _settleToast(tester);

    expect(find.textContaining(r'$90.00'), findsWidgets);
  });

  testWidgets('leaving the editor asks before throwing the draft away', (
    tester,
  ) async {
    await _pump(tester);
    await _openEditor(tester);

    await tester.enterText(find.byType(TextField).first, 'Half typed');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Discard'));
    await tester.pumpAndSettle();

    expect(find.text('Discard this listing?'), findsOneWidget);
    expect(find.text('Keep editing'), findsOneWidget);
  });
}
