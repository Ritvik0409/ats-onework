import 'package:flutter/material.dart';

import '../management/expense_store.dart';
import '../shared/app_snack.dart';
import '../shared/load_more.dart';
import '../ui/expense_row.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// The employee's own claims: one list, one filter row, one row widget.
class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key});

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  static const List<String> _filters = <String>[
    'All',
    'Pending',
    'Approved',
    'Paid',
    'Rejected',
  ];

  final ExpenseStore _store = ExpenseStore.instance;
  String _selectedFilter = 'All';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (BuildContext context, Widget? _) {
        final AppPalette palette = context.palette;

        // `myExpenses` already scopes by the signed-in employee id (with
        // an email fallback for legacy rows). Re-filtering by email here
        // hid rows whose record carried an id but no email, so the list
        // could be empty even though the dashboard counted claims.
        final List<ExpenseRecord> all = _store.myExpenses.toList()
          // Newest first — backend ids are numeric; the old string
          // compare on the id field put "10" before "9".
          ..sort(
            (ExpenseRecord a, ExpenseRecord b) =>
                _number(b).compareTo(_number(a)),
          );

        final List<ExpenseRecord> filtered = all
            .where((ExpenseRecord e) {
              if (_selectedFilter == 'All') return true;
              if (_selectedFilter == 'Pending') {
                return e.status == 'Pending Verification' ||
                    e.status == 'Info Requested';
              }
              return e.status == _selectedFilter;
            })
            .toList(growable: false);

        return Scaffold(
          backgroundColor: palette.bg,
          appBar: AppBar(title: const Text('My claims')),
          body: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
                child: AppFilterBar(
                  options: _filters,
                  value: _selectedFilter,
                  onChanged: (String filter) =>
                      setState(() => _selectedFilter = filter),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: !_store.expensesLoaded
                    ? const _ListSkeleton()
                    : RefreshIndicator(
                        onRefresh: () => _store.fetchExpensesFromBackend(),
                        child: filtered.isEmpty
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
                                    icon: Icons.receipt_long_rounded,
                                    title: _selectedFilter == 'All'
                                        ? 'No claims yet'
                                        : 'Nothing in this filter',
                                    message: _selectedFilter == 'All'
                                        ? 'Submit an expense and it will '
                                              'show up here.'
                                        : 'Try another filter to see the '
                                              'rest of your claims.',
                                    action: _selectedFilter == 'All'
                                        ? null
                                        : TextButton(
                                            onPressed: () => setState(
                                              () => _selectedFilter = 'All',
                                            ),
                                            child: const Text('Show all'),
                                          ),
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
                                    filtered.length +
                                    (_store.hasMoreExpenses ? 1 : 0),
                                separatorBuilder:
                                    (BuildContext context, int index) =>
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
                                    showOwner: false,
                                    showId: true,
                                    note: _note(expense, palette),
                                    trailing: expense.status == 'Info Requested'
                                        ? _ResubmitButton(
                                            store: _store,
                                            expenseId: expense.id,
                                          )
                                        : null,
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

  static int _number(ExpenseRecord expense) =>
      int.tryParse(expense.firestoreDocId) ?? 0;

  /// The reason the claim was rejected, or the question the reviewer
  /// asked — the two things the employee needs to read first.
  Widget? _note(ExpenseRecord expense, AppPalette palette) {
    if (expense.status == 'Rejected' &&
        expense.rejectionReason != null &&
        expense.rejectionReason!.isNotEmpty) {
      return Text(
        'Reason: ${expense.rejectionReason}',
        style: TextStyle(
          color: palette.danger.withValues(alpha: 0.9),
          fontSize: 11.5,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    if (expense.status == 'Info Requested' &&
        expense.infoMessage != null &&
        expense.infoMessage!.isNotEmpty) {
      return Text(
        'Reviewer asked: ${expense.infoMessage}',
        style: TextStyle(
          color: palette.warning.withValues(alpha: 0.95),
          fontSize: 11.5,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return null;
  }
}

/// Placeholder rows while the first page is loading.
class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
      itemCount: 4,
      separatorBuilder: (BuildContext context, int index) =>
          const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int index) => const AppCard(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: <Widget>[
            SkeletonBox(width: 40, height: 40, radius: 10),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SkeletonBox(width: 140, height: 14),
                  SizedBox(height: 8),
                  SkeletonBox(width: 90, height: 11),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Resubmit affordance for an expense in 'Info Requested' — the honest
/// backend action: POST /expenses/{id}/resubmit (no fake success).
class _ResubmitButton extends StatefulWidget {
  const _ResubmitButton({required this.store, required this.expenseId});

  final ExpenseStore store;
  final String expenseId;

  @override
  State<_ResubmitButton> createState() => _ResubmitButtonState();
}

class _ResubmitButtonState extends State<_ResubmitButton> {
  bool _sending = false;

  /// Ask for the answer before resubmitting — the manager's question can
  /// only be answered if the employee is actually given a place to type
  /// it.
  Future<String?> _askForAnswer() async {
    final TextEditingController controller = TextEditingController();
    final String? answer = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Provide the requested details'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          maxLength: 2000,
          decoration: const InputDecoration(
            hintText: 'Explain what the reviewer asked for…',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Resubmit'),
          ),
        ],
      ),
    );
    controller.dispose();
    return answer;
  }

  Future<void> _resubmit() async {
    final String? answer = await _askForAnswer();
    if (answer == null) return; // cancelled
    if (!mounted) return;
    if (answer.trim().isEmpty) {
      AppSnack.error(context, 'Please write an answer first.');
      return;
    }
    setState(() => _sending = true);
    final bool ok = await widget.store.resubmitExpense(
      widget.expenseId,
      response: answer.trim(),
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      AppSnack.success(context, 'Details sent — back in the review queue.');
    } else {
      AppSnack.error(context, 'Could not resubmit. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return SizedBox(
      height: 28,
      child: OutlinedButton.icon(
        onPressed: _sending ? null : _resubmit,
        icon: _sending
            ? SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: palette.warning,
                ),
              )
            : const Icon(Icons.replay_rounded, size: 13),
        label: Text(
          _sending ? 'Sending…' : "I've updated it",
          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          foregroundColor: palette.warning,
          side: BorderSide(color: palette.warning.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          ),
          textStyle: const TextStyle(fontSize: 10.5),
          minimumSize: const Size(0, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}
