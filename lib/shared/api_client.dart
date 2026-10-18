import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Central HTTP client for the FastAPI backend.
///
/// - Base URL comes from `--dart-define=API_BASE_URL=...`, defaulting to
///   `http://localhost:8000` (web/desktop). Pass
///   `--dart-define=API_BASE_URL=http://10.0.2.2:8000` for the Android
///   emulator. No `dart:io` import so web builds keep working.
/// - All versioned paths go through [v1] which prefixes `/api/v1`.
/// - Auth uses the backend JWT in `SharedPreferences` (`auth_token`),
///   plus `refresh_token`, `organization_id`, `is_admin` (ADR-001).
/// - Session lifecycle: an `auth:true` request that comes back 401
///   triggers **one** `POST /auth/refresh` (single-flight guarded),
///   retries the original request with the new token, and — if the
///   refresh fails — clears the token store and fires [onSessionExpired]
///   so the app can land the user back on the login screen.
class ApiClient {
  static String get baseUrl {
    const env = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:8000',
    );
    if (env != 'http://localhost:8000') return env;
    // Web + desktop hit localhost directly. On physical Android devices
    // override via --dart-define; kIsWeb guard avoids dart:io on web.
    if (kIsWeb) return 'http://localhost:8000';
    return 'http://localhost:8000';
  }

  /// Invoked (at most once per dead session) after a 401 that survives a
  /// refresh attempt — i.e. the refresh token is expired/revoked and the
  /// session is unrecoverable. The app installs a callback that pushes
  /// the login screen and clears the navigation stack.
  static void Function()? onSessionExpired;

  static Uri v1(String path, [Map<String, String>? query]) {
    final p = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$baseUrl/api/v1$p');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: query);
  }

  static Future<int?> getOrganizationId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('organization_id');
  }

  static Future<Map<String, String>> authHeaders({bool json = true}) async {
    final token = await getToken();
    final headers = <String, String>{
      if (json) 'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    return headers;
  }

  static Future<String> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token') ?? '';
  }

  // -- requests (wrapped with the 401 → refresh → retry interceptor) ------

  static Future<http.Response> get(
    String path, {
    Map<String, String>? query,
    bool auth = true,
  }) {
    return _withAuth(
      auth,
      (headers) => http.get(v1(path, query), headers: headers),
    );
  }

  static Future<http.Response> post(
    String path,
    Map<String, dynamic> body, {
    bool auth = true,
  }) {
    return _withAuth(
      auth,
      (headers) =>
          http.post(v1(path), headers: headers, body: json.encode(body)),
    );
  }

  static Future<http.Response> patch(String path, Map<String, dynamic> body) {
    return _withAuth(
      true,
      (headers) =>
          http.patch(v1(path), headers: headers, body: json.encode(body)),
    );
  }

  static Future<http.Response> delete(String path) {
    return _withAuth(
      true,
      (headers) => http.delete(v1(path), headers: headers),
    );
  }

  static Future<http.StreamedResponse> postMultipart(
    String path, {
    Map<String, String> fields = const {},
    List<http.MultipartFile> files = const [],
  }) async {
    // MultipartRequest is single-use, so rebuild per attempt.
    Future<http.StreamedResponse> send() async {
      final request = http.MultipartRequest('POST', v1(path));
      request.headers.addAll(await authHeaders(json: false));
      request.fields.addAll(fields);
      request.files.addAll(files);
      return request.send();
    }

    var response = await send();
    if (response.statusCode == 401) {
      // Expired access token — refresh once and re-send (callers still
      // read the final status off the stream).
      if (await _refreshOnce() == _refreshOk) {
        response = await send();
      }
    }
    return response;
  }

  static Future<http.Response> _withAuth(
    bool auth,
    Future<http.Response> Function(Map<String, String> headers) send,
  ) async {
    final first = await send(await authHeaders());
    if (!auth || first.statusCode != 401) return first;

    // The access token is expired/invalid — refresh once and retry.
    if (await _refreshOnce() == _refreshOk) {
      final retry = await send(await authHeaders());
      if (retry.statusCode != 401) return retry;
    }
    return _onSessionDead(first);
  }

  // -- token refresh ------------------------------------------------------

  static const _refreshOk = 1;
  static const _refreshDead = 0;
  static const _refreshOffline = -1;

  /// Single-flight guard: concurrent 401s share one refresh call so token
  /// rotation can't be double-spent.
  static Future<int>? _refreshInFlight;

  static Future<int> _refreshOnce() {
    // Non-null → an earlier 401 already triggered a refresh; share it.
    return _refreshInFlight ??= _doRefreshInner().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  /// Exchange the stored refresh token for a fresh TokenPair (rotation:
  /// the old refresh token is invalidated server-side). [_refreshOk] on
  /// success, [_refreshDead] when the refresh token is
  /// missing/unknown/expired (session unrecoverable), [_refreshOffline]
  /// when the backend is unreachable (transient — keep the session).
  static Future<int> _doRefreshInner() async {
    final prefs = await SharedPreferences.getInstance();
    final refresh = prefs.getString('refresh_token') ?? '';
    if (refresh.isEmpty) return _refreshDead;
    try {
      final response = await http.post(
        v1('/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'refresh_token': refresh}),
      );
      if (response.statusCode != 200) return _refreshDead;
      final data = json.decode(response.body) as Map<String, dynamic>;
      final access = data['access_token']?.toString() ?? '';
      final newRefresh = data['refresh_token']?.toString() ?? '';
      if (access.isEmpty) return _refreshDead;
      await prefs.setString('auth_token', access);
      if (newRefresh.isNotEmpty) {
        await prefs.setString('refresh_token', newRefresh);
      }
      _sessionExpiredNotified = false;
      return _refreshOk;
    } catch (_) {
      // Backend unreachable — not a dead session; the caller keeps its
      // original 401 and the user keeps their session for later retry.
      return _refreshOffline;
    }
  }

  static bool _sessionExpiredNotified = false;

  static Future<http.Response> _onSessionDead(http.Response response) async {
    if (!_sessionExpiredNotified) {
      _sessionExpiredNotified = true;
      // The refresh token is dead too — no point revoking server-side;
      // just clear everything locally and let the UI log the user out.
      await clearSession();
      onSessionExpired?.call();
    }
    return response;
  }

  // -- session lifecycle --------------------------------------------------

  /// Returns true when a usable token pair exists, refreshing the access
  /// token if only the refresh token survived (cold-start resume path).
  static Future<bool> ensureSession() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString('auth_token') ?? '';
    final refresh = prefs.getString('refresh_token') ?? '';
    if (token.isEmpty && refresh.isNotEmpty) {
      final result = await _refreshOnce();
      if (result != _refreshOk) return false;
      token = prefs.getString('auth_token') ?? '';
    }
    return token.isNotEmpty;
  }

  /// Sign the user out: best-effort `POST /auth/logout` (revokes the
  /// refresh token server-side, §49 #6), then clear the local token store.
  /// Never throws — offline/failed logout still clears local state.
  static Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    final refresh = prefs.getString('refresh_token') ?? '';
    if (refresh.isNotEmpty) {
      try {
        await post('/auth/logout', {'refresh_token': refresh});
      } catch (_) {
        // Server revoke failed (offline etc.) — clear locally anyway.
      }
    }
    await clearSession();
  }

  /// Clears the local token store without contacting the server.
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('refresh_token');
    await prefs.remove('organization_id');
    await prefs.remove('is_admin');
  }

  // -- response helpers ---------------------------------------------------

  /// Decode a paged envelope `{items, next_cursor}` into its items list.
  static List<dynamic> pageItems(http.Response response) {
    final decoded = json.decode(response.body);
    if (decoded is Map<String, dynamic> && decoded['items'] is List) {
      return decoded['items'] as List<dynamic>;
    }
    if (decoded is List) return decoded;
    return [];
  }

  static String? pageCursor(http.Response response) {
    final decoded = json.decode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded['next_cursor']?.toString();
    }
    return null;
  }
}
