import 'package:http/http.dart' as http;

import '../shared/api_client.dart';

/// One entry of the organization's audit trail.
class AuditEntry {
  const AuditEntry({
    required this.logId,
    required this.action,
    required this.tableName,
    required this.recordId,
    required this.actorId,
    required this.createdAt,
    this.oldValues,
    this.newValues,
  });

  factory AuditEntry.fromJson(Map<String, dynamic> json) {
    return AuditEntry(
      logId: _int(json['log_id']),
      action: json['action']?.toString() ?? '',
      tableName: json['table_name']?.toString() ?? '',
      recordId: json['record_id']?.toString() ?? '',
      actorId: json['actor_id'] == null ? null : _int(json['actor_id']),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      oldValues: _values(json['old_values']),
      newValues: _values(json['new_values']),
    );
  }

  final int logId;
  final String action;
  final String tableName;
  final String recordId;
  final int? actorId;
  final DateTime createdAt;

  /// The values before the change, when there were any.
  final Map<String, dynamic>? oldValues;

  /// The values after the change, when there were any.
  final Map<String, dynamic>? newValues;

  /// "expense.submit" reads better as "Expense submitted".
  String get readableAction {
    final List<String> parts = action.split('.');
    if (parts.length < 2) return action;
    final String subject = parts.first.replaceAll('_', ' ');
    final String verb = parts.last.replaceAll('_', ' ');
    return '${subject[0].toUpperCase()}${subject.substring(1)} '
        '${_pastTense[verb] ?? verb}';
  }

  static const Map<String, String> _pastTense = <String, String>{
    'submit': 'submitted',
    'update': 'updated',
    'create': 'created',
    'add': 'added',
    'remove': 'removed',
    'register': 'registered',
    'delete': 'deleted',
    'approve': 'approved',
    'reject': 'rejected',
    'pay': 'paid',
  };

  static int _int(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static Map<String, dynamic>? _values(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    return null;
  }
}

/// One page of the audit trail.
class AuditPage {
  const AuditPage({required this.entries, this.nextCursor});

  final List<AuditEntry> entries;

  /// The cursor of the next page, or null when the trail is exhausted.
  final String? nextCursor;
}

/// Reads the organization's audit trail (`GET /audit-logs`).
///
/// The endpoint is admin-only and cursor-paginated, like the expense
/// list — the screen walks it with [fetchAuditPage].
class AuditRepository {
  const AuditRepository();

  Future<AuditPage> fetchPage({
    String? cursor,
    String? tableName,
    int limit = 50,
  }) async {
    final Map<String, String> query = <String, String>{'limit': '$limit'};
    if (cursor != null) query['cursor'] = cursor;
    if (tableName != null) query['table_name'] = tableName;

    final http.Response response = await ApiClient.get(
      '/audit-logs',
      query: query,
    );
    final List<dynamic> items = ApiClient.pageItems(response);
    return AuditPage(
      entries: items
          .whereType<Map<String, dynamic>>()
          .map(AuditEntry.fromJson)
          .toList(growable: false),
      nextCursor: ApiClient.pageCursor(response),
    );
  }
}
