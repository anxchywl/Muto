import 'dart:typed_data';

import '../../domain/entities/client_request_id.dart';
import '../../domain/entities/identity.dart';
import '../../domain/entities/image_ref.dart';
import '../../domain/entities/listing.dart';
import '../../domain/entities/listing_status.dart';
import '../../domain/entities/page.dart';
import '../../domain/entities/operational_report.dart';
import '../../domain/entities/report_reason.dart';
import '../../domain/entities/seller_profile.dart';
import '../../domain/failures.dart';
import '../../domain/repositories/favorites_repository.dart';
import '../../domain/repositories/image_locator.dart';
import '../../domain/repositories/image_repository.dart';
import '../../domain/repositories/listing_repository.dart';
import '../../domain/repositories/report_repository.dart';
import '../../domain/repositories/report_operations_repository.dart';
import '../../domain/repositories/seller_repository.dart';
import '../../domain/repositories/session_repository.dart';
import 'remote_api_client.dart';
import 'remote_dtos.dart';

final class RemoteSessionRepository implements SessionRepository {
  const RemoteSessionRepository(this._api);

  final RemoteApiClient _api;

  @override
  Future<Identity> resolve(String accessToken) async =>
      identityFromWire((await _api.resolveSession(accessToken)).dataObject());
}

final class RemoteListingRepository implements ListingRepository {
  const RemoteListingRepository(this._api);

  final RemoteApiClient _api;

  @override
  Future<Page<Listing>> browse({
    required ListingQuery query,
    Cursor? cursor,
  }) async {
    final parameters = <String, String>{
      'q': ?query.text,
      if (query.category case final value?) 'category': value.slug,
      if (query.kind case final value?) 'kind': value.wireValue,
      if (query.condition case final value?) 'condition': value.wireValue,
      if (query.currency case final value?) 'currency': value.code,
      if (query.minMinorUnits case final value?) 'min_minor_units': '$value',
      if (query.maxMinorUnits case final value?) 'max_minor_units': '$value',
      'sort': switch (query.sort) {
        ListingSort.newest => 'newest',
        ListingSort.priceAscending => 'price_ascending',
        ListingSort.priceDescending => 'price_descending',
      },
      if (cursor case final value?) 'cursor': value.value,
    };
    return listingPageFromWire(
      (await _api.get('/api/v1/listings', query: parameters)).envelope(),
    );
  }

  @override
  Future<Listing> byId(String id) async => listingFromWire(
    (await _api.get('/api/v1/listings/${_segment(id)}')).dataObject(),
  );

  @override
  Future<List<String>> suggestions(String prefix) async {
    final values = (await _api.get(
      '/api/v1/listings/suggestions',
      query: {'prefix': prefix},
    )).dataList();
    if (values.any((value) => value is! String)) {
      throw const UnexpectedFailure();
    }
    return values.cast<String>();
  }

  @override
  Future<Page<Listing>> mine({ListingStatus? status, Cursor? cursor}) async =>
      listingPageFromWire(
        (await _api.get(
          '/api/v1/me/listings',
          query: {
            if (status != null) 'status': status.wireValue,
            if (cursor != null) 'cursor': cursor.value,
          },
        )).envelope(),
      );

  @override
  Future<Listing> create(
    ListingDraft draft, {
    required ClientRequestId requestId,
  }) async => listingFromWire(
    (await _api.post(
      '/api/v1/listings',
      body: listingDraftToWire(draft),
      headers: {'Idempotency-Key': requestId.value},
    )).dataObject(),
  );

  @override
  Future<Listing> update(
    String id,
    ListingDraft draft, {
    required Version expected,
  }) async => listingFromWire(
    (await _api.patch(
      '/api/v1/listings/${_segment(id)}',
      body: listingDraftToWire(draft),
      headers: {'If-Match': '${expected.value}'},
    )).dataObject(),
  );

  @override
  Future<Listing> changeStatus(
    String id,
    ListingStatus next, {
    required Version expected,
  }) async => listingFromWire(
    (await _api.patch(
      '/api/v1/listings/${_segment(id)}/status',
      body: {'status': next.wireValue},
      headers: {
        'If-Match': '${expected.value}',
        'Idempotency-Key': 'status:$id:${expected.value}:${next.wireValue}',
      },
    )).dataObject(),
  );

  @override
  Future<void> remove(String id, {required Version expected}) async {
    await _api.delete(
      '/api/v1/listings/${_segment(id)}',
      headers: {
        'If-Match': '${expected.value}',
        'Idempotency-Key': 'remove:$id:${expected.value}',
      },
    );
  }
}

final class RemoteFavoritesRepository implements FavoritesRepository {
  const RemoteFavoritesRepository(this._api);

  final RemoteApiClient _api;

  @override
  Future<Page<Listing>> page({Cursor? cursor}) async => listingPageFromWire(
    (await _api.get(
      '/api/v1/favorites',
      query: {if (cursor != null) 'cursor': cursor.value},
    )).envelope(),
  );

  @override
  Future<Set<String>> savedIds() async {
    final values = (await _api.get('/api/v1/favorites/ids')).dataList();
    if (values.any((value) => value is! String)) {
      throw const UnexpectedFailure();
    }
    return values.cast<String>().toSet();
  }

  @override
  Future<void> add(String listingId) async {
    await _api.put('/api/v1/favorites/${_segment(listingId)}');
  }

  @override
  Future<void> remove(String listingId) async {
    await _api.delete('/api/v1/favorites/${_segment(listingId)}');
  }
}

final class RemoteSellerRepository implements SellerRepository {
  const RemoteSellerRepository(this._api);

  final RemoteApiClient _api;

  @override
  Future<SellerProfile> profile(String sellerId) async => sellerProfileFromWire(
    (await _api.get('/api/v1/sellers/${_segment(sellerId)}')).dataObject(),
  );

  @override
  Future<Page<Listing>> listings(String sellerId, {Cursor? cursor}) async =>
      listingPageFromWire(
        (await _api.get(
          '/api/v1/sellers/${_segment(sellerId)}/listings',
          query: {if (cursor != null) 'cursor': cursor.value},
        )).envelope(),
      );
}

final class RemoteReportRepository implements ReportRepository {
  const RemoteReportRepository(this._api);

  final RemoteApiClient _api;

  @override
  Future<void> submit({
    required String listingId,
    required ReportReason reason,
    String? note,
    required ClientRequestId requestId,
  }) async {
    await _api.post(
      '/api/v1/reports',
      body: {'listing_id': listingId, 'reason': reason.wireValue, 'note': note},
      headers: {'Idempotency-Key': requestId.value},
    );
  }
}

final class RemoteReportOperationsRepository
    implements ReportOperationsRepository {
  const RemoteReportOperationsRepository(this._api);

  final RemoteApiClient _api;

  @override
  Future<Page<OperationalReport>> reports({Cursor? cursor}) async =>
      operationalReportPageFromWire(
        (await _api.get(
          '/api/v1/operations/reports',
          query: {if (cursor != null) 'cursor': cursor.value},
        )).envelope(),
      );
}

final class RemoteImageRepository implements ImageRepository {
  const RemoteImageRepository(this._api);

  final RemoteApiClient _api;

  @override
  Future<ImageRef> stage(StagedImage image) async {
    final slot = (await _api.post(
      '/api/v1/image-uploads',
      body: {'mime_type': image.mimeType, 'byte_length': image.byteLength},
    )).dataObject();
    final uploadId = slot['upload_id'];
    final uploadTarget = slot['upload_target'];
    if (uploadId is! String || uploadTarget is! String) {
      throw const UnexpectedFailure();
    }
    final target = Uri.tryParse(uploadTarget);
    final expectedTarget =
        '/api/v1/image-uploads/${_segment(uploadId)}/content';
    if (target == null ||
        target.hasScheme ||
        target.hasAuthority ||
        target.path != expectedTarget ||
        target.hasQuery ||
        target.hasFragment) {
      throw const UnexpectedFailure();
    }
    await _api.put(
      target.path,
      bytes: Uint8List.fromList(image.bytes),
      headers: {'Content-Type': image.mimeType},
    );
    return imageRefFromWire(
      (await _api.post(
        '/api/v1/image-uploads/${_segment(uploadId)}/finalize',
        headers: {'Idempotency-Key': 'image-finalize:$uploadId'},
      )).dataObject(),
    );
  }
}

final class RemoteImageLocator implements ImageLocator {
  const RemoteImageLocator(this._api);

  final RemoteApiClient _api;

  @override
  ImageLocation? locate(ImageRef ref) => RemoteImageLocation(
    _api.authenticatedResourceUri(
      '/api/v1/images/${_segment(ref.id)}/${_segment(ref.version)}',
    ),
    headers: _api.authorizationHeaders(),
  );
}

String _segment(String value) => Uri.encodeComponent(value);
