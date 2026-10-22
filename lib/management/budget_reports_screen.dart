import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../core/formatting.dart';
import '../management/expense_store.dart';
import '../shared/app_snack.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'download_stub.dart'
    if (dart.library.html) 'download_web.dart'
    as downloader;

/// The budget report: what was allocated, what was spent and what is
/// left, month by month.
class BudgetReportsScreen extends StatefulWidget {
  const BudgetReportsScreen({super.key});

  @override
  State<BudgetReportsScreen> createState() => _BudgetReportsScreenState();
}

class _BudgetReportsScreenState extends State<BudgetReportsScreen> {
  final ExpenseStore _store = ExpenseStore.instance;
  String _searchQuery = '';
  DateTime? _selectedDate;

  /// Debounces the search field: reloading reads twelve months of
  /// budgets, so it must not run on every keystroke.
  Timer? _searchDebounce;

  List<Map<String, dynamic>> _cachedBudgetReports = <Map<String, dynamic>>[];
  bool _isLoadingReports = true;

  @override
  void initState() {
    super.initState();
    _loadBudgetHistory();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadBudgetHistory() async {
    if (!mounted) return;
    setState(() => _isLoadingReports = true);
    final List<Map<String, dynamic>> reports = <Map<String, dynamic>>[];
    final DateTime now = DateTime.now();

    // The twelve months are fetched together rather than one after the
    // other: they are independent reads, and doing them in sequence made
    // the report take twelve round-trips.
    final List<DateTime> months = List<DateTime>.generate(
      12,
      (int i) => DateTime(now.year, now.month - i),
    );
    // Coverage read: every period overlapping the month, so months
    // under the yearly seed allocation report the yearly amount without
    // an explicit monthly row. (The exact-month allocation read that
    // getBudgetForMonth performs is what the allocation screen edits,
    // not what a report should show.)
    final List<double> budgets = await Future.wait(
      months.map(_store.getBudgetCoverageForMonth),
    );

    for (int i = 0; i < months.length; i++) {
      final DateTime targetMonth = months[i];
      final String monthName = formatMonthLabelLong(targetMonth);

      final double budget = budgets[i];

      double spent = 0;
      for (final ExpenseRecord expense in _store.expenses) {
        // Spend is approved + reimbursed, matching the budgets API and
        // the analytics endpoint. Pending claims are not money out yet,
        // and counting them under-reported the remaining budget.
        if (expense.status != 'Approved' && expense.status != 'Paid') {
          continue;
        }
        // The API sends an ISO date ("2026-10-20"). Matching it against
        // a month abbreviation never matched, so every month reported a
        // spend of zero.
        final DateTime? expenseDate = _store.parseBackendDate(expense.date);
        if (expenseDate == null) continue;
        if (expenseDate.year == targetMonth.year &&
            expenseDate.month == targetMonth.month) {
          spent += expense.amount;
        }
      }

      final double variance = budget - spent;

      final String query = _searchQuery.trim().toLowerCase();
      if (query.isNotEmpty && !monthName.toLowerCase().contains(query)) {
        continue;
      }
      if (_selectedDate != null &&
          (targetMonth.year != _selectedDate!.year ||
              targetMonth.month != _selectedDate!.month)) {
        continue;
      }

      reports.add(<String, dynamic>{
        'month': monthName,
        'budget': budget,
        'spent': spent,
        'variance': variance,
      });
    }

    if (!mounted) return;
    setState(() {
      _cachedBudgetReports = reports;
      _isLoadingReports = false;
    });
  }

  double get _totalAllocatedBudget => _cachedBudgetReports.fold<double>(
    0,
    (double sum, Map<String, dynamic> r) => sum + (r['budget'] as double),
  );

  double get _totalSpentBudget => _cachedBudgetReports.fold<double>(
    0,
    (double sum, Map<String, dynamic> r) => sum + (r['spent'] as double),
  );

  void _downloadCsv() {
    if (_cachedBudgetReports.isEmpty) {
      AppSnack.error(context, 'No budget records match this filter.');
      return;
    }
    final StringBuffer csv = StringBuffer(
      'Fiscal Month,Allocated Budget (INR),Total Spent (INR),'
      'Remaining Variance (INR)\n',
    );
    for (final Map<String, dynamic> row in _cachedBudgetReports) {
      csv.writeln(
        <String>[
          '"${row['month']}"',
          (row['budget'] as double).toStringAsFixed(2),
          (row['spent'] as double).toStringAsFixed(2),
          (row['variance'] as double).toStringAsFixed(2),
        ].join(','),
      );
    }
    if (!kIsWeb) {
      AppSnack.info(context, 'CSV export is available in the web build only.');
      return;
    }
    final bool ok = downloader.downloadFile(
      utf8.encode(csv.toString()),
      'budget_allocation_report_${DateTime.now().millisecondsSinceEpoch}.csv',
    );
    // The downloader only signals success through its bool — the
    // snack must match what actually happened.
    if (ok) {
      AppSnack.success(context, 'Budget CSV report downloaded.');
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

        return Scaffold(
          backgroundColor: palette.bg,
          appBar: AppBar(title: const Text('Budget reports')),
          body: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    AppSearchField(
                      hint: 'Search fiscal month (e.g. August 2026)…',
                      onChanged: (String value) {
                        setState(() => _searchQuery = value);
                        // Debounced: the reload reads twelve months of
                        // budgets, so running it on every keystroke meant
                        // twelve sequential requests per character typed.
                        _searchDebounce?.cancel();
                        _searchDebounce = Timer(
                          const Duration(milliseconds: 300),
                          _loadBudgetHistory,
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    AppMonthFilter(
                      value: _selectedDate,
                      onChanged: (DateTime? date) {
                        setState(() => _selectedDate = date);
                        _loadBudgetHistory();
                      },
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
                                'Total allocated',
                                style: TextStyle(
                                  color: palette.muted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                formatMoney(_totalAllocatedBudget),
                                style: TextStyle(
                                  color: palette.text,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: <Widget>[
                              Text(
                                'Total spent',
                                style: TextStyle(
                                  color: palette.muted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                formatMoney(_totalSpentBudget),
                                style: TextStyle(
                                  color: palette.gold,
                                  fontSize: 18,
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
                child: _isLoadingReports
                    ? const Center(child: CircularProgressIndicator())
                    : _cachedBudgetReports.isEmpty
                    ? Center(
                        child: EmptyState(
                          icon: Icons.pie_chart_outline_rounded,
                          title: 'No budget records match',
                          message: 'Try another month or clear the search.',
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                        itemCount: _cachedBudgetReports.length,
                        separatorBuilder: (BuildContext context, int index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (BuildContext context, int index) {
                          final Map<String, dynamic> row =
                              _cachedBudgetReports[index];
                          final double budget = row['budget'] as double;
                          final double spent = row['spent'] as double;
                          final double variance = row['variance'] as double;

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
                                        row['month'] as String,
                                        style: TextStyle(
                                          color: palette.text,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Spent ${formatMoney(spent)} · '
                                        'left ${formatMoney(variance)}',
                                        style: TextStyle(
                                          color: variance < 0
                                              ? palette.danger
                                              : palette.muted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  formatMoney(budget),
                                  style: TextStyle(
                                    color: palette.gold,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
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
