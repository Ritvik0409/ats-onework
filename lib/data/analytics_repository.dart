import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/formatting.dart';
import '../shared/api_client.dart';

/// Analytics models + the HTTP calls that fill them.
///
/// Dashboards read aggregates from the server instead of summing the
/// first page of expenses, so figures stay correct as the organization
/// grows. Every value is tolerant of the backend's Decimal-as-string
/// serialization.

double _d(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _i(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double? _nullableD(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

class AnalyticsTotals {
  const AnalyticsTotals({
    this.totalSpend = 0,
    this.pendingCount = 0,
    this.pendingAmount = 0,
    this.infoRequestedCount = 0,
    this.infoRequestedAmount = 0,
    this.approvedCount = 0,
    this.approvedAmount = 0,
    this.rejectedCount = 0,
    this.rejectedAmount = 0,
    this.reimbursedCount = 0,
    this.reimbursedAmount = 0,
    this.totalClaims = 0,
    this.avgApprovalDays,
  });

  factory AnalyticsTotals.fromJson(Map<String, dynamic> json) =>
      AnalyticsTotals(
        totalSpend: _d(json['total_spend']),
        pendingCount: _i(json['pending_count']),
        pendingAmount: _d(json['pending_amount']),
        infoRequestedCount: _i(json['info_requested_count']),
        infoRequestedAmount: _d(json['info_requested_amount']),
        approvedCount: _i(json['approved_count']),
        approvedAmount: _d(json['approved_amount']),
        rejectedCount: _i(json['rejected_count']),
        rejectedAmount: _d(json['rejected_amount']),
        reimbursedCount: _i(json['reimbursed_count']),
        reimbursedAmount: _d(json['reimbursed_amount']),
        totalClaims: _i(json['total_claims']),
        avgApprovalDays: _nullableD(json['avg_approval_days']),
      );

  final double totalSpend;
  final int pendingCount;
  final double pendingAmount;
  final int infoRequestedCount;
  final double infoRequestedAmount;
  final int approvedCount;
  final double approvedAmount;
  final int rejectedCount;
  final double rejectedAmount;
  final int reimbursedCount;
  final double reimbursedAmount;
  final int totalClaims;
  final double? avgApprovalDays;

  int get openCount => pendingCount + infoRequestedCount;
  double get openAmount => pendingAmount + infoRequestedAmount;
}

class AnalyticsSummary extends AnalyticsTotals {
  const AnalyticsSummary({
    super.totalSpend,
    super.pendingCount,
    super.pendingAmount,
    super.infoRequestedCount,
    super.infoRequestedAmount,
    super.approvedCount,
    super.approvedAmount,
    super.rejectedCount,
    super.rejectedAmount,
    super.reimbursedCount,
    super.reimbursedAmount,
    super.totalClaims,
    super.avgApprovalDays,
    this.budgetAllocated = 0,
    this.budgetUtilisation = 0,
    this.previousSpend = 0,
    this.spendChangePct,
  });

  factory AnalyticsSummary.fromJson(Map<String, dynamic> json) =>
      AnalyticsSummary(
        totalSpend: _d(json['total_spend']),
        pendingCount: _i(json['pending_count']),
        pendingAmount: _d(json['pending_amount']),
        infoRequestedCount: _i(json['info_requested_count']),
        infoRequestedAmount: _d(json['info_requested_amount']),
        approvedCount: _i(json['approved_count']),
        approvedAmount: _d(json['approved_amount']),
        rejectedCount: _i(json['rejected_count']),
        rejectedAmount: _d(json['rejected_amount']),
        reimbursedCount: _i(json['reimbursed_count']),
        reimbursedAmount: _d(json['reimbursed_amount']),
        totalClaims: _i(json['total_claims']),
        avgApprovalDays: _nullableD(json['avg_approval_days']),
        budgetAllocated: _d(json['budget_allocated']),
        budgetUtilisation: _d(json['budget_utilisation']),
        previousSpend: _d(json['previous_spend']),
        spendChangePct: _nullableD(json['spend_change_pct']),
      );

  final double budgetAllocated;
  final double budgetUtilisation;
  final double previousSpend;
  final double? spendChangePct;

  double get budgetRemaining =>
      budgetAllocated > totalSpend ? budgetAllocated - totalSpend : 0;
}

class MonthlyPoint {
  const MonthlyPoint({
    required this.month,
    required this.label,
    this.spend = 0,
    this.budget = 0,
    this.pendingCount = 0,
    this.pendingAmount = 0,
    this.approvedCount = 0,
    this.approvedAmount = 0,
    this.rejectedCount = 0,
    this.rejectedAmount = 0,
  });

  factory MonthlyPoint.fromJson(Map<String, dynamic> json) => MonthlyPoint(
    month: json['month']?.toString() ?? '',
    label: json['label']?.toString() ?? '',
    spend: _d(json['spend']),
    budget: _d(json['budget']),
    pendingCount: _i(json['pending_count']),
    pendingAmount: _d(json['pending_amount']),
    approvedCount: _i(json['approved_count']),
    approvedAmount: _d(json['approved_amount']),
    rejectedCount: _i(json['rejected_count']),
    rejectedAmount: _d(json['rejected_amount']),
  );

  final String month;
  final String label;
  final double spend;
  final double budget;
  final int pendingCount;
  final double pendingAmount;
  final int approvedCount;
  final double approvedAmount;
  final int rejectedCount;
  final double rejectedAmount;
}

class CategorySlice {
  const CategorySlice({required this.name, this.amount = 0, this.count = 0});

  factory CategorySlice.fromJson(Map<String, dynamic> json) => CategorySlice(
    name: json['name']?.toString() ?? 'Uncategorised',
    amount: _d(json['amount']),
    count: _i(json['count']),
  );

  final String name;
  final double amount;
  final int count;
}

class ProjectSlice {
  const ProjectSlice({
    required this.projectId,
    required this.name,
    this.amount = 0,
    this.budget = 0,
    this.count = 0,
  });

  factory ProjectSlice.fromJson(Map<String, dynamic> json) => ProjectSlice(
    projectId: _i(json['project_id']),
    name: json['name']?.toString() ?? 'Unnamed project',
    amount: _d(json['amount']),
    budget: _d(json['budget']),
    count: _i(json['count']),
  );

  final int projectId;
  final String name;
  final double amount;
  final double budget;
  final int count;

  double get utilisation =>
      budget > 0 ? (amount / budget).clamp(0.0, 1.0) : 0.0;
}

class AgingBucket {
  const AgingBucket({required this.label, this.count = 0, this.amount = 0});

  factory AgingBucket.fromJson(Map<String, dynamic> json) => AgingBucket(
    label: json['label']?.toString() ?? '',
    count: _i(json['count']),
    amount: _d(json['amount']),
  );

  final String label;
  final int count;
  final double amount;
}

class TopSpender {
  const TopSpender({
    required this.employeeId,
    required this.name,
    this.amount = 0,
    this.count = 0,
  });

  factory TopSpender.fromJson(Map<String, dynamic> json) => TopSpender(
    employeeId: _i(json['employee_id']),
    name: json['name']?.toString() ?? 'Unknown',
    amount: _d(json['amount']),
    count: _i(json['count']),
  );

  final int employeeId;
  final String name;
  final double amount;
  final int count;
}

class ReimbursementStats {
  const ReimbursementStats({
    this.pendingCount = 0,
    this.pendingAmount = 0,
    this.processingCount = 0,
    this.processingAmount = 0,
    this.paidCount = 0,
    this.paidAmount = 0,
    this.failedCount = 0,
    this.failedAmount = 0,
    this.avgPaymentDays,
  });

  factory ReimbursementStats.fromJson(Map<String, dynamic> json) =>
      ReimbursementStats(
        pendingCount: _i(json['pending_count']),
        pendingAmount: _d(json['pending_amount']),
        processingCount: _i(json['processing_count']),
        processingAmount: _d(json['processing_amount']),
        paidCount: _i(json['paid_count']),
        paidAmount: _d(json['paid_amount']),
        failedCount: _i(json['failed_count']),
        failedAmount: _d(json['failed_amount']),
        avgPaymentDays: _nullableD(json['avg_payment_days']),
      );

  final int pendingCount;
  final double pendingAmount;
  final int processingCount;
  final double processingAmount;
  final int paidCount;
  final double paidAmount;
  final int failedCount;
  final double failedAmount;
  final double? avgPaymentDays;

  double get openAmount => pendingAmount + processingAmount;
  int get openCount => pendingCount + processingCount;
}

class StatusSlice {
  const StatusSlice({
    required this.status,
    required this.label,
    this.count = 0,
    this.amount = 0,
  });

  factory StatusSlice.fromJson(Map<String, dynamic> json) => StatusSlice(
    status: json['status']?.toString() ?? '',
    label: json['label']?.toString() ?? '',
    count: _i(json['count']),
    amount: _d(json['amount']),
  );

  final String status;
  final String label;
  final int count;
  final double amount;
}

class AnalyticsOverview {
  const AnalyticsOverview({
    required this.fromDate,
    required this.toDate,
    required this.summary,
    this.monthly = const [],
    this.categories = const [],
    this.projects = const [],
    this.aging = const [],
    this.topSpenders = const [],
    this.reimbursements = const ReimbursementStats(),
    this.statusBreakdown = const [],
  });

  factory AnalyticsOverview.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> map = json;
    return AnalyticsOverview(
      fromDate:
          parseLooseDate(map['from_date']?.toString() ?? '') ?? DateTime.now(),
      toDate:
          parseLooseDate(map['to_date']?.toString() ?? '') ?? DateTime.now(),
      summary: AnalyticsSummary.fromJson(
        (map['summary'] as Map<String, dynamic>?) ?? const {},
      ),
      monthly: _list(map['monthly'], MonthlyPoint.fromJson),
      categories: _list(map['categories'], CategorySlice.fromJson),
      projects: _list(map['projects'], ProjectSlice.fromJson),
      aging: _list(map['aging'], AgingBucket.fromJson),
      topSpenders: _list(map['top_spenders'], TopSpender.fromJson),
      reimbursements: ReimbursementStats.fromJson(
        (map['reimbursements'] as Map<String, dynamic>?) ?? const {},
      ),
      statusBreakdown: _list(map['status_breakdown'], StatusSlice.fromJson),
    );
  }

  final DateTime fromDate;
  final DateTime toDate;
  final AnalyticsSummary summary;
  final List<MonthlyPoint> monthly;
  final List<CategorySlice> categories;
  final List<ProjectSlice> projects;
  final List<AgingBucket> aging;
  final List<TopSpender> topSpenders;
  final ReimbursementStats reimbursements;
  final List<StatusSlice> statusBreakdown;
}

class PersonalAnalytics {
  const PersonalAnalytics({
    required this.fromDate,
    required this.toDate,
    required this.summary,
    this.monthly = const [],
    this.categories = const [],
    this.statusBreakdown = const [],
  });

  factory PersonalAnalytics.fromJson(
    Map<String, dynamic> json,
  ) => PersonalAnalytics(
    fromDate:
        parseLooseDate(json['from_date']?.toString() ?? '') ?? DateTime.now(),
    toDate: parseLooseDate(json['to_date']?.toString() ?? '') ?? DateTime.now(),
    summary: AnalyticsTotals.fromJson(
      (json['summary'] as Map<String, dynamic>?) ?? const {},
    ),
    monthly: _list(json['monthly'], MonthlyPoint.fromJson),
    categories: _list(json['categories'], CategorySlice.fromJson),
    statusBreakdown: _list(json['status_breakdown'], StatusSlice.fromJson),
  );

  final DateTime fromDate;
  final DateTime toDate;
  final AnalyticsTotals summary;
  final List<MonthlyPoint> monthly;
  final List<CategorySlice> categories;
  final List<StatusSlice> statusBreakdown;
}

List<T> _list<T>(dynamic raw, T Function(Map<String, dynamic>) build) {
  if (raw is! List) return <T>[];
  return raw
      .whereType<Map<String, dynamic>>()
      .map(build)
      .toList(growable: false);
}

class AnalyticsException implements Exception {
  const AnalyticsException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AnalyticsRepository {
  const AnalyticsRepository();

  Future<AnalyticsOverview> fetchOverview({
    required int organizationId,
    required DateTimeRange range,
  }) async {
    final http.Response response = await ApiClient.get(
      '/organizations/$organizationId/analytics/overview',
      query: {'from': isoDate(range.start), 'to': isoDate(range.end)},
    );
    final Map<String, dynamic> body = _body(response);
    return AnalyticsOverview.fromJson(body);
  }

  Future<PersonalAnalytics> fetchPersonal({
    required int organizationId,
    required DateTimeRange range,
  }) async {
    final http.Response response = await ApiClient.get(
      '/organizations/$organizationId/analytics/me',
      query: {'from': isoDate(range.start), 'to': isoDate(range.end)},
    );
    final Map<String, dynamic> body = _body(response);
    return PersonalAnalytics.fromJson(body);
  }

  Map<String, dynamic> _body(http.Response response) {
    Map<String, dynamic> decoded = const {};
    try {
      final Object? raw = json.decode(response.body);
      if (raw is Map<String, dynamic>) decoded = raw;
    } catch (_) {
      // Fall through to the status-based message.
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }
    final Object? error = decoded['error'];
    final String message = error is Map<String, dynamic>
        ? (error['message']?.toString() ?? '')
        : '';
    throw AnalyticsException(
      message.isNotEmpty
          ? message
          : 'Could not load analytics (${response.statusCode}).',
    );
  }
}
