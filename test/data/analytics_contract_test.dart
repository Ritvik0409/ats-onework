import 'dart:convert';
import 'dart:io';

import 'package:ats_onework/data/analytics_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// The analytics payloads are produced by the FastAPI service
/// (`backend/app/analytics/schemas.py`) and serialized into
/// `test/fixtures/` by `backend/scripts/generate_analytics_fixtures.py`.
/// Parsing the real server shape here means a renamed field breaks a test
/// instead of silently blanking a dashboard.
Map<String, dynamic> _fixture(String name) {
  final File file = File('test/fixtures/$name');
  return json.decode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  group('analytics contract', () {
    test('the overview payload parses into the client model', () {
      final AnalyticsOverview overview = AnalyticsOverview.fromJson(
        _fixture('analytics_overview.json'),
      );

      expect(overview.fromDate, DateTime(2026, 5, 1));
      expect(overview.toDate, DateTime(2026, 10, 20));

      // Money arrives as a decimal string; the client reads it as a double.
      expect(overview.summary.totalSpend, 482500.50);
      expect(overview.summary.pendingAmount, 91300.25);
      expect(overview.summary.approvedAmount, 245000);
      expect(overview.summary.reimbursedAmount, 237500.50);
      expect(overview.summary.totalClaims, 55);
      expect(overview.summary.avgApprovalDays, 2.4);
      expect(overview.summary.budgetAllocated, 600000);
      expect(overview.summary.budgetUtilisation, closeTo(0.8042, 0.0001));
      expect(overview.summary.previousSpend, 401000);
      expect(overview.summary.spendChangePct, 20.3);
      expect(overview.summary.openCount, 9);
      expect(overview.summary.openAmount, closeTo(106700.25, 0.01));

      expect(overview.monthly, hasLength(2));
      expect(overview.monthly.first.month, '2026-05');
      expect(overview.monthly.first.label, 'May');
      expect(overview.monthly.first.spend, 62000);

      expect(
        overview.categories.map((CategorySlice c) => c.name),
        containsAll(<String>['Travel', 'Meals', 'Software']),
      );
      expect(overview.projects.first.projectId, 7);
      expect(overview.projects.first.utilisation, closeTo(0.72, 0.001));
      expect(
        overview.aging.map((AgingBucket b) => b.label),
        contains('15+ days'),
      );
      expect(overview.topSpenders.first.name, 'Aarav Mehta');
      expect(overview.topSpenders.first.amount, 96400);

      expect(overview.reimbursements.openCount, 6);
      expect(overview.reimbursements.openAmount, 89500);
      expect(overview.reimbursements.paidAmount, 237500.50);
      expect(overview.reimbursements.avgPaymentDays, 3.1);

      expect(overview.statusBreakdown, hasLength(5));
      expect(overview.statusBreakdown.first.status, 'pending');
      expect(overview.statusBreakdown.first.amount, 91300.25);
    });

    test('the personal payload parses into the client model', () {
      final PersonalAnalytics personal = PersonalAnalytics.fromJson(
        _fixture('analytics_personal.json'),
      );

      expect(personal.summary.totalSpend, 48500);
      expect(personal.summary.pendingCount, 2);
      expect(personal.summary.infoRequestedCount, 1);
      expect(personal.summary.totalClaims, 18);
      expect(personal.monthly, hasLength(2));
      expect(personal.monthly.last.label, 'Oct');
      expect(personal.categories, hasLength(2));
      expect(personal.statusBreakdown, hasLength(5));
    });

    test('a missing section degrades instead of throwing', () {
      final AnalyticsOverview overview = AnalyticsOverview.fromJson(
        <String, dynamic>{'from_date': '2026-01-01', 'to_date': '2026-01-31'},
      );

      expect(overview.summary.totalSpend, 0);
      expect(overview.monthly, isEmpty);
      expect(overview.statusBreakdown, isEmpty);
      expect(overview.reimbursements.paidCount, 0);
    });
  });
}
