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

  static Uri v1(String path, [Map<String, String>? query]) {
    final p = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$baseUrl/api/v1$p');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: query);
  }

  static Future<String> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token') ?? '';
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

  static Future<http.Response> get(
    String path, {
    Map<String, String>? query,
    bool auth = true,
  }) async {
    return http.get(
      v1(path, query),
      headers: auth ? await authHeaders() : {'Content-Type': 'application/json'},
    );
  }

  static Future<http.Response> post(
    String path,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    return http.post(
      v1(path),
      headers: auth ? await authHeaders() : {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
  }

  static Future<http.Response> patch(
    String path,
    Map<String, dynamic> body,
  ) async {
    return http.patch(
      v1(path),
      headers: await authHeaders(),
      body: json.encode(body),
    );
  }

  static Future<http.Response> delete(String path) async {
    return http.delete(v1(path), headers: await authHeaders());
  }

  static Future<http.StreamedResponse> postMultipart(
    String path, {
    Map<String, String> fields = const {},
    List<http.MultipartFile> files = const [],
  }) async {
    final request = http.MultipartRequest('POST', v1(path));
    final headers = await authHeaders(json: false);
    request.headers.addAll(headers);
    request.fields.addAll(fields);
    request.files.addAll(files);
    return request.send();
  }

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
      final cursor = decoded['next_cursor'];
      return cursor?.toString();
    }
    return null;
  }
}
