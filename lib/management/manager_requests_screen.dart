import 'package:flutter/material.dart';

import '../management/expense_details.dart';
import '../management/expense_store.dart';
import '../management/manager_reports.dart';
import '../shared/load_more.dart';
import '../ui/expense_row.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// The review queue: every claim the approver may see, searchable and
/// filterable, with the high-value ones flagged.
class ManagerRequestsScreen extends StatefulWidget {
  const ManagerRequestsScreen({super.key});

  @override
  State<ManagerRequestsScreen> createState() => _ManagerRequestsScreenState();
}

class _ManagerRequestsScreenState extends State<ManagerRequestsScreen> {
  static const List<String> _filters = <String>[
    'All',
    'Pending',
    'Approved',
    'Paid',
    'Rejected',
  ];

  final ExpenseStore _store = ExpenseStore.instance;
  String _searchQuery = '';
  String _selectedFilter = 'All';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (BuildContext context, Widget? _) {
        final AppPalette palette = context.palette;

        final List<ExpenseRecord> filtered = _store.expenses
            .where((ExpenseRecord expense) {
              final String query = _searchQuery.trim().toLowerCase();
              final bool matchesSearch =
                  query.isEmpty ||
                  expense.name.toLowerCase().contains(query) ||
                  expense.id.toLowerCase().contains(query) ||
                  expense.type.toLowerCase().contains(query) ||
                  (expense.projectName ?? '').toLowerCase().contains(query);

              if (!matchesSearch) return false;
              if (_selectedFilter == 'All') return true;
              if (_selectedFilter == 'Pending') {
                // Same rule as the employee screen: a claim the approver
                // has asked for more info on is still "waiting on us".
                return expense.status == 'Pending Verification' ||
                    expense.status == 'Info Requested';
              }
              return expense.status == _selectedFilter;
            })
            .toList(growable: false);

        return Scaffold(
          backgroundColor: palette.bg,
          appBar: AppBar(
            title: const Text('All requests'),
            actions: <Widget>[
              IconButton(
                tooltip: 'Reports',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) =>
                        const ManagerReportsScreen(),
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
                      hint: 'Search by employee, id, type or project…',
                      onChanged: (String value) =>
                          setState(() => _searchQuery = value),
                    ),
                    const SizedBox(height: 12),
                    AppFilterBar(
                      options: _filters,
                      value: _selectedFilter,
                      onChanged: (String filter) =>
                          setState(() => _selectedFilter = filter),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: !_store.expensesLoaded
                    // The first page is still in flight — landing on the
                    // empty state here made a slow fetch read as "nothing
                    // matches your filter".
                    ? const Center(child: CircularProgressIndicator())
                    : _store.expensesError != null
                    ? RefreshIndicator(
                        onRefresh: () => _store.fetchExpensesFromBackend(),
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: <Widget>[
                            const SizedBox(height: 60),
                            EmptyState(
                              icon: Icons.cloud_off_rounded,
                              title: "Couldn't load the queue",
                              message: _store.expensesError!,
                              action: FilledButton.icon(
                                onPressed: _store.fetchExpensesFromBackend,
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 18,
                                ),
                                label: const Text('Retry'),
                              ),
                            ),
                          ],
                        ),
                      )
                    : filtered.isEmpty
                    // A scrollable empty state: the queue is paged, so an
                    // empty page can still be followed by more claims —
                    // and pull-to-refresh has to work here too.
                    ? RefreshIndicator(
                        onRefresh: () => _store.fetchExpensesFromBackend(),
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: <Widget>[
                            const SizedBox(height: 60),
                            EmptyState(
                              icon: Icons.search_off_rounded,
                              title: 'No matching claims',
                              message: _store.hasMoreExpenses
                                  ? 'More claims are still being loaded — '
                                        'press "Load more" to fetch the next '
                                        'page.'
                                  : 'Try another filter or clear the search.',
                              action: _store.hasMoreExpenses
                                  ? FilledButton.icon(
                                      onPressed: _store.expensesLoadingMore
                                          ? null
                                          : _store.loadMoreExpenses,
                                      icon: const Icon(
                                        Icons.expand_more_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Load more'),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _store.fetchExpensesFromBackend(),
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
                          // One extra row for the "load more" footer, so a
                          // list longer than one page can be walked through.
                          itemCount:
                              filtered.length +
                              (_store.hasMoreExpenses ? 1 : 0),
                          separatorBuilder: (BuildContext context, int index) =>
                              const SizedBox(height: 10),
                          itemBuilder: (BuildContext context, int index) {
                            if (index >= filtered.length) {
                              return LoadMoreFooter(
                                hasMore: _store.hasMoreExpenses,
                                loading: _store.expensesLoadingMore,
                                onLoad: _store.loadMoreExpenses,
                              );
                            }
                            final ExpenseRecord expense = filtered[index];
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
}
