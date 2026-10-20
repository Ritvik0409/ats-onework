/// Where the signed-in session is kept.
///
/// The access and refresh tokens are secrets: a refresh token is a
/// long-lived credential that can be exchanged for a new session. They
/// are kept in the platform's secure storage — the Android keystore, the
/// iOS keychain, and the equivalent elsewhere — rather than in the
/// preferences file, which is an ordinary unencrypted file in the app's
/// sandbox.
///
/// The organization and the admin flag are not secrets, so they stay in
/// the preferences where the rest of the app expects to find them.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionStore {
  SessionStore._();

  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    iOptions: IOSOptions(
      // The token is not read while the device is locked.
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const String _tokenKey = 'auth_token';
  static const String _refreshKey = 'refresh_token';

  // -- the tokens ---------------------------------------------------------

  static Future<String?> readToken() => _secure.read(key: _tokenKey);

  static Future<void> writeToken(String value) =>
      _secure.write(key: _tokenKey, value: value);

  static Future<String?> readRefreshToken() => _secure.read(key: _refreshKey);

  static Future<void> writeRefreshToken(String value) =>
      _secure.write(key: _refreshKey, value: value);

  static Future<void> deleteTokens() async {
    await _secure.delete(key: _tokenKey);
    await _secure.delete(key: _refreshKey);
  }

  /// Moves a session that was stored before the tokens moved into the
  /// secure store, so an upgrade does not sign everybody out.
  static Future<void> migrateLegacyTokens() async {
    final prefs = await SharedPreferences.getInstance();
    final legacyToken = prefs.getString(_tokenKey);
    final legacyRefresh = prefs.getString(_refreshKey);
    if (legacyToken == null && legacyRefresh == null) return;
    if (legacyToken != null && await readToken() == null) {
      await writeToken(legacyToken);
    }
    if (legacyRefresh != null && await readRefreshToken() == null) {
      await writeRefreshToken(legacyRefresh);
    }
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshKey);
  }

  // -- the organization ---------------------------------------------------

  static Future<int?> readOrganizationId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('organization_id');
  }

  static Future<void> writeOrganizationId(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('organization_id', value);
  }

  static Future<void> deleteOrganizationId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('organization_id');
  }

  static Future<bool> readIsAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_admin') ?? false;
  }

  static Future<void> writeIsAdmin(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_admin', value);
  }

  static Future<void> deleteIsAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('is_admin');
  }
}
