import 'package:flutter/material.dart';

import '../core/formatting.dart';
import '../shared/api_client.dart';
import 'analytics_repository.dart';

/// Loads one dashboard's analytics and owns its range selection.
///
/// Dashboards share this controller instead of each re-implementing
/// loading/error/refresh state. A newer request always wins, so tapping a
/// different range mid-flight cannot show the older answer.
class AnalyticsController extends ChangeNotifier {
  AnalyticsController({
    required this.personal,
    AnalyticsRange initialRange = AnalyticsRange.last6Months,
    this.repository = const AnalyticsRepository(),
  }) : _range = initialRange;

  final bool personal;
  final AnalyticsRepository repository;

  AnalyticsRange _range;
  AnalyticsOverview? overview;
  PersonalAnalytics? personalData;
  bool loading = false;
  bool loaded = false;
  String? error;

  int _requestId = 0;
  bool _disposed = false;

  AnalyticsRange get range => _range;

  DateTimeRange get window => _range.resolve(DateTime.now());

  Future<void> load() async {
    final int request = ++_requestId;
    loading = true;
    error = null;
    _notify();

    try {
      final int? organizationId = await _organizationId();
      if (organizationId == null) {
        throw const AnalyticsException(
          'You are not signed in to an organization.',
        );
      }
      final DateTimeRange range = _range.resolve(DateTime.now());
      if (personal) {
        final PersonalAnalytics result = await repository.fetchPersonal(
          organizationId: organizationId,
          range: range,
        );
        if (_isStale(request)) return;
        personalData = result;
      } else {
        final AnalyticsOverview result = await repository.fetchOverview(
          organizationId: organizationId,
          range: range,
        );
        if (_isStale(request)) return;
        overview = result;
      }
      error = null;
      loaded = true;
    } catch (exception) {
      if (_isStale(request)) return;
      error = exception is AnalyticsException
          ? exception.message
          : 'Could not load analytics. Check your connection and try again.';
      loaded = true;
    } finally {
      if (request == _requestId && !_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void selectRange(AnalyticsRange range) {
    if (_range == range) return;
    _range = range;
    load();
  }

  Future<int?> _organizationId() => ApiClient.getOrganizationId();

  bool _isStale(int request) => _disposed || request != _requestId;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
