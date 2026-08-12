import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../domain/entities/page.dart';
import '../../domain/failures.dart';
import 'remote_auth.dart';

final class RemoteResponse {
  const RemoteResponse({required this.statusCode, required this.bodyBytes});

  final int statusCode;
  final Uint8List bodyBytes;

  Object? json() {
    try {
      return jsonDecode(utf8.decode(bodyBytes));
    } on FormatException {
      throw UnexpectedFailure(statusCode: statusCode);
    }
  }

  Map<String, Object?> dataObject() {
    final envelope = _object(json());
    return _object(envelope['data']);
  }

  List<Object?> dataList() {
    final envelope = _object(json());
    final data = envelope['data'];
    if (data is! List<Object?>) {
      throw UnexpectedFailure(statusCode: statusCode);
    }
    return data;
  }

  Map<String, Object?> envelope() => _object(json());
}

final class RemoteApiClient {
  RemoteApiClient({
    required Uri baseUri,
    required RemoteAuthState auth,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _baseUri = baseUri,
       _auth = auth,
       _client = client ?? http.Client();

  final Uri _baseUri;
  final RemoteAuthState _auth;
  final http.Client _client;
  final Duration timeout;

  Uri uri(String path, [Map<String, String>? query]) {
    final joined = '${_baseUri.path}$path'.replaceAll(RegExp(r'//+'), '/');
    return _baseUri.replace(
      path: joined,
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

  Map<String, String> authorizationHeaders() {
    final token = _auth.accessToken;
    if (token == null) throw const UnauthorizedFailure();
    return {'Authorization': 'Bearer $token'};
  }

  Uri authenticatedResourceUri(String path) {
    authorizationHeaders();
    return uri(path, {'account_session': '${_auth.sessionNamespace}'});
  }

  Future<RemoteResponse> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<RemoteResponse> post(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) => _send('POST', path, body: body, headers: headers);

  Future<RemoteResponse> patch(
    String path, {
    required Object body,
    Map<String, String>? headers,
  }) => _send('PATCH', path, body: body, headers: headers);

  Future<RemoteResponse> put(
    String path, {
    Object? body,
    Uint8List? bytes,
    Map<String, String>? headers,
  }) => _send('PUT', path, body: body, bytes: bytes, headers: headers);

  Future<RemoteResponse> delete(String path, {Map<String, String>? headers}) =>
      _send('DELETE', path, headers: headers);

  Future<RemoteResponse> resolveSession(String accessToken) async {
    _auth.beginSession(accessToken);
    return _send('GET', '/api/v1/me', tokenOverride: accessToken);
  }

  Future<RemoteResponse> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    Uint8List? bytes,
    Map<String, String>? headers,
    String? tokenOverride,
  }) async {
    final requestToken = tokenOverride ?? _auth.accessToken;
    if (requestToken == null) throw const UnauthorizedFailure();
    final request = http.Request(method, uri(path, query));
    request.headers.addAll({
      'Authorization': 'Bearer $requestToken',
      'Accept': 'application/json',
      ...?headers,
    });
    if (bytes != null) {
      request.bodyBytes = bytes;
      request.headers.putIfAbsent(
        'Content-Type',
        () => 'application/octet-stream',
      );
    } else if (body != null) {
      request.body = jsonEncode(body);
      request.headers['Content-Type'] = 'application/json';
    }
    try {
      final streamed = await _client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _throwFailure(response, requestToken);
      }
      return RemoteResponse(
        statusCode: response.statusCode,
        bodyBytes: response.bodyBytes,
      );
    } on MutoFailure {
      rethrow;
    } on TimeoutException {
      throw const NetworkFailure();
    } on SocketException {
      throw const NetworkFailure();
    } on http.ClientException {
      throw const NetworkFailure();
    }
  }

  Never _throwFailure(http.Response response, String requestToken) {
    if (response.statusCode == 401) {
      if (_auth.accessToken != requestToken) throw const NetworkFailure();
      _auth.clearIfCurrent(requestToken);
      throw const UnauthorizedFailure();
    }
    switch (response.statusCode) {
      case 403:
        throw const ForbiddenFailure();
      case 404:
        throw const NotFoundFailure();
      case 410:
        throw const GoneFailure();
      case 409:
        throw ConflictFailure(current: _currentVersion(response));
      case 429:
        throw RateLimitedFailure(retryAfter: _retryAfter(response));
      default:
        throw UnexpectedFailure(statusCode: response.statusCode);
    }
  }

  static Version? _currentVersion(http.Response response) {
    try {
      final envelope = _object(jsonDecode(response.body));
      final error = _object(envelope['error']);
      final details = _object(error['details']);
      final value = details['current_version'];
      return value is int ? Version(value) : null;
    } on Object {
      return null;
    }
  }

  static Duration? _retryAfter(http.Response response) {
    final seconds = int.tryParse(response.headers['retry-after'] ?? '');
    return seconds == null ? null : Duration(seconds: seconds);
  }
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) throw const UnexpectedFailure();
  return value;
}
