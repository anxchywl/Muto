import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

const apiBaseUrl = String.fromEnvironment('MUTO_API_BASE_URL');
const userToken = String.fromEnvironment('MUTO_ACCESS_TOKEN');
const adminToken = String.fromEnvironment('MUTO_ADMIN_ACCESS_TOKEN');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('live backend authenticates, isolates roles and redeems an image', (
    tester,
  ) async {
    expect(Uri.parse(apiBaseUrl).scheme, 'https');
    expect(userToken, isNotEmpty);
    expect(adminToken, isNotEmpty);
    expect(userToken, isNot(adminToken));

    final client = http.Client();
    final unique = DateTime.now().microsecondsSinceEpoch.toString();
    String? listingId;
    int? listingVersion;
    try {
      final user = await _json(
        client.get(_uri('/api/v1/me'), headers: _auth(userToken)),
      );
      final admin = await _json(
        client.get(_uri('/api/v1/me'), headers: _auth(adminToken)),
      );
      expect(_data(user)['is_admin'], isFalse);
      expect(_data(admin)['is_admin'], isTrue);
      expect(_data(user)['user_id'], isNot(_data(admin)['user_id']));

      final denied = await client.get(
        _uri('/api/v1/operations/reports'),
        headers: _auth(userToken),
      );
      expect(denied.statusCode, 403);
      final allowed = await client.get(
        _uri('/api/v1/operations/reports'),
        headers: _auth(adminToken),
      );
      expect(allowed.statusCode, 200);

      final image = await rootBundle.load(
        'packages/muto_feature/assets/sample/images/sample-01.png',
      );
      final bytes = image.buffer.asUint8List();
      final slot = await _json(
        client.post(
          _uri('/api/v1/image-uploads'),
          headers: _jsonAuth(userToken),
          body: jsonEncode({
            'mime_type': 'image/png',
            'byte_length': bytes.length,
          }),
        ),
      );
      final slotData = _data(slot);
      final uploadId = slotData['upload_id'] as String;
      final uploadTarget = slotData['upload_target'] as String;
      final uploaded = await client.put(
        _uri(uploadTarget),
        headers: {..._auth(userToken), 'Content-Type': 'image/png'},
        body: bytes,
      );
      expect(uploaded.statusCode, 200);
      final finalized = await _json(
        client.post(
          _uri('/api/v1/image-uploads/$uploadId/finalize'),
          headers: {
            ..._auth(userToken),
            'Idempotency-Key': 'live-image-$unique',
          },
        ),
      );
      final imageReference = _data(finalized);

      final created = await _json(
        client.post(
          _uri('/api/v1/listings'),
          headers: {
            ..._jsonAuth(userToken),
            'Idempotency-Key': 'live-listing-$unique',
          },
          body: jsonEncode({
            'kind': 'sale',
            'title': 'Automated staging image $unique',
            'description': 'Synthetic integration-test listing',
            'condition': 'good',
            'category': 'other',
            'price_minor_units': 100,
            'currency': 'KZT',
            'images': [imageReference],
          }),
        ),
        expectedStatus: 201,
      );
      final listing = _data(created);
      listingId = listing['id'] as String;
      listingVersion = listing['version'] as int;
      final delivered = await client.get(
        _uri(
          '/api/v1/images/${imageReference['id']}/${imageReference['version']}',
        ),
        headers: _auth(userToken),
      );
      expect(delivered.statusCode, 200);
      expect(delivered.headers['content-type'], startsWith('image/'));
      expect(delivered.bodyBytes, isNotEmpty);
    } finally {
      if (listingId != null && listingVersion != null) {
        await client.delete(
          _uri('/api/v1/listings/$listingId'),
          headers: {
            ..._auth(userToken),
            'If-Match': '"$listingVersion"',
            'Idempotency-Key': 'live-remove-$unique',
          },
        );
      }
      client.close();
    }
  });
}

Uri _uri(String path) => Uri.parse(apiBaseUrl).resolve(path);

Map<String, String> _auth(String token) => {
  'Authorization': 'Bearer $token',
  'Accept': 'application/json',
};

Map<String, String> _jsonAuth(String token) => {
  ..._auth(token),
  'Content-Type': 'application/json',
};

Future<Map<String, Object?>> _json(
  Future<http.Response> responseFuture, {
  int expectedStatus = 200,
}) async {
  final response = await responseFuture.timeout(const Duration(seconds: 20));
  expect(response.statusCode, expectedStatus, reason: response.body);
  return (jsonDecode(response.body) as Map).cast<String, Object?>();
}

Map<String, Object?> _data(Map<String, Object?> envelope) =>
    (envelope['data'] as Map).cast<String, Object?>();
