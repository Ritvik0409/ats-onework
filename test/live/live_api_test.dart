@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:ats_onework/data/analytics_repository.dart';
import 'package:ats_onework/data/audit_repository.dart';
import 'package:ats_onework/shared/api_client.dart';
import 'package:ats_onework/shared/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// The client against a running backend.
///
/// This is the check the unit tests cannot make: that the JSON the
/// server actually sends parses into the models the dashboards read. It
/// is opt-in — the suite skips itself unless a backend is running and
/// `LIVE_API=1` is set, so it never breaks an offline test run.
///
///   # terminal 1
///   cd backend && .venv\Scripts\python.exe scripts\dev.py
///   # terminal 2
///   cd backend && .venv\Scripts\python.exe scripts\reset_seed_password.py
///   # terminal 3
///   set LIVE_API=1 && flutter test --tags live
const String kEmail = 'admin@acme-corp.dev';
const String kPassword = 'DevPass!2026';

Future<bool> _liveEnabled() async {
  if (Platform.environment['LIVE_API'] != '1') return false;
  try {
    final Socket socket = await Socket.connect(
      '127.0.0.1',
      8000,
      timeout: const Duration(seconds: 2),
    );
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  // Deliberately no TestWidgetsFlutterBinding: it installs an
  // HttpOverrides that answers every request with 400, which is exactly
  // what a live test must not have.
  late bool live;

  group('live API', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
        <String, String>{},
      );
      live = await _liveEnabled();
    });

    test('the analytics endpoints answer and parse', () async {
      if (!live) {
        markTestSkipped('Set LIVE_API=1 and run the backend to include this.');
        return;
      }

      final http.Response response = await ApiClient.post(
        '/auth/login',
        <String, String>{'email': kEmail, 'password': kPassword},
        auth: false,
      );
      expect(response.statusCode, 200, reason: 'the seeded admin can sign in');

      final Map<String, dynamic> body =
          json.decode(response.body) as Map<String, dynamic>;
      final String token = body['access_token']?.toString() ?? '';
      final int organizationId =
          ((body['organizations'] as List<dynamic>).first
                  as Map<String, dynamic>)['organization_id']
              as int;

      await SessionStore.writeToken(token);
      await SessionStore.writeOrganizationId(organizationId);

      const AnalyticsRepository analytics = AnalyticsRepository();
      final DateTimeRange window = DateTimeRange(
        start: DateTime(2026, 5, 1),
        end: DateTime(2026, 10, 21),
      );

      final AnalyticsOverview overview = await analytics.fetchOverview(
        organizationId: organizationId,
        range: window,
      );
      expect(overview.summary.totalClaims, greaterThanOrEqualTo(0));
      expect(overview.monthly, isNotEmpty);
      expect(overview.monthly.first.label, isNotEmpty);
      // The window the server answered for is the one that was asked for.
      expect(overview.fromDate, DateTime(2026, 5, 1));
      expect(overview.toDate, DateTime(2026, 10, 21));
      // The status slices always carry every status, in order.
      expect(
        overview.statusBreakdown.map((StatusSlice s) => s.status),
        <String>[
          'pending',
          'info_requested',
          'approved',
          'rejected',
          'reimbursed',
        ],
      );

      final PersonalAnalytics personal = await analytics.fetchPersonal(
        organizationId: organizationId,
        range: window,
      );
      expect(personal.summary.totalClaims, greaterThanOrEqualTo(0));
      // The personal view never reports more claims than the
      // organization holds.
      expect(
        personal.summary.totalClaims,
        lessThanOrEqualTo(overview.summary.totalClaims),
      );

      const AuditRepository audit = AuditRepository();
      final AuditPage page = await audit.fetchPage(limit: 5);
      expect(page.entries.length, lessThanOrEqualTo(5));
    });

    test('the analytics window is validated by the server', () async {
      if (!live) {
        markTestSkipped('Set LIVE_API=1 and run the backend to include this.');
        return;
      }
      final http.Response response = await ApiClient.post(
        '/auth/login',
        <String, String>{'email': kEmail, 'password': kPassword},
        auth: false,
      );
      final Map<String, dynamic> body =
          json.decode(response.body) as Map<String, dynamic>;
      await SessionStore.writeToken(body['access_token']?.toString() ?? '');
      final int organizationId =
          ((body['organizations'] as List<dynamic>).first
                  as Map<String, dynamic>)['organization_id']
              as int;

      final http.Response bad = await ApiClient.get(
        '/organizations/$organizationId/analytics/overview',
        query: <String, String>{'from': '2026-10-01', 'to': '2026-09-01'},
      );
      // The app's validation errors carry 422 (§22's error envelope).
      expect(bad.statusCode, 422);

      final http.Response tooLong = await ApiClient.get(
        '/organizations/$organizationId/analytics/overview',
        query: <String, String>{'from': '2020-01-01', 'to': '2026-09-01'},
      );
      expect(tooLong.statusCode, 422);
    });
  });
}
