import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../core/formatting.dart';
import '../core/status.dart';
import '../management/expense_store.dart';
import '../shared/app_snack.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'download_stub.dart'
    if (dart.library.html) 'download_web.dart'
    as downloader;

/// The reimbursement report: what was paid, to whom, and when.
class ManagerReportsScreen extends StatefulWidget {
  const ManagerReportsScreen({super.key});

  @override
  State<ManagerReportsScreen> createState() => _ManagerReportsScreenState();
}

class _ManagerReportsScreenState extends State<ManagerReportsScreen> {
  static const List<String> _statuses = <String>[
    'All',
    'Pending',
    'Approved',
    'Paid',
    'Rejected',
  ];

  final ExpenseStore _store = ExpenseStore.instance;
  String _searchQuery = '';
  String _selectedStatus = 'All';
  DateTime? _selectedDate;

  List<ExpenseRecord> get _filteredExpenses {
    return _store.expenses
        .where((ExpenseRecord e) {
          final String query = _searchQuery.trim().toLowerCase();
          final bool matchesSearch =
              query.isEmpty ||
              e.name.toLowerCase().contains(query) ||
              e.id.toLowerCase().contains(query) ||
              e.type.toLowerCase().contains(query);
          if (!matchesSearch) return false;
          if (_selectedStatus != 'All' && e.status != _selectedStatus) {
            return false;
          }
          if (_selectedDate != null) {
            final DateTime? date = parseLooseDate(e.date);
            if (date == null ||
                date.month != _selectedDate!.month ||
                date.year != _selectedDate!.year) {
              return false;
            }
          }
          return true;
        })
        .toList(growable: false);
  }

  double get _totalAmount => _filteredExpenses.fold<double>(
    0,
    (double sum, ExpenseRecord e) => sum + e.amount,
  );

  void _downloadCsv() {
    final List<ExpenseRecord> rows = _filteredExpenses;
    if (rows.isEmpty) {
      AppSnack.error(context, 'No matching reimbursements to export.');
      return;
    }
    final StringBuffer csv = StringBuffer(
      'Tracking ID,Employee Name,Email,Expense Type,Amount,Date,Status\n',
    );
    for (final ExpenseRecord e in rows) {
      csv.writeln(
        <String>[
          _escapeCsv(e.id),
          _escapeCsv(e.name),
          _escapeCsv(e.email),
          _escapeCsv(e.type),
          e.amount.toStringAsFixed(2),
          _escapeCsv(e.date),
          _escapeCsv(e.status),
        ].join(','),
      );
    }
    final int timestamp = DateTime.now().millisecondsSinceEpoch;
    if (!kIsWeb) {
      AppSnack.info(context, 'CSV export is available in the web build only.');
      return;
    }
    downloader.downloadFile(
      utf8.encode(csv.toString()),
      'reimbursement_report_$timestamp.csv',
    );
    AppSnack.success(context, 'Report downloaded.');
  }

  static String _escapeCsv(String field) {
    if (field.contains(',') || field.contains('"') || field.contains('\n')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (BuildContext context, Widget? _) {
        final AppPalette palette = context.palette;
        final List<ExpenseRecord> rows = _filteredExpenses;

        return Scaffold(
          backgroundColor: palette.bg,
          appBar: AppBar(title: const Text('Reimbursement reports')),
          body: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    AppSearchField(
                      hint: 'Search by employee, id or type…',
                      onChanged: (String value) =>
                          setState(() => _searchQuery = value),
                    ),
                    const SizedBox(height: 12),
                    AppFilterBar(
                      options: _statuses,
                      value: _selectedStatus,
                      onChanged: (String status) =>
                          setState(() => _selectedStatus = status),
                    ),
                    const SizedBox(height: 12),
                    AppMonthFilter(
                      value: _selectedDate,
                      onChanged: (DateTime? date) =>
                          setState(() => _selectedDate = date),
                    ),
                    const SizedBox(height: 14),
                    AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Total reimbursed',
                                style: TextStyle(
                                  color: palette.muted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                formatMoney(_totalAmount),
                                style: TextStyle(
                                  color: palette.text,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: <Widget>[
                              Text(
                                'Records',
                                style: TextStyle(
                                  color: palette.muted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                formatCount(rows.length),
                                style: TextStyle(
                                  color: palette.gold,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: EmptyState(
                          icon: Icons.receipt_long_rounded,
                          title: 'No matching reimbursements',
                          message:
                              'Try another filter, another month, or clear '
                              'the search.',
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                        itemCount: rows.length,
                        separatorBuilder: (BuildContext context, int index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (BuildContext context, int index) {
                          final ExpenseRecord expense = rows[index];
                          final Color tone = statusColor(
                            expense.status,
                            palette,
                          );
                          return AppCard(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        expense.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: palette.text,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${expense.type} · ${expense.date}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: palette.muted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: <Widget>[
                                    Text(
                                      formatMoney(expense.amount),
                                      style: TextStyle(
                                        color: palette.text,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    StatusBadge(
                                      status: expense.status,
                                      color: tone,
                                      label: statusLabel(expense.status),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _downloadCsv,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text(
                      'Download CSV report',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
