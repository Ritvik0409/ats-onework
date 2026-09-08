import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_store.dart';

class EmployeeDashboardScreen extends StatelessWidget {
  final Function(int) onNavigate;
  const EmployeeDashboardScreen({super.key, required this.onNavigate});

  Color _statusColor(String status, Color defaultGold) {
    if (status == 'Approved') return Colors.greenAccent.shade400;
    if (status == 'Rejected') return Colors.redAccent.shade400;
    return defaultGold;
  }

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 600;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final obsidianBlack = store.bg;
        final darkCharcoal = store.card;
        final champagneGold = store.accentGold;
        final textFrost = store.textFrost;
        final textMuted = store.textMuted;
        
        final List<BoxShadow> cardShadows = store.isDarkMode
            ? <BoxShadow>[]
            : [
                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 4)),
                BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 12), spreadRadius: -4),
                BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 2, offset: const Offset(0, -1)),
              ];

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
                            boxShadow: cardShadows,
                          ),
                          child: Icon(Icons.person_rounded, color: champagneGold, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Welcome, ${store.currentEmployeeName}',
                              style: TextStyle(color: textFrost, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                            ),
                            const SizedBox(height: 3),
                            Text(
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
                      childAspectRatio: isMobile ? 1.4 : 2.3, 
                      children: [
                        _metricCard('Pending Requests', store.myPendingCount.toString().padLeft(2, '0'), Icons.hourglass_empty_rounded, champagneGold, store, cardShadows, () => onNavigate(2)),
                        _metricCard('Approved Requests', store.myApprovedCount.toString().padLeft(2, '0'), Icons.check_circle_outline_rounded, Colors.greenAccent.shade400, store, cardShadows, () => onNavigate(2)),
                        _metricCard('Rejected Requests', store.myRejectedCount.toString().padLeft(2, '0'), Icons.cancel_outlined, Colors.redAccent.shade400, store, cardShadows, () => onNavigate(2)),
                        _metricCard('Total Uploads', store.myTotalUploads.toString().padLeft(2, '0'), Icons.cloud_upload_rounded, Colors.blue.shade400, store, cardShadows, () => onNavigate(2)),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Recent Requests', style: TextStyle(color: textFrost, fontSize: 15, fontWeight: FontWeight.bold)),
                        TextButton(
                          onPressed: () => onNavigate(2),
                          child: Text('View all', style: TextStyle(color: champagneGold, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (recent.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: Text('No expenses submitted yet.', style: TextStyle(color: textMuted))),
                      )
                    else
                      ...recent.map((e) => Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: darkCharcoal,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: store.isDarkMode ? champagneGold.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)),
                              boxShadow: cardShadows,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${e.type} Expense • ${e.date}', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold, fontSize: 14)),
                                      const SizedBox(height: 4),
                                      Text(e.amountFormatted, style: TextStyle(color: textMuted, fontSize: 13)),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _statusColor(e.status, champagneGold).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: _statusColor(e.status, champagneGold).withValues(alpha: 0.3)),
                                  ),
                                  child: Text(e.status, style: TextStyle(color: _statusColor(e.status, champagneGold), fontSize: 10, fontWeight: FontWeight.bold)),
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
                        icon: Icon(Icons.add_rounded, color: store.isDarkMode ? obsidianBlack : Colors.white),
                        label: Text('Submit New Expense', style: TextStyle(fontWeight: FontWeight.bold, color: store.isDarkMode ? obsidianBlack : Colors.white)),
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

  Widget _metricCard(String title, String count, IconData icon, Color iconColor, ExpenseStore store, List<BoxShadow> cardShadows, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: store.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: store.isDarkMode ? store.accentGold.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)),
          boxShadow: cardShadows,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title, 
                    style: TextStyle(color: store.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(icon, color: iconColor, size: 18),
              ],
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                count, 
                style: TextStyle(color: store.textFrost, fontSize: 30, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}