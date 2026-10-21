// Finance hub screens - pending payouts ("To Pay") and settled
// reimbursements ("Paid"), plus their time-filtered report screens.
// Split out of the old management-only navigation shell when the two
// portals merged into the single capability-driven portal shell.

import 'package:flutter/material.dart';

import 'package:ats_onework/core/formatting.dart';
import 'package:ats_onework/management/expense_details.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/management/reimbursement_report_screen.dart';
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

/// The paid report: what was reimbursed, to whom and when.
class PaidReportsScreen extends StatelessWidget {
  const PaidReportsScreen({super.key});

  @override
  Widget build(BuildContext context) => const ReimbursementReportScreen(
    title: 'Paid reimbursements',
    status: 'Paid',
    emptyTitle: 'Nothing has been paid yet',
    exportName: 'paid_reimbursements_report',
  );
}

/// The pending-payout report: what is approved and waiting to be paid.
class FinanceReportsScreen extends StatelessWidget {
  const FinanceReportsScreen({super.key});

  @override
  Widget build(BuildContext context) => const ReimbursementReportScreen(
    title: 'Pending payouts',
    status: 'Approved',
    emptyTitle: 'Nothing is waiting for payment',
    exportName: 'pending_payouts_report',
  );
}
