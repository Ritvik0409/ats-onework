// Finance hub screens - pending payouts ("To Pay") and settled
// reimbursements ("Paid"), plus their time-filtered report screens.
// Split out of the old management-only navigation shell when the two
// portals merged into the single capability-driven portal shell.

import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:ats_onework/management/download_stub.dart'
    if (dart.library.html) 'package:ats_onework/management/download_web.dart';
import 'package:ats_onework/core/formatting.dart';
import 'package:ats_onework/management/expense_details.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/shared/load_more.dart';
import 'package:ats_onework/ui/expense_row.dart';
import 'package:ats_onework/ui/tokens.dart';
import 'package:ats_onework/ui/widgets.dart';

/// Claims that are approved and waiting to be paid out.
class FinanceToPayScreen extends StatefulWidget {
  const FinanceToPayScreen({super.key});

  @override
  State<FinanceToPayScreen> createState() => _FinanceToPayScreenState();
}

class _FinanceToPayScreenState extends State<FinanceToPayScreen> {
  final ExpenseStore _store = ExpenseStore.instance;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (BuildContext context, Widget? _) {
        final AppPalette palette = context.palette;

        final List<ExpenseRecord> approved = _store.expenses
            .where(
              (ExpenseRecord expense) =>
                  expense.status == 'Approved' && _matches(expense),
            )
            .toList(growable: false);

        final double total = approved.fold<double>(
          0,
          (double sum, ExpenseRecord expense) => sum + expense.amount,
        );

        return Scaffold(
          backgroundColor: palette.bg,
          appBar: AppBar(
            title: const Text('To pay'),
            actions: <Widget>[
              IconButton(
                tooltip: 'Reports',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) =>
                        const FinanceReportsScreen(),
                  ),
                ),
                icon: const Icon(Icons.bar_chart_rounded),
              ),
            ],
          ),
          body: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
                child: Column(
                  children: <Widget>[
                    AppSearchField(
                      hint: 'Search approved claims by employee, id or type…',
                      onChanged: (String value) =>
                          setState(() => _searchQuery = value),
                    ),
                    const SizedBox(height: 14),
                    AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Waiting for payout',
                                  style: TextStyle(
                                    color: palette.muted,
                                    fontSize: 12.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  formatMoney(total),
                                  style: TextStyle(
                                    color: palette.text,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          AppTag(
                            label:
                                '${approved.length} claim${approved.length == 1 ? '' : 's'}',
                            icon: Icons.account_balance_wallet_rounded,
                            color: palette.warning,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: !_store.expensesLoaded
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: () => _store.fetchExpensesFromBackend(),
                        child: approved.isEmpty
                            // A RefreshIndicator only reacts to the scroll
                            // notifications of a scrollable child, so the
                            // empty state has to be one too — otherwise
                            // pull-to-refresh does nothing exactly when
                            // it is wanted.
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: <Widget>[
                                  const SizedBox(height: 60),
                                  EmptyState(
                                    icon: Icons.task_alt_rounded,
                                    title: 'Inbox zero',
                                    message:
                                        'Every approved claim has been paid.',
                                  ),
                                ],
                              )
                            : ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  0,
                                  18,
                                  32,
                                ),
                                // One extra row for the "load more"
                                // footer, so a list longer than one page
                                // can be walked through.
                                itemCount:
                                    approved.length +
                                    (_store.hasMoreExpenses ? 1 : 0),
                                separatorBuilder:
                                    (BuildContext context, int index) =>
                                        const SizedBox(height: 10),
                                itemBuilder: (BuildContext context, int index) {
                                  if (index >= approved.length) {
                                    return LoadMoreFooter(
                                      hasMore: _store.hasMoreExpenses,
                                      loading: _store.expensesLoadingMore,
                                      onLoad: _store.loadMoreExpenses,
                                    );
                                  }
                                  final ExpenseRecord expense = approved[index];
                                  return ExpenseRow(
                                    expense: expense,
                                    showId: true,
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (BuildContext context) =>
                                            ExpenseDetailsScreen(
                                              expenseId: expense.id,
                                            ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _matches(ExpenseRecord expense) {
    final String query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return true;
    return expense.name.toLowerCase().contains(query) ||
        expense.id.toLowerCase().contains(query) ||
        expense.type.toLowerCase().contains(query);
  }
}

/// Claims that have been paid out.
class PaidReimbursementsScreen extends StatefulWidget {
  const PaidReimbursementsScreen({super.key});

  @override
  State<PaidReimbursementsScreen> createState() =>
      _PaidReimbursementsScreenState();
}

class _PaidReimbursementsScreenState extends State<PaidReimbursementsScreen> {
  final ExpenseStore _store = ExpenseStore.instance;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (BuildContext context, Widget? _) {
        final AppPalette palette = context.palette;

        final List<ExpenseRecord> paid = _store.expenses
            .where(
              (ExpenseRecord expense) =>
                  expense.status == 'Paid' && _matches(expense),
            )
            .toList(growable: false);

        final double total = paid.fold<double>(
          0,
          (double sum, ExpenseRecord expense) => sum + expense.amount,
        );

        return Scaffold(
          backgroundColor: palette.bg,
          appBar: AppBar(
            title: const Text('Paid'),
            actions: <Widget>[
              IconButton(
                tooltip: 'Reports',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) =>
                        const PaidReportsScreen(),
                  ),
                ),
                icon: const Icon(Icons.bar_chart_rounded),
              ),
            ],
          ),
          body: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
                child: Column(
                  children: <Widget>[
                    AppSearchField(
                      hint: 'Search paid claims by employee, id or type…',
                      onChanged: (String value) =>
                          setState(() => _searchQuery = value),
                    ),
                    const SizedBox(height: 14),
                    AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Total settled & disbursed',
                                  style: TextStyle(
                                    color: palette.muted,
                                    fontSize: 12.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  formatMoney(total),
                                  style: TextStyle(
                                    color: palette.text,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          AppTag(
                            label: '${paid.length} paid',
                            icon: Icons.verified_rounded,
                            color: palette.success,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: !_store.expensesLoaded
                    ? const Center(child: CircularProgressIndicator())
                    : paid.isEmpty
                    ? Center(
                        child: EmptyState(
                          icon: Icons.payments_outlined,
                          title: 'No paid claims yet',
                          message:
                              'Reimbursements appear here once they are '
                              'marked as paid.',
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
                        itemCount: paid.length,
                        separatorBuilder: (BuildContext context, int index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (BuildContext context, int index) {
                          final ExpenseRecord expense = paid[index];
                          return ExpenseRow(
                            expense: expense,
                            showId: true,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (BuildContext context) =>
                                    ExpenseDetailsScreen(expenseId: expense.id),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _matches(ExpenseRecord expense) {
    final String query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return true;
    return expense.name.toLowerCase().contains(query) ||
        expense.id.toLowerCase().contains(query) ||
        expense.type.toLowerCase().contains(query);
  }
}

class PaidReportsScreen extends StatefulWidget {
  const PaidReportsScreen({super.key});
  @override
  State<PaidReportsScreen> createState() => _PaidReportsScreenState();
}

class _PaidReportsScreenState extends State<PaidReportsScreen> {
  String _searchQuery = '';
  String _selectedTimeframe = 'All Time';

  // Delegates parsing to the store's single backend date parser (legacy
  // "5 Jan 2026" and ISO "2026-01-05" both supported); only the
  // timeframe matching lives here.
  bool _matchesTimeframe(String dateStr) {
    if (_selectedTimeframe == 'All Time') return true;
    final d = ExpenseStore.instance.parseBackendDate(dateStr);
    if (d == null) return false;
    final now = DateTime.now();
    if (_selectedTimeframe == 'This Month') {
      return d.year == now.year && d.month == now.month;
    } else if (_selectedTimeframe == 'Last 3 Months') {
      final threeMonthsAgo = DateTime(now.year, now.month - 3, now.day);
      return d.isAfter(threeMonthsAgo) || d.isAtSameMomentAs(threeMonthsAgo);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final obsidianBlack = store.bg;
        final darkCharcoal = store.card;
        final champagneGold = store.accentGold;
        final textFrost = store.textFrost;
        final textMuted = store.textMuted;

        final paidExpenses = store.expenses.where((e) {
          if (e.status != 'Paid') return false;
          if (!_matchesTimeframe(e.date)) return false;

          final q = _searchQuery.toLowerCase();
          return e.name.toLowerCase().contains(q) ||
              e.id.toLowerCase().contains(q) ||
              e.type.toLowerCase().contains(q);
        }).toList();

        final totalAmount = paidExpenses.fold(
          0.0,
          (sum, item) => sum + item.amount,
        );

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: darkCharcoal,
            title: Text(
              'Paid Reimbursements Report',
              style: TextStyle(color: textFrost, fontWeight: FontWeight.bold),
            ),
            iconTheme: IconThemeData(color: textFrost),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(
                color: champagneGold.withValues(alpha: 0.15),
                height: 1,
              ),
            ),
          ),
          body: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 800),
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  TextField(
                    onChanged: (value) => setState(() => _searchQuery = value),
                    style: TextStyle(color: textFrost),
                    decoration: InputDecoration(
                      hintText: 'Search by employee name, ID or type...',
                      hintStyle: TextStyle(color: textMuted, fontSize: 14),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: champagneGold,
                        size: 22,
                      ),
                      filled: true,
                      fillColor: darkCharcoal,
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: champagneGold.withValues(alpha: 0.15),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: champagneGold,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: obsidianBlack,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.fromBorderSide(
                            BorderSide(
                              color: champagneGold.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            dropdownColor: darkCharcoal,
                            value: _selectedTimeframe,
                            icon: Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Icon(
                                Icons.arrow_drop_down,
                                color: champagneGold,
                              ),
                            ),
                            items:
                                <String>[
                                  'All Time',
                                  'This Month',
                                  'Last 3 Months',
                                ].map((String value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.calendar_month_rounded,
                                          color: champagneGold,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          value,
                                          style: TextStyle(
                                            color: textFrost,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                            onChanged: (newValue) {
                              if (newValue != null) {
                                setState(() => _selectedTimeframe = newValue);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: darkCharcoal,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.fromBorderSide(
                        BorderSide(color: store.border, width: 1),
                      ),
                      boxShadow: [
                        if (!store.isDarkMode)
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total reimbursed',
                              style: TextStyle(color: textMuted, fontSize: 13),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '₹${totalAmount.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: textFrost,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Records',
                              style: TextStyle(color: textMuted, fontSize: 13),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${paidExpenses.length}',
                              style: TextStyle(
                                color: champagneGold,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: !store.expensesLoaded
                        ? const Center(child: CircularProgressIndicator())
                        : paidExpenses.isEmpty
                        ? Center(
                            child: Text(
                              'No matching paid records found.',
                              style: TextStyle(color: textMuted),
                            ),
                          )
                        : ListView.builder(
                            itemCount: paidExpenses.length,
                            itemBuilder: (context, index) {
                              final expense = paidExpenses[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: darkCharcoal,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.fromBorderSide(
                                    BorderSide(color: store.border, width: 1),
                                  ),
                                  boxShadow: [
                                    if (!store.isDarkMode)
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.03,
                                        ),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          expense.name,
                                          style: TextStyle(
                                            color: textFrost,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${expense.type} • ${expense.date}',
                                          style: TextStyle(
                                            color: textMuted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      expense.amountFormatted,
                                      style: TextStyle(
                                        color: champagneGold,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: champagneGold,
                        foregroundColor: store.isDarkMode
                            ? obsidianBlack
                            : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        if (paidExpenses.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('No records to download.'),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                          return;
                        }

                        String csvContent =
                            "Employee Name,Expense ID,Type,Amount,Date Settled,Status\n";
                        for (var exp in paidExpenses) {
                          final cleanName = exp.name.replaceAll(',', '');
                          csvContent +=
                              "$cleanName,${exp.id},${exp.type},${exp.amount},${exp.date},Paid\n";
                        }
                        final bytes = utf8.encode(csvContent);

                        try {
                          final timestamp =
                              DateTime.now().millisecondsSinceEpoch;
                          final downloaded = downloadFile(
                            bytes,
                            'Paid_Reimbursements_$timestamp.csv',
                          );

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                downloaded
                                    ? 'Download started!'
                                    : 'CSV export is available in the web build.',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              backgroundColor: champagneGold,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error downloading file: $e'),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                        }
                      },
                      icon: Icon(Icons.download_rounded, size: 20),
                      label: Text(
                        'Download CSV Report',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class FinanceReportsScreen extends StatefulWidget {
  const FinanceReportsScreen({super.key});
  @override
  State<FinanceReportsScreen> createState() => _FinanceReportsScreenState();
}

class _FinanceReportsScreenState extends State<FinanceReportsScreen> {
  String _searchQuery = '';
  String _selectedTimeframe = 'All Time';

  // Delegates parsing to the store's single backend date parser; only the
  // timeframe matching lives here.
  bool _matchesTimeframe(String dateStr) {
    if (_selectedTimeframe == 'All Time') return true;
    final d = ExpenseStore.instance.parseBackendDate(dateStr);
    if (d == null) return false;
    final now = DateTime.now();
    if (_selectedTimeframe == 'This Month') {
      return d.year == now.year && d.month == now.month;
    } else if (_selectedTimeframe == 'Last 3 Months') {
      final threeMonthsAgo = DateTime(now.year, now.month - 3, now.day);
      return d.isAfter(threeMonthsAgo) || d.isAtSameMomentAs(threeMonthsAgo);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final obsidianBlack = store.bg;
        final darkCharcoal = store.card;
        final champagneGold = store.accentGold;
        final textFrost = store.textFrost;
        final textMuted = store.textMuted;

        final pendingPayouts = store.expenses.where((e) {
          if (e.status != 'Approved') return false;
          if (!_matchesTimeframe(e.date)) return false;

          final q = _searchQuery.toLowerCase();
          return e.name.toLowerCase().contains(q) ||
              e.id.toLowerCase().contains(q) ||
              e.type.toLowerCase().contains(q);
        }).toList();

        final totalAmount = pendingPayouts.fold(
          0.0,
          (sum, item) => sum + item.amount,
        );

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: darkCharcoal,
            title: Text(
              'Pending Payouts Report',
              style: TextStyle(color: textFrost, fontWeight: FontWeight.bold),
            ),
            iconTheme: IconThemeData(color: textFrost),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(
                color: champagneGold.withValues(alpha: 0.15),
                height: 1,
              ),
            ),
          ),
          body: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 800),
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  TextField(
                    onChanged: (value) => setState(() => _searchQuery = value),
                    style: TextStyle(color: textFrost),
                    decoration: InputDecoration(
                      hintText: 'Search by employee name, ID or type...',
                      hintStyle: TextStyle(color: textMuted, fontSize: 14),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: champagneGold,
                        size: 22,
                      ),
                      filled: true,
                      fillColor: darkCharcoal,
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: champagneGold.withValues(alpha: 0.15),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: champagneGold,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: obsidianBlack,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.fromBorderSide(
                            BorderSide(
                              color: champagneGold.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            dropdownColor: darkCharcoal,
                            value: _selectedTimeframe,
                            icon: Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Icon(
                                Icons.arrow_drop_down,
                                color: champagneGold,
                              ),
                            ),
                            items:
                                <String>[
                                  'All Time',
                                  'This Month',
                                  'Last 3 Months',
                                ].map((String value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.calendar_month_rounded,
                                          color: champagneGold,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          value,
                                          style: TextStyle(
                                            color: textFrost,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                            onChanged: (newValue) {
                              if (newValue != null) {
                                setState(() => _selectedTimeframe = newValue);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: darkCharcoal,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.fromBorderSide(
                        BorderSide(color: store.border, width: 1),
                      ),
                      boxShadow: [
                        if (!store.isDarkMode)
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Pending Payout',
                              style: TextStyle(color: textMuted, fontSize: 13),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '₹${totalAmount.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: textFrost,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Records',
                              style: TextStyle(color: textMuted, fontSize: 13),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${pendingPayouts.length}',
                              style: TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: !store.expensesLoaded
                        ? const Center(child: CircularProgressIndicator())
                        : pendingPayouts.isEmpty
                        ? Center(
                            child: Text(
                              'No matching pending records found.',
                              style: TextStyle(color: textMuted),
                            ),
                          )
                        : ListView.builder(
                            itemCount: pendingPayouts.length,
                            itemBuilder: (context, index) {
                              final expense = pendingPayouts[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: darkCharcoal,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.fromBorderSide(
                                    BorderSide(color: store.border, width: 1),
                                  ),
                                  boxShadow: [
                                    if (!store.isDarkMode)
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.03,
                                        ),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          expense.name,
                                          style: TextStyle(
                                            color: textFrost,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${expense.type} • ${expense.date}',
                                          style: TextStyle(
                                            color: textMuted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      expense.amountFormatted,
                                      style: TextStyle(
                                        color: Colors.orangeAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: champagneGold,
                        foregroundColor: store.isDarkMode
                            ? obsidianBlack
                            : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        if (pendingPayouts.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('No records to download.'),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                          return;
                        }

                        String csvContent =
                            "Employee Name,Expense ID,Type,Amount,Date Approved,Status\n";
                        for (var exp in pendingPayouts) {
                          final cleanName = exp.name.replaceAll(',', '');
                          csvContent +=
                              "$cleanName,${exp.id},${exp.type},${exp.amount},${exp.date},Approved\n";
                        }
                        final bytes = utf8.encode(csvContent);

                        try {
                          final timestamp =
                              DateTime.now().millisecondsSinceEpoch;
                          final downloaded = downloadFile(
                            bytes,
                            'Pending_Payouts_$timestamp.csv',
                          );

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                downloaded
                                    ? 'Download started!'
                                    : 'CSV export is available in the web build.',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              backgroundColor: champagneGold,
                            ),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error downloading file: $e'),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                        }
                      },
                      icon: Icon(Icons.download_rounded, size: 20),
                      label: Text(
                        'Download CSV Report',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
