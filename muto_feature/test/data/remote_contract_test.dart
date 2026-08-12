import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:muto_feature/src/config/muto_config.dart';
import 'package:muto_feature/src/data/remote/remote_api_client.dart';
import 'package:muto_feature/src/data/remote/remote_auth.dart';
import 'package:muto_feature/src/data/remote/remote_dependencies.dart';
import 'package:muto_feature/src/data/remote/remote_dtos.dart';
import 'package:muto_feature/src/data/remote/remote_repositories.dart';
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
import 'package:muto_feature/src/domain/entities/report_reason.dart';
import 'package:muto_feature/src/domain/failures.dart';
import 'package:muto_feature/src/domain/repositories/image_locator.dart';
import 'package:muto_feature/src/domain/repositories/image_repository.dart';
import 'package:muto_feature/src/domain/repositories/listing_repository.dart';

void main() {
  group('remote DTOs', () {
    test('parse the complete listing wire shape', () {
      final listing = listingFromWire(_listing());

      expect(listing.id, 'listing-1');
      expect(listing.version, const Version(3));
      expect(listing.kind, ListingKind.sale);
      expect(
        listing.price,
        const Money(minorUnits: 1200, currency: Currency.kzt),
      );
      expect(listing.images, const [
        ImageRef(id: 'image-1', version: 'version-123456789'),
      ]);
      expect(listing.contact?.telegramUsername, 'student');
    });

    test('reject an unknown required enum value', () {
      expect(
        () => listingFromWire({..._listing(), 'kind': 'auction'}),
        throwsA(isA<UnexpectedFailure>()),
      );
    });
  });

  group('remote repositories', () {
    test(
      'map listing reads, filters, writes, and concurrency headers',
      () async {
        final requests = <http.Request>[];
        final api = _api((request) async {
          requests.add(request);
          if (request.url.path == '/api/v1/me') return _identityResponse();
          if (request.url.path == '/api/v1/listings/suggestions') {
            return _json({
              'data': ['desk', 'desk lamp'],
              'meta': {},
            });
          }
          if (request.method == 'DELETE') return _json({'data': _listing()});
          if (request.url.path.endsWith('/status')) {
            return _json({
              'data': {..._listing(), 'status': 'reserved'},
            });
          }
          if (request.method == 'POST' || request.method == 'PATCH') {
            return _json({'data': _listing()});
          }
          return _json({
            'data': [_listing()],
            'meta': {'next_cursor': 'opaque-next'},
          });
        });
        final session = RemoteSessionRepository(api);
        final repository = RemoteListingRepository(api);
        await session.resolve('token-a');

        final page = await repository.browse(
          query: const ListingQuery(
            text: 'desk',
            category: ListingCategory.furniture,
            kind: ListingKind.sale,
            condition: ListingCondition.good,
            currency: Currency.kzt,
            minMinorUnits: 100,
            maxMinorUnits: 5000,
            sort: ListingSort.priceAscending,
          ),
        );
        expect(page.nextCursor, const Cursor('opaque-next'));
        final browse = requests.last;
        expect(browse.url.queryParameters['q'], 'desk');
        expect(browse.url.queryParameters['sort'], 'price_ascending');
        expect(browse.headers['Authorization'], 'Bearer token-a');

        expect(await repository.suggestions('de'), ['desk', 'desk lamp']);
        await repository.create(
          _draft,
          requestId: const ClientRequestId('request-key-123456'),
        );
        expect(requests.last.headers['Idempotency-Key'], 'request-key-123456');
        final createBody =
            jsonDecode(requests.last.body) as Map<String, Object?>;
        expect(createBody['price_minor_units'], 1200);

        await repository.update(
          'listing-1',
          _draft,
          expected: const Version(3),
        );
        expect(requests.last.headers['If-Match'], '3');

        await repository.changeStatus(
          'listing-1',
          ListingStatus.reserved,
          expected: const Version(3),
        );
        expect(requests.last.headers['Idempotency-Key'], contains('reserved'));

        await repository.remove('listing-1', expected: const Version(3));
        expect(requests.last.method, 'DELETE');
        expect(requests.last.headers['If-Match'], '3');
      },
    );

    test('map favorites, sellers, reports, and image staging', () async {
      final requests = <http.Request>[];
      final api = _api((request) async {
        requests.add(request);
        if (request.url.path == '/api/v1/me') return _identityResponse();
        if (request.url.path == '/api/v1/favorites/ids') {
          return _json({
            'data': ['listing-1'],
            'meta': {},
          });
        }
        if (request.url.path == '/api/v1/sellers/seller-1') {
          return _json({'data': _seller()});
        }
        if (request.url.path == '/api/v1/operations/reports') {
          return _json({
            'data': [_operationalReport()],
            'meta': {'next_cursor': null},
          });
        }
        if (request.url.path == '/api/v1/image-uploads') {
          return _json({
            'data': {
              'upload_id': 'upload-1',
              'upload_target': '/api/v1/image-uploads/upload-1/content',
            },
          }, status: 201);
        }
        if (request.url.path.endsWith('/finalize')) {
          return _json({
            'data': {'id': 'image-2', 'version': 'version-abcdefghijkl'},
          });
        }
        if (request.url.path.contains('/sellers/') ||
            request.url.path == '/api/v1/favorites') {
          return _json({
            'data': [_listing()],
            'meta': {},
          });
        }
        return _json({'data': {}});
      });
      final session = RemoteSessionRepository(api);
      await session.resolve('token-b');
      final favorites = RemoteFavoritesRepository(api);
      final sellers = RemoteSellerRepository(api);
      final reports = RemoteReportRepository(api);
      final reportOperations = RemoteReportOperationsRepository(api);
      final images = RemoteImageRepository(api);

      expect(await favorites.savedIds(), {'listing-1'});
      await favorites.add('listing-1');
      await favorites.remove('listing-1');
      expect((await favorites.page()).items, hasLength(1));
      expect((await sellers.profile('seller-1')).displayName, 'Seller');
      expect((await sellers.listings('seller-1')).items, hasLength(1));
      await reports.submit(
        listingId: 'listing-1',
        reason: ReportReason.misleading,
        requestId: const ClientRequestId('report-key-123456'),
      );
      expect(requests.last.headers['Idempotency-Key'], 'report-key-123456');
      expect((await reportOperations.reports()).items.single.id, 'report-1');

      final image = await images.stage(
        StagedImage(
          bytes: Uint8List.fromList([1, 2, 3]),
          mimeType: 'image/png',
          width: 200,
          height: 200,
        ),
      );
      expect(image.id, 'image-2');
      final upload = requests.firstWhere(
        (request) => request.url.path.endsWith('/content'),
      );
      expect(upload.url.path, '/api/v1/image-uploads/upload-1/content');
      expect(upload.headers['Content-Type'], 'image/png');
      expect(upload.bodyBytes, [1, 2, 3]);
    });
  });

  group('remote failures and account isolation', () {
    test('time out without retrying the request', () async {
      var calls = 0;
      final api = RemoteApiClient(
        baseUri: Uri.parse('https://market.example'),
        auth: RemoteAuthState(),
        client: MockClient((_) async {
          calls++;
          await Completer<void>().future;
          return _identityResponse();
        }),
        timeout: const Duration(milliseconds: 1),
      );

      await expectLater(
        RemoteSessionRepository(api).resolve('token'),
        throwsA(isA<NetworkFailure>()),
      );
      expect(calls, 1);
    });

    test('map version conflicts with the current version', () async {
      final api = _api((request) async {
        if (request.url.path == '/api/v1/me') return _identityResponse();
        return _json({
          'error': {
            'code': 'listing_version_conflict',
            'details': {'current_version': 8},
          },
        }, status: 409);
      });
      await RemoteSessionRepository(api).resolve('token');

      await expectLater(
        RemoteListingRepository(api).byId('listing-1'),
        throwsA(
          isA<ConflictFailure>().having(
            (failure) => failure.current,
            'current',
            const Version(8),
          ),
        ),
      );
    });

    test('an old account 401 cannot expire the current account', () async {
      final oldResponse = Completer<http.Response>();
      final api = _api((request) async {
        if (request.headers['Authorization'] == 'Bearer old-token') {
          return oldResponse.future;
        }
        return _identityResponse(userId: 'new-user');
      });
      final sessions = RemoteSessionRepository(api);
      final oldRequest = sessions.resolve('old-token');
      await Future<void>.delayed(Duration.zero);
      final current = await sessions.resolve('new-token');
      oldResponse.complete(_json({'error': {}}, status: 401));

      expect(current.userId, 'new-user');
      await expectLater(oldRequest, throwsA(isA<NetworkFailure>()));
      expect((await sessions.resolve('new-token')).userId, 'new-user');
    });

    test(
      'remote wiring exposes authenticated image URLs only after resolve',
      () async {
        final dependencies = createRemoteDependencies(
          baseUri: Uri.parse('https://market.example'),
          client: MockClient((_) async => _identityResponse()),
        );
        expect(dependencies.backend.name, 'remote');
        expect(
          () => dependencies.imageLocator.locate(
            const ImageRef(id: 'image-1', version: 'version-1'),
          ),
          throwsA(isA<UnauthorizedFailure>()),
        );
        await dependencies.session.resolve('image-token');
        final location =
            dependencies.imageLocator.locate(
                  const ImageRef(id: 'image-1', version: 'version-1'),
                )
                as RemoteImageLocation;
        expect(location.uri.path, '/api/v1/images/image-1/version-1');
        expect(location.uri.queryParameters['account_session'], isNotEmpty);
        expect(location.headers['Authorization'], 'Bearer image-token');

        await dependencies.session.resolve('another-token');
        final switched =
            dependencies.imageLocator.locate(
                  const ImageRef(id: 'image-1', version: 'version-1'),
                )
                as RemoteImageLocation;
        expect(switched.uri, isNot(location.uri));
      },
    );

    test('remote configuration validates and normalizes its base URI', () {
      expect(
        MutoConfig.remote(
          baseUri: Uri.parse('https://market.example/'),
        ).baseUri,
        Uri.parse('https://market.example'),
      );
      expect(
        () => MutoConfig.remote(baseUri: Uri.parse('/relative')),
        throwsArgumentError,
      );
      expect(
        () => MutoConfig.remote(baseUri: Uri.parse('http://market.example')),
        throwsArgumentError,
      );
      expect(
        () => MutoConfig.remote(
          baseUri: Uri.parse('https://token@market.example?secret=value'),
        ),
        throwsArgumentError,
      );
    });
  });
}

RemoteApiClient _api(Future<http.Response> Function(http.Request) handler) =>
    RemoteApiClient(
      baseUri: Uri.parse('https://market.example'),
      auth: RemoteAuthState(),
      client: MockClient(handler),
    );

http.Response _identityResponse({String userId = 'user-1'}) => _json({
  'data': {
    'user_id': userId,
    'display_name': 'Student',
    'is_verified': true,
    'is_admin': false,
  },
});

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, Object?> _listing() => {
  'id': 'listing-1',
  'version': 3,
  'kind': 'sale',
  'status': 'active',
  'title': 'Desk lamp',
  'description': 'Works well',
  'condition': 'good',
  'category': 'furniture',
  'images': [
    {'id': 'image-1', 'version': 'version-123456789'},
  ],
  'seller_id': 'seller-1',
  'seller_display_name': 'Seller',
  'created_at': '2026-01-02T03:04:05Z',
  'updated_at': '2026-01-03T03:04:05Z',
  'price': {'minor_units': 1200, 'currency': 'KZT'},
  'wanted_items': null,
  'contact': {'telegram_username': 'student'},
};

Map<String, Object?> _seller() => {
  'seller_id': 'seller-1',
  'display_name': 'Seller',
  'is_verified': true,
  'active_listing_count': 2,
  'first_listed_at': '2025-01-02T03:04:05Z',
};

Map<String, Object?> _operationalReport() => {
  'id': 'report-1',
  'listing_id': 'listing-1',
  'listing_title': 'Desk lamp',
  'listing_status': 'active',
  'reason': 'misleading',
  'note': 'Incorrect description',
  'created_at': '2026-01-04T03:04:05Z',
};

const ListingDraft _draft = ListingDraft(
  kind: ListingKind.sale,
  title: 'Desk lamp',
  description: 'Works well',
  condition: ListingCondition.good,
  category: ListingCategory.furniture,
  images: [ImageRef(id: 'image-1', version: 'version-123456789')],
  price: Money(minorUnits: 1200, currency: Currency.kzt),
);
