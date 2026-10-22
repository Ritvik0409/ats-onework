import 'package:ats_onework/data/audit_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shape below is the live `GET /audit-logs` payload.
Map<String, dynamic> _payload() {
  return <String, dynamic>{
    'items': <Map<String, dynamic>>[
      <String, dynamic>{
        'log_id': 11,
        'actor_id': 2,
        'action': 'expense.submit',
        'table_name': 'expenses',
        'record_id': '3',
        'old_values': null,
        'new_values': <String, dynamic>{'amount': '1000', 'project_id': 1},
        'created_at': '2026-10-20T18:58:46.165405',
      },
      <String, dynamic>{
        'log_id': 10,
        'actor_id': null,
        'action': 'budget.update',
        'table_name': 'budgets',
        'record_id': '1',
        'old_values': <String, dynamic>{'amount': '5000'},
        'new_values': <String, dynamic>{'amount': '7000'},
        'created_at': '2026-10-20T17:15:55.565644',
      },
    ],
    'next_cursor': '10',
  };
}

void main() {
  group('audit entries', () {
    test('parse the fields the trail shows', () {
      final AuditEntry entry = AuditEntry.fromJson(_payload()['items'][0]);

      expect(entry.logId, 11);
      expect(entry.actorId, 2);
      expect(entry.action, 'expense.submit');
      expect(entry.tableName, 'expenses');
      expect(entry.recordId, '3');
      expect(entry.oldValues, isNull);
      expect(entry.newValues?['amount'], '1000');
      expect(entry.createdAt.year, 2026);
    });

    test('an entry without an actor still parses', () {
      final AuditEntry entry = AuditEntry.fromJson(_payload()['items'][1]);

      expect(entry.actorId, isNull);
      expect(entry.oldValues?['amount'], '5000');
    });

    test('the action reads as a sentence', () {
      expect(
        AuditEntry.fromJson(_payload()['items'][0]).readableAction,
        'Expense submitted',
      );
      expect(
        AuditEntry.fromJson(_payload()['items'][1]).readableAction,
        'Budget updated',
      );
    });
  });
}
