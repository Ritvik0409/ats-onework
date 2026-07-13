import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_store.dart';

class EmployeeDashboardScreen extends StatelessWidget {
  final Function(int) onNavigate;
  const EmployeeDashboardScreen({super.key, required this.onNavigate});

  static const Color obsidianBlack = Color(0xFF0D0D11);
  static const Color darkCharcoal = Color(0xFF16161F);
  static const Color champagneGold = Color(0xFFE2B93B);
  static const Color textFrost = Color(0xFFF3F4F6);
  static const Color textMuted = Color(0xFF9CA3AF);

  Color _statusColor(String status) {
    if (status == 'Approved') return Colors.greenAccent.shade400;
    if (status == 'Rejected') return Colors.redAccent.shade400;
    return champagneGold;
  }

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final recent = store.myExpenses.take(3).toList();

        return Scaffold(
          backgroundColor: obsidianBlack,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: darkCharcoal,
                            shape: BoxShape.circle,
                            border: Border.all(color: champagneGold.withValues(alpha: 0.25), width: 1.5),
                          ),
                          child: const Icon(Icons.person_rounded, color: champagneGold, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Welcome, ${store.currentEmployeeName}',
                              style: const TextStyle(color: textFrost, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'Employee Portal',
                              style: TextStyle(color: textMuted, fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 2.3,
                      children: [
                        _metricCard('Pending Requests', store.myPendingCount.toString().padLeft(2, '0'), Icons.hourglass_empty_rounded, champagneGold, () => onNavigate(2)),
                        _metricCard('Approved Requests', store.myApprovedCount.toString().padLeft(2, '0'), Icons.check_circle_outline_rounded, Colors.greenAccent.shade400, () => onNavigate(2)),
                        _metricCard('Rejected Requests', store.myRejectedCount.toString().padLeft(2, '0'), Icons.cancel_outlined, Colors.redAccent.shade400, () => onNavigate(2)),
                        _metricCard('Total Uploads', store.myTotalUploads.toString().padLeft(2, '0'), Icons.cloud_upload_rounded, Colors.blue.shade400, () => onNavigate(2)),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Recent Requests', style: TextStyle(color: textFrost, fontSize: 15, fontWeight: FontWeight.bold)),
                        TextButton(
                          onPressed: () => onNavigate(2),
                          child: const Text('View all', style: TextStyle(color: champagneGold, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (recent.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: Text('No expenses submitted yet.', style: TextStyle(color: textMuted))),
                      )
                    else
                      ...recent.map((e) => Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: darkCharcoal,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: champagneGold.withValues(alpha: 0.1)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${e.type} Expense • ${e.date}', style: const TextStyle(color: textFrost, fontWeight: FontWeight.bold, fontSize: 14)),
                                      const SizedBox(height: 4),
                                      Text(e.amountFormatted, style: const TextStyle(color: textMuted, fontSize: 13)),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _statusColor(e.status).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: _statusColor(e.status).withValues(alpha: 0.3)),
                                  ),
                                  child: Text(e.status, style: TextStyle(color: _statusColor(e.status), fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          )),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () => onNavigate(1),
                        icon: const Icon(Icons.add_rounded, color: obsidianBlack),
                        label: const Text('Submit New Expense', style: TextStyle(fontWeight: FontWeight.bold, color: obsidianBlack)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: champagneGold,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _metricCard(String title, String count, IconData icon, Color iconColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: darkCharcoal,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: champagneGold.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(title, style: const TextStyle(color: textMuted, fontSize: 12, fontWeight: FontWeight.w600))),
                Icon(icon, color: iconColor, size: 18),
              ],
            ),
            Text(count, style: const TextStyle(color: textFrost, fontSize: 30, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}