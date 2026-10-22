import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../core/formatting.dart';
import '../core/status.dart';
import '../management/download_stub.dart'
    if (dart.library.html) '../management/download_web.dart'
    as downloader;
import '../management/expense_store.dart';
import '../shared/app_snack.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// A report over the expense ledger: one status, a search box, a
/// timeframe and the rows.
///
/// The paid report and the pending-payout report were two screens with
/// the same body and one different line — the status they filter by.
/// They are one widget now.
class ReimbursementReportScreen extends StatefulWidget {
  const ReimbursementReportScreen({
    super.key,
    required this.title,
    required this.status,
    required this.emptyTitle,
    required this.exportName,
  });

  final String title;

  /// The claim status this report covers ('Paid', 'Approved', …).
  final String status;
  final String emptyTitle;

  /// The name of the CSV file (without the timestamp).
  final String exportName;

  @override
  State<ReimbursementReportScreen> createState() =>
      _ReimbursementReportScreenState();
}

class _ReimbursementReportScreenState extends State<ReimbursementReportScreen> {
  static const List<String> _timeframes = <String>[
    'All time',
    'This month',
    'Last 3 months',
  ];

  final ExpenseStore _store = ExpenseStore.instance;
  String _searchQuery = '';
  String _timeframe = 'All time';

  /// Delegates parsing to the store's single backend date parser; only
  /// the timeframe matching lives here.
  bool _matchesTimeframe(String dateStr) {
    if (_timeframe == 'All time') return true;
    final DateTime? date = _store.parseBackendDate(dateStr);
    if (date == null) return false;
    final DateTime now = DateTime.now();
    if (_timeframe == 'This month') {
      return date.year == now.year && date.month == now.month;
    }
    final DateTime threeMonthsAgo = DateTime(now.year, now.month - 3, now.day);
    return !date.isBefore(threeMonthsAgo);
  }

  List<ExpenseRecord> _rows() {
    final String query = _searchQuery.trim().toLowerCase();
    return _store.expenses
        .where((ExpenseRecord expense) {
          if (expense.status != widget.status) return false;
          if (!_matchesTimeframe(expense.date)) return false;
          if (query.isEmpty) return true;
          return expense.name.toLowerCase().contains(query) ||
              expense.id.toLowerCase().contains(query) ||
              expense.type.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  /// Escapes one CSV field: a comma, quote or newline inside a value
  /// (an employee name, an email…) would otherwise shift the columns
  /// of that row and every row after it.
  String _csvField(String value) {
    if (!value.contains(',') && !value.contains('"') && !value.contains('\n')) {
      return value;
    }
    return '"${value.replaceAll('"', '""')}"';
  }

  void _downloadCsv(List<ExpenseRecord> rows) {
    if (rows.isEmpty) {
      AppSnack.error(context, 'Nothing to export for this filter.');
      return;
    }
    final StringBuffer csv = StringBuffer(
      'Tracking ID,Employee Name,Email,Expense Type,Amount,Date,Status\n',
    );
    for (final ExpenseRecord expense in rows) {
      csv.writeln(
        <String>[
          _csvField(expense.id),
          _csvField(expense.name),
          _csvField(expense.email),
          _csvField(expense.type),
          _csvField(expense.amount.toStringAsFixed(2)),
          _csvField(expense.date),
          _csvField(expense.status),
        ].join(','),
      );
    }
    if (!kIsWeb) {
      AppSnack.info(context, 'CSV export is available in the web build only.');
      return;
    }
    final bool ok = downloader.downloadFile(
      utf8.encode(csv.toString()),
      '${widget.exportName}_${DateTime.now().millisecondsSinceEpoch}.csv',
    );
    // The downloader only signals success through its bool — the
    // snack must match what actually happened.
    if (ok) {
      AppSnack.success(context, 'Report downloaded.');
    } else {
      AppSnack.error(context, "Couldn't generate the report. Try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (BuildContext context, Widget? _) {
        final AppPalette palette = context.palette;
        final List<ExpenseRecord> rows = _rows();
        final double total = rows.fold<double>(
          0,
          (double sum, ExpenseRecord expense) => sum + expense.amount,
        );

        return Scaffold(
          backgroundColor: palette.bg,
          appBar: AppBar(title: Text(widget.title)),
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
                      options: _timeframes,
                      value: _timeframe,
                      onChanged: (String value) =>
                          setState(() => _timeframe = value),
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
                                'Total value',
                                style: TextStyle(
                                  color: palette.muted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                formatMoney(total),
                                style: TextStyle(
                                  color: palette.text,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                          AppTag(
                            label:
                                '${rows.length} claim'
                                '${rows.length == 1 ? '' : 's'}',
                            icon: Icons.receipt_long_rounded,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                // The store gates the list: first load in flight, the
                // load failed (with the reason in expensesError) and
                // only then empty-vs-data.
                child: !_store.expensesLoaded
                    ? const Center(child: CircularProgressIndicator())
                    : _store.expensesError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: EmptyState(
                            icon: Icons.cloud_off_rounded,
                            title: "Couldn't load claims",
                            message: _store.expensesError,
                            action: FilledButton.icon(
                              onPressed: () =>
                                  _store.fetchExpensesFromBackend(),
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('Retry'),
                            ),
                          ),
                        ),
                      )
                    : rows.isEmpty
                    ? RefreshIndicator(
                        // Pull-to-refresh must work on the empty state
                        // too, and a RefreshIndicator only reacts to
                        // the scroll notifications of a scrollable
                        // child — so the empty state is one.
                        onRefresh: () => _store.fetchExpensesFromBackend(),
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: <Widget>[
                            const SizedBox(height: 60),
                            Center(
                              child: EmptyState(
                                icon: Icons.receipt_long_rounded,
                                title: widget.emptyTitle,
                                message:
                                    'Try another timeframe or clear the '
                                    'search.',
                              ),
                            ),
                          ],
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
                    onPressed: () => _downloadCsv(rows),
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
