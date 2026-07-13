import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_store.dart';

class EmployeeNotificationsScreen extends StatelessWidget {
  const EmployeeNotificationsScreen({super.key});

  static const Color obsidianBlack = Color(0xFF0D0D11);
  static const Color darkCharcoal = Color(0xFF16161F);
  static const Color champagneGold = Color(0xFFE2B93B);
  static const Color textFrost = Color(0xFFF3F4F6);
  static const Color textMuted = Color(0xFF9CA3AF);

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        // Only show notifications relevant to this employee's own expense IDs.
        final myExpenseIds = store.myExpenses.map((e) => e.id).toSet();
        final items = store.notifications.where((n) => myExpenseIds.contains(n.expenseId)).toList();

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: darkCharcoal,
            elevation: 0,
            title: const Text('Activity', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold)),
          ),
          body: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600),
              padding: const EdgeInsets.all(16.0),
              child: items.isEmpty
                  ? const Center(child: Text('No activity yet.', style: TextStyle(color: textMuted)))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        IconData iconData = Icons.info_rounded;
                        Color accentColor = champagneGold;
                        if (item.type == 'approved') {
                          iconData = Icons.check_circle_rounded;
                          accentColor = Colors.greenAccent.shade400;
                        } else if (item.type == 'rejected') {
                          iconData = Icons.cancel_rounded;
                          accentColor = Colors.redAccent.shade400;
                        }
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: darkCharcoal,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: champagneGold.withValues(alpha: 0.1)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(iconData, color: accentColor, size: 24),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.type == 'approved' ? 'Request Approved' : item.type == 'rejected' ? 'Request Rejected' : 'Additional Info Required', style: const TextStyle(color: textFrost, fontWeight: FontWeight.bold, fontSize: 14)),
                                    const SizedBox(height: 6),
                                    Text(item.subtitle, style: TextStyle(color: textMuted.withValues(alpha: 0.85), fontSize: 13)),
                                    const SizedBox(height: 8),
                                    Text(item.time, style: TextStyle(color: textMuted.withValues(alpha: 0.5), fontSize: 11)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        );
      },
    );
  }
}