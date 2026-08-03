import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/src/application/cache/generation.dart';
import 'package:muto_feature/src/application/cache/listing_cache.dart';
import 'package:muto_feature/src/application/listing_editor_controller.dart';
import 'package:muto_feature/src/data/mock/mock_environment.dart';
import 'package:muto_feature/src/data/mock/mock_image_repository.dart';
import 'package:muto_feature/src/data/mock/mock_listing_repository.dart';
import 'package:muto_feature/src/data/mock/sample_data.dart';
import 'package:muto_feature/src/domain/entities/client_request_id.dart';
import 'package:muto_feature/src/domain/entities/currency.dart';
import 'package:muto_feature/src/domain/entities/image_ref.dart';
import 'package:muto_feature/src/domain/entities/listing.dart';
import 'package:muto_feature/src/domain/entities/listing_category.dart';
import 'package:muto_feature/src/domain/entities/listing_condition.dart';
import 'package:muto_feature/src/domain/entities/listing_kind.dart';
import 'package:muto_feature/src/domain/entities/listing_status.dart';
import 'package:muto_feature/src/domain/entities/money.dart';
import 'package:muto_feature/src/domain/entities/page.dart';
import 'package:muto_feature/src/domain/failures.dart';
import 'package:muto_feature/src/domain/repositories/draft_store.dart';
import 'package:muto_feature/src/domain/repositories/image_repository.dart';
import 'package:muto_feature/src/domain/validation/image_rules.dart';
import 'package:muto_feature/src/domain/validation/listing_rules.dart';

late SampleData _data;

/// In memory, so the test can see exactly what the editor saved and when it
/// cleared it.
final class _FakeDraftStore implements DraftStore {
  final Map<String, StoredDraft> saved = {};
  int clears = 0;

  @override
  Future<StoredDraft?> read(String userId) async => saved[userId];

  @override
  Future<void> write(String userId, StoredDraft draft) async {
    saved[userId] = draft;
  }

  @override
  Future<void> clear(String userId) async {
    clears++;
    saved.remove(userId);
  }
}

ListingDraft _blank({
  ListingKind kind = ListingKind.sale,
  String title = 'Desk lamp',
  Money? price = const Money(minorUnits: 3000, currency: Currency.kzt),
  List<ImageRef> images = const [],
}) {
  return ListingDraft(
    kind: kind,
    title: title,
    description: 'Works fine',
    condition: ListingCondition.good,
    category: ListingCategory.dorm,
    images: images,
    price: price,
  );
}

StagedImage _image() => StagedImage(
  bytes: File('assets/sample/images/sample-01.png').readAsBytesSync(),
  mimeType: 'image/png',
  width: 600,
  height: 450,
);

({
  ListingEditorController editor,
  _FakeDraftStore drafts,
  MockListingRepository listings,
  CacheGeneration generation,
  MockFaults faults,
  int Function() unauthorizedCount,
})
_build({
  ListingDraft? initial,
  String? editingListingId,
  Version? expectedVersion,
  MockFaults? faults,
  MockLatency latency = const MockLatency.none(),
}) {
  final shared = faults ?? MockFaults();
  final generation = CacheGeneration();
  final cache = ListingCache();
  final drafts = _FakeDraftStore();
  var unauthorized = 0;

  final listings = MockListingRepository(
    seed: _data.listings,
    viewer: () => _data.viewer,
    latency: latency,
    faults: shared,
  );

  return (
    editor: ListingEditorController(
      listings: listings,
      images: MockImageRepository(
        store: StagedImageStore(),
        latency: const MockLatency.none(),
        faults: shared,
      ),
      drafts: drafts,
      cache: cache,
      generation: generation,
      onUnauthorized: () => unauthorized++,
      userId: _data.viewer.userId,
      initial: initial ?? _blank(),
      editingListingId: editingListingId,
      expectedVersion: expectedVersion,
    ),
    drafts: drafts,
    listings: listings,
    generation: generation,
    faults: shared,
    unauthorizedCount: () => unauthorized,
  );
}

void main() {
  setUpAll(() {
    _data = SampleData.decode(
      File('assets/sample/listings.json').readAsStringSync(),
    );
  });

  group('validation', () {
    test('stays quiet until the student tries to publish', () async {
      final harness = _build(initial: _blank(title: 'ab'));

      expect(harness.editor.visibleIssues.isValid, isTrue);
      expect(harness.editor.validation.isValid, isFalse);

      await harness.editor.submit();
      expect(
        harness.editor.visibleIssues.issues,
        contains(ListingIssue.titleTooShort),
      );
    });

    test('an invalid draft never reaches the repository', () async {
      final harness = _build(initial: _blank(title: 'ab'));
      final result = await harness.editor.submit();

      expect(result, isNull);
      expect(harness.drafts.clears, 0);
    });

    test(
      'a giveaway drops the price rather than refusing to publish',
      () async {
        final harness = _build(initial: _blank(kind: ListingKind.giveaway));

        final saved = await harness.editor.submit();
        expect(saved, isNotNull);
        expect(saved!.price, isNull);
        expect(saved.kind, ListingKind.giveaway);
      },
    );
  });

  group('publishing', () {
    test('creates an active listing owned by the student', () async {
      final harness = _build();
      final saved = await harness.editor.submit();

      expect(saved, isNotNull);
      expect(saved!.status, ListingStatus.active);
      expect(saved.sellerId, _data.viewer.userId);
    });

    test('clears the stored draft once it has been written', () async {
      final harness = _build();
      harness.editor.edit((draft) => draft.copyWith(title: 'Desk lamp two'));
      expect(harness.drafts.saved, isNotEmpty);

      await harness.editor.submit();
      expect(harness.drafts.saved, isEmpty);
    });

    test('a retry after a failure reuses the same request id', () async {
      final harness = _build(faults: MockFaults()..offline = true);
      final token = harness.editor.requestId;

      final first = await harness.editor.submit();
      expect(first, isNull);
      expect(harness.editor.failure, isA<NetworkFailure>());

      harness.faults.offline = false;
      final second = await harness.editor.submit();

      expect(second, isNotNull);
      expect(
        harness.editor.requestId,
        token,
        reason:
            'a retry must reach the same identity, not create a second '
            'listing',
      );
    });

    test('publishing the same draft twice yields one listing', () async {
      final harness = _build();

      final first = await harness.editor.submit();
      final second = await harness.editor.submit();

      expect(first, isNotNull);
      expect(second!.id, first!.id);
    });

    test('surfaces a conflict without discarding what was typed', () async {
      final mine = _data.listings.firstWhere(
        (listing) => listing.sellerId == _data.viewer.userId,
      );
      final harness = _build(
        initial: _blank(title: 'Renamed'),
        editingListingId: mine.id,
        expectedVersion: const Version(99),
      );

      final result = await harness.editor.submit();

      expect(result, isNull);
      expect(harness.editor.failure, isA<ConflictFailure>());
      expect(harness.editor.draft.title, 'Renamed');
    });

    test('reports an expired session upwards', () async {
      final harness = _build(faults: MockFaults()..sessionExpired = true);
      await harness.editor.submit();

      expect(harness.editor.failure, isA<UnauthorizedFailure>());
      expect(harness.unauthorizedCount(), 1);
    });

    test('a result landing after an account switch is discarded', () async {
      final harness = _build(
        latency: const MockLatency(write: Duration(milliseconds: 20)),
      );

      final pending = harness.editor.submit();
      // the session controller does exactly this when a new student resolves
      harness.generation.bump();

      expect(
        await pending,
        isNull,
        reason:
            'a listing published as one student must not surface as the '
            'next',
      );
    });
  });

  group('images', () {
    test('stages an acceptable image onto the draft', () async {
      final harness = _build();
      await harness.editor.addImage(_image());

      expect(harness.editor.draft.images, hasLength(1));
      expect(harness.editor.imageIssue, isNull);
    });

    test('refuses content that is not an image, by its bytes', () async {
      final harness = _build();
      await harness.editor.addImage(
        StagedImage(
          bytes: Uint8List.fromList(List<int>.filled(64, 0x41)),
          mimeType: 'image/png',
          width: 600,
          height: 450,
        ),
      );

      expect(harness.editor.imageIssue, ImageIssue.unsupportedType);
      expect(harness.editor.draft.images, isEmpty);
    });

    test('refuses an image below the minimum size', () async {
      final harness = _build();
      await harness.editor.addImage(
        StagedImage(
          bytes: File('assets/sample/images/sample-01.png').readAsBytesSync(),
          mimeType: 'image/png',
          width: 80,
          height: 80,
        ),
      );

      expect(harness.editor.imageIssue, ImageIssue.tooSmall);
    });

    test('stops accepting images at the cap', () async {
      final harness = _build();
      for (var i = 0; i < ListingRules.maxImages + 2; i++) {
        await harness.editor.addImage(_image());
      }

      expect(harness.editor.draft.images, hasLength(ListingRules.maxImages));
      expect(harness.editor.canAddImage, isFalse);
    });

    test('removes an image the student changed their mind about', () async {
      final harness = _build();
      await harness.editor.addImage(_image());
      final ref = harness.editor.draft.images.single;

      harness.editor.removeImage(ref);
      expect(harness.editor.draft.images, isEmpty);
    });
  });

  group('draft persistence', () {
    test('saves what was typed, with the request id', () async {
      final harness = _build();
      harness.editor.edit((draft) => draft.copyWith(title: 'Half typed'));

      final stored = await harness.drafts.read(_data.viewer.userId);
      expect(stored, isNotNull);
      expect(stored!.draft.title, 'Half typed');
      expect(stored.requestId, harness.editor.requestId);
    });

    test('is scoped to one account', () async {
      final harness = _build();
      harness.editor.edit((draft) => draft.copyWith(title: 'Mine'));

      expect(await harness.drafts.read(_data.viewer.userId), isNotNull);
      expect(await harness.drafts.read('usr_other'), isNull);
    });

    test('discarding removes it', () async {
      final harness = _build();
      harness.editor.edit((draft) => draft.copyWith(title: 'Half typed'));

      await harness.editor.discard();
      expect(await harness.drafts.read(_data.viewer.userId), isNull);
    });

    test('a request id restored with a draft is kept, not minted again', () {
      const token = ClientRequestId('restored-token');
      final harness = _build();
      final restored = ListingEditorController(
        listings: harness.listings,
        images: MockImageRepository(
          store: StagedImageStore(),
          latency: const MockLatency.none(),
        ),
        drafts: harness.drafts,
        cache: ListingCache(),
        generation: harness.generation,
        onUnauthorized: () {},
        userId: _data.viewer.userId,
        initial: _blank(),
        requestId: token,
      );

      expect(restored.requestId, token);
    });
  });
}
