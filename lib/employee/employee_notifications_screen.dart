import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_store.dart';

class EmployeeNotificationsScreen extends StatelessWidget {
  const EmployeeNotificationsScreen({super.key});

  static const Color obsidianBlack = Color(0xFF0D0D11);
  static const Color darkCharcoal = Color(0xFF16161F);
  static const Color champagneGold = Color(0xFFE2B93B);
  static const Color textFrost = Color(0xFFF3F4F6);
  static const Color textMuted = Color(0xFF9CA3AF);

  Widget _buildNotificationCard(AppNotification notif) {
    IconData icon;
    Color iconColor;
    String title;

    // Matches the title and icon to the specific action
    if (notif.type == 'approved') {
      icon = Icons.check_circle_rounded;
      iconColor = Colors.greenAccent;
      title = 'Request Approved';
    } else if (notif.type == 'rejected') {
      icon = Icons.cancel_rounded;
      iconColor = Colors.redAccent;
      title = 'Request Rejected';
    } else if (notif.type == 'info') {
      icon = Icons.info_rounded;
      iconColor = champagneGold;
      title = 'Additional Info Required';
    } else {
      icon = Icons.notifications_rounded;
      iconColor = champagneGold;
      title = 'Notification';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: darkCharcoal,
        borderRadius: BorderRadius.circular(12),
        // Super subtle border to match the sleek design in your 2nd picture
        border: Border.all(color: const Color(0xFF262633), width: 1), 
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: textFrost, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 6),
                Text(notif.subtitle, style: const TextStyle(color: textMuted, fontSize: 13)),
                const SizedBox(height: 10),
                Text(notif.time, style: TextStyle(color: textMuted.withValues(alpha: 0.5), fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        // Only grabs notifications that belong to this specific employee's expenses
        final myExpenseIds = store.myExpenses.map((e) => e.id).toSet();
        final myNotifications = store.notifications.where((n) => myExpenseIds.contains(n.expenseId)).toList();

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: obsidianBlack,
            elevation: 0,
            title: const Text('Notifications', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold, fontSize: 20)),
          ),
          body: myNotifications.isEmpty
              ? const Center(child: Text('No activity yet.', style: TextStyle(color: textMuted)))
              : Center(
                  child: Container(
                    // Keeps the cards nicely centered and constrained on larger screens
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(24),
                      itemCount: myNotifications.length,
                      itemBuilder: (context, index) {
                        return _buildNotificationCard(myNotifications[index]);
                      },
                    ),
                  ),
                ),
        );
      },
    );
  }
}