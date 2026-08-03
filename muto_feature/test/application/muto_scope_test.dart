import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/src/application/muto_scope.dart';
import 'package:muto_feature/src/data/local/preferences_draft_store.dart';
import 'package:muto_feature/src/data/mock/mock_environment.dart';
import 'package:muto_feature/src/data/mock/mock_favorites_repository.dart';
import 'package:muto_feature/src/data/mock/mock_image_repository.dart';
import 'package:muto_feature/src/data/mock/mock_listing_repository.dart';
import 'package:muto_feature/src/data/mock/mock_session_repository.dart';
import 'package:muto_feature/src/data/mock/sample_data.dart';

MutoDependencies _dependencies(SampleData data) {
  final store = StagedImageStore();
  final listings = MockListingRepository(
    seed: data.listings,
    viewer: () => data.viewer,
    latency: const MockLatency.none(),
  );
  return MutoDependencies(
    session: MockSessionRepository(
      identity: data.viewer,
      latency: const MockLatency.none(),
    ),
    listings: listings,
    favorites: MockFavoritesRepository(
      listings: listings,
      latency: const MockLatency.none(),
    ),
    images: MockImageRepository(
      store: store,
      latency: const MockLatency.none(),
    ),
    imageLocator: MockImageLocator(store: store, bundled: const {}),
    drafts: const PreferencesDraftStore(),
  );
}

void main() {
  late SampleData data;

  setUpAll(() {
    data = SampleData.decode(
      File('assets/sample/listings.json').readAsStringSync(),
    );
  });

  testWidgets('exposes its controllers to the subtree', (tester) async {
    late MutoScopeData scope;
    await tester.pumpWidget(
      MutoScope(
        dependencies: _dependencies(data),
        child: Builder(
          builder: (context) {
            scope = MutoScope.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(scope.session, isNotNull);
    expect(scope.cache, isNotNull);
    expect(scope.browse, isNotNull);
    expect(scope.mine, isNotNull);
    expect(scope.favorites, isNotNull);
  });

  testWidgets('each feed is its own controller', (tester) async {
    late MutoScopeData scope;
    await tester.pumpWidget(
      MutoScope(
        dependencies: _dependencies(data),
        child: Builder(
          builder: (context) {
            scope = MutoScope.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(identical(scope.browse, scope.mine), isFalse);
    expect(identical(scope.browse, scope.favorites), isFalse);
  });

  testWidgets('unmounting disposes everything it owns', (tester) async {
    late MutoScopeData scope;
    await tester.pumpWidget(
      MutoScope(
        dependencies: _dependencies(data),
        child: Builder(
          builder: (context) {
            scope = MutoScope.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final session = scope.session;
    final cache = scope.cache;
    final browse = scope.browse;

    await tester.pumpWidget(const SizedBox.shrink());

    // a disposed ChangeNotifier rejects new listeners, which is how the test
    // observes that nothing was left running
    expect(() => session.addListener(() {}), throwsFlutterError);
    expect(() => cache.addListener(() {}), throwsFlutterError);
    expect(() => browse.addListener(() {}), throwsFlutterError);
  });

  testWidgets('a rebuilt scope carries no state from the previous one', (
    tester,
  ) async {
    final controllers = <Object>[];

    Future<void> mount(Key key) async {
      await tester.pumpWidget(
        MutoScope(
          key: key,
          dependencies: _dependencies(data),
          child: Builder(
            builder: (context) {
              controllers.add(MutoScope.of(context).cache);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    }

    await mount(const ValueKey('session-a'));
    await mount(const ValueKey('session-b'));

    expect(
      identical(controllers.first, controllers.last),
      isFalse,
      reason: 'a new session must not inherit the previous cache',
    );
  });
}
