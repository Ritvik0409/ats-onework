import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/shared/app_snack.dart';

class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key});

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  String _selectedFilter = 'All';
  final ExpenseStore _store = ExpenseStore.instance;

  Color _statusColor(String status, Color defaultGold) {
    if (status == 'Approved' || status == 'Paid') return Colors.greenAccent.shade400;
    if (status == 'Rejected') return Colors.redAccent.shade400;
    if (status == 'Info Requested') return Colors.orangeAccent.shade200;
    return defaultGold;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final obsidianBlack = _store.bg;
        final darkCharcoal = _store.card;
        final champagneGold = _store.accentGold;
        final textFrost = _store.textFrost;
        final textMuted = _store.textMuted;
        
        final List<BoxShadow> cardShadows = _store.isDarkMode
            ? <BoxShadow>[]
            : [
                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 4)),
                BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 12), spreadRadius: -4),
                BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 2, offset: const Offset(0, -1)),
              ];

        // STRICT IDENTITY SYNC: Reads both login states to guarantee your list is never empty
        final myEmployeeEmail = _store.currentEmployeeEmail.trim().toLowerCase();
        final myManagerEmail = _store.currentManagerEmail.trim().toLowerCase();
        
        final all = _store.myExpenses.where((e) {
          final uploaderEmail = e.email.trim().toLowerCase();
          return uploaderEmail == myEmployeeEmail || uploaderEmail == myManagerEmail;
        }).toList();
        
        // Newest first — backend ids are numeric; the old string compare
        // on the id field put "10" before "9".
        int expenseNumber(ExpenseRecord e) => int.tryParse(e.firestoreDocId) ?? 0;
        all.sort((a, b) => expenseNumber(b).compareTo(expenseNumber(a)));

        final filtered = all.where((e) {
          if (_selectedFilter == 'All') return true;
          if (_selectedFilter == 'Pending') {
            return e.status == 'Pending Verification' || e.status == 'Info Requested';
          }
          return e.status == _selectedFilter;
        }).toList();

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: darkCharcoal,
            elevation: 0,
            title: Text('My Expenses', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold, fontSize: 20)),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(color: champagneGold.withValues(alpha: 0.15), height: 1),
            ),
          ),
          body: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600),
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ['All', 'Pending', 'Approved', 'Paid', 'Rejected'].map((category) {
                        final isSelected = _selectedFilter == category;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ChoiceChip(
                            label: Text(category),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) setState(() => _selectedFilter = category);
                            },
                            labelStyle: TextStyle(
                              color: isSelected ? (_store.isDarkMode ? obsidianBlack : Colors.white) : textFrost, 
                              fontWeight: FontWeight.bold, 
                              fontSize: 13
                            ),
                            selectedColor: champagneGold,
                            backgroundColor: darkCharcoal,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(color: isSelected ? champagneGold : champagneGold.withValues(alpha: 0.15)),
                            ),
                            showCheckmark: false,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: !_store.expensesLoaded
                        ? const Center(child: CircularProgressIndicator())
                        : RefreshIndicator(
                            onRefresh: () => _store.fetchExpensesFromBackend(),
                            child: filtered.isEmpty
                                // A RefreshIndicator only reacts to the
                                // scroll notifications of a scrollable
                                // child, so the empty state has to be one
                                // too — otherwise pull-to-refresh does
                                // nothing exactly when it is wanted.
                                ? ListView(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    children: [
                                      const SizedBox(height: 80),
                                      Center(child: Text('No expenses in this category.', style: TextStyle(color: textMuted))),
                                    ],
                                  )
                                : ListView.builder(
                                    itemCount: filtered.length,
                                    itemBuilder: (context, index) {
                                      final e = filtered[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 14),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: darkCharcoal,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: _store.isDarkMode ? champagneGold.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)),
                                  boxShadow: cardShadows,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(color: champagneGold.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                                      child: Icon(Icons.receipt_long_rounded, color: champagneGold, size: 20),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text('${e.type} Expense', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold, fontSize: 14)),
                                            
                                            if (e.projectName != null && e.projectName!.isNotEmpty) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: champagneGold.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: champagneGold.withValues(alpha: 0.5)),
                                                ),
                                                child: Text(
                                                  e.projectName!,
                                                  style: TextStyle(color: champagneGold, fontSize: 12, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            ]
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text('${e.date} • ${e.id}', style: TextStyle(color: textMuted, fontSize: 12)),
                                        if (e.status == 'Rejected' && e.rejectionReason != null) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            'Reason: ${e.rejectionReason}',
                                            style: TextStyle(color: Colors.redAccent.withValues(alpha: 0.85), fontSize: 11, fontStyle: FontStyle.italic),
                                          ),
                                        ],
                                        if (e.status == 'Info Requested' && e.infoMessage != null && e.infoMessage!.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            'Manager asked: ${e.infoMessage}',
                                            style: TextStyle(color: Colors.orangeAccent.withValues(alpha: 0.9), fontSize: 11, fontStyle: FontStyle.italic),
                                          ),
                                        ],
                                      ],
                                    ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(e.amountFormatted, style: TextStyle(color: textFrost, fontWeight: FontWeight.w900, fontSize: 14)),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: _statusColor(e.status, champagneGold).withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: _statusColor(e.status, champagneGold).withValues(alpha: 0.3)),
                                          ),
                                          child: Text(e.status == 'Approved' ? 'Approved • Payment Pending' : e.status, style: TextStyle(color: _statusColor(e.status, champagneGold), fontSize: 10, fontWeight: FontWeight.bold)),
                                        ),
                                        if (e.status == 'Info Requested') ...[
                                          const SizedBox(height: 8),
                                          _ResubmitButton(store: _store, expenseId: e.id),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
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

/// Resubmit affordance for an expense in 'Info Requested' — the honest
/// backend action: POST /expenses/{id}/resubmit (no fake success).
class _ResubmitButton extends StatefulWidget {
  final ExpenseStore store;
  final String expenseId;

  const _ResubmitButton({required this.store, required this.expenseId});

  @override
  State<_ResubmitButton> createState() => _ResubmitButtonState();
}

class _ResubmitButtonState extends State<_ResubmitButton> {
  bool _sending = false;

  /// Ask for the answer before resubmitting — the manager's question can
  /// only be answered if the employee is actually given a place to type
  /// it.
  Future<String?> _askForAnswer() async {
    final controller = TextEditingController();
    final answer = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
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
    final answer = await _askForAnswer();
    if (answer == null) return; // cancelled
    setState(() => _sending = true);
    final ok = await widget.store.resubmitExpense(
      widget.expenseId,
      response: answer,
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
    return SizedBox(
      height: 26,
      child: ElevatedButton.icon(
        onPressed: _sending ? null : _resubmit,
        icon: _sending
            ? const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.replay_rounded, size: 13),
        label: Text(
          _sending ? 'Sending…' : "I've updated it — resubmit",
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          backgroundColor: Colors.orangeAccent.withValues(alpha: 0.15),
          foregroundColor: Colors.orangeAccent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: Colors.orangeAccent.withValues(alpha: 0.4)),
          ),
        ),
      ),
    );
  }
}