import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/api_config.dart';

/// Error returned by the API (`{ "error": { code, message, details } }`) or a
/// transport failure (`status == 0`, code `NETWORK`).
class ApiException implements Exception {
  ApiException(this.status, this.code, this.message, {this.body});

  final int status;
  final String code;
  final String message;

  /// Whole error body; carries `current` (409 version) / `expectedSeq` (409 ball gap).
  final Map<String, dynamic>? body;

  bool get isNetwork => status == 0;
  bool get isUnauthenticated => status == 401;
  bool get isConflict => status == 409;
  int? get expectedSeq => body?['expectedSeq'] as int?;

  @override
  String toString() => 'ApiException($status $code: $message)';
}

/// Thin JSON-over-HTTP client. Adds the Firebase ID token and `X-Device-Id`.
class ApiClient {
  ApiClient({required this.deviceId, http.Client? client, FirebaseAuth? auth})
      : _http = client ?? http.Client(),
        _auth = auth;

  final String deviceId;
  final http.Client _http;
  final FirebaseAuth? _auth;

  FirebaseAuth get _firebase => _auth ?? FirebaseAuth.instance;

  Future<String?> _token({bool force = false}) =>
      _firebase.currentUser?.getIdToken(force) ?? Future.value(null);

  Future<dynamic> request(
    String method,
    String path, {
    Map<String, String?>? query,
    Object? body,
    bool auth = true,
  }) async {
    final q = <String, String>{
      for (final e in (query ?? const <String, String?>{}).entries)
        if (e.value != null) e.key: e.value!,
    };
    final uri = ApiConfig.uri(path, q.isEmpty ? null : q);

    Future<http.Response> attempt({bool forceToken = false}) async {
      final req = http.Request(method, uri)
        ..headers['Accept'] = 'application/json'
        ..headers['X-Device-Id'] = deviceId;
      if (body != null) {
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode(body);
      }
      if (auth) {
        final t = await _token(force: forceToken);
        if (t != null) req.headers['Authorization'] = 'Bearer $t';
      }
      final streamed = await _http.send(req);
      return http.Response.fromStream(streamed);
    }

    // The timeout covers token fetch + request + body, so nothing can hang forever.
    Future<http.Response> send({bool forceToken = false}) =>
        attempt(forceToken: forceToken).timeout(ApiConfig.timeout);

    try {
      var res = await send();
      if (res.statusCode == 401 && auth) res = await send(forceToken: true);
      if (res.statusCode >= 400) {
        debugPrint('API $method $path -> ${res.statusCode} ${utf8.decode(res.bodyBytes)}');
      }
      return _decode(res);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      debugPrint('API $method $path -> timeout');
      throw ApiException(0, 'NETWORK', 'The server did not respond in time');
    } on FirebaseAuthException catch (e) {
      throw ApiException(401, 'UNAUTHENTICATED', e.message ?? e.code);
    } catch (e) {
      debugPrint('API $method $path -> $e');
      throw ApiException(0, 'NETWORK', 'Cannot reach the server');
    }
  }

  dynamic _decode(http.Response res) {
    final text = utf8.decode(res.bodyBytes);
    dynamic json;
    if (text.isNotEmpty) {
      try {
        json = jsonDecode(text);
      } catch (_) {
        json = null;
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return json;
    final map = json is Map<String, dynamic> ? json : null;
    final err = map?['error'];
    if (res.statusCode >= 500) {
      throw ApiException(res.statusCode, 'SERVER_ERROR',
          'Server error (${res.statusCode}). The server could not complete the request, please try again later.',
          body: map);
    }
    throw ApiException(
      res.statusCode,
      err is Map ? (err['code'] as String? ?? 'ERROR') : 'ERROR',
      err is Map ? (err['message'] as String? ?? 'Request failed') : 'Request failed (${res.statusCode})',
      body: map,
    );
  }

  Future<dynamic> get(String p, {Map<String, String?>? query, bool auth = true}) =>
      request('GET', p, query: query, auth: auth);
  Future<dynamic> post(String p, {Object? body, bool auth = true}) =>
      request('POST', p, body: body, auth: auth);
  Future<dynamic> put(String p, {Object? body}) => request('PUT', p, body: body);
  Future<dynamic> patch(String p, {Object? body}) => request('PATCH', p, body: body);
  Future<dynamic> delete(String p) => request('DELETE', p);
}
