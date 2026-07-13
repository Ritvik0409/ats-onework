import 'package:flutter/material.dart';
import 'package:ats_onework/management/manager_dashboard.dart';
import 'package:ats_onework/management/notifications_hub.dart';
import 'package:ats_onework/management/manager_profile.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/management/expense_details.dart';

class ManagementNavigationShell extends StatefulWidget {
  const ManagementNavigationShell({super.key});

  @override
  State<ManagementNavigationShell> createState() => _ManagementNavigationShellState();
}

class _ManagementNavigationShellState extends State<ManagementNavigationShell> {
  int _currentIndex = 0;

  static const Color obsidianBlack = Color(0xFF0D0D11);
  static const Color darkCharcoal = Color(0xFF16161F);
  static const Color champagneGold = Color(0xFFE2B93B);
  static const Color textFrost = Color(0xFFF3F4F6);
  static const Color textMuted = Color(0xFF9CA3AF);

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      DashboardAnalyticsScreen(
        onFilterRequested: (targetIndex) {
          setState(() {
            _currentIndex = targetIndex;
          });
        },
      ),
      const ManagerDashboardScreen(),
      const NotificationsHubScreen(),
      const ManagerProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: obsidianBlack,
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: darkCharcoal,
          border: Border(top: BorderSide(color: Color(0xFF262633), width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: darkCharcoal,
          selectedItemColor: champagneGold,
          unselectedItemColor: textMuted,
          type: BottomNavigationBarType.fixed,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded, size: 22), label: 'Dashboard'),
            BottomNavigationBarItem(icon: Icon(Icons.assignment_rounded, size: 22), label: 'Requests'),
            BottomNavigationBarItem(icon: Icon(Icons.notifications_rounded, size: 22), label: 'Notifications'),
            BottomNavigationBarItem(icon: Icon(Icons.person_rounded, size: 22), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}

class DashboardAnalyticsScreen extends StatelessWidget {
  final Function(int) onFilterRequested;

  const DashboardAnalyticsScreen({super.key, required this.onFilterRequested});

  @override
  Widget build(BuildContext context) {
    const Color obsidianBlack = Color(0xFF0D0D11);
    const Color darkCharcoal = Color(0xFF16161F);
    const Color champagneGold = Color(0xFFE2B93B);
    const Color textFrost = Color(0xFFF3F4F6);
    const Color textMuted = Color(0xFF9CA3AF);

    final store = ExpenseStore.instance;

    double monthlySpend = 42850.00;
    double allocatedBudget = 60000.00;
    double burnRate = monthlySpend / allocatedBudget;

    final pendingExpenses = store.expenses.where((e) => e.status == 'Pending Verification').toList();
    final urgentItem = pendingExpenses.isNotEmpty ? pendingExpenses.first : null;

    void openUrgentItemDetails() {
      if (urgentItem == null) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ExpenseDetailsScreen(expenseId: urgentItem.id),
        ),
      );
    }

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => Scaffold(
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
                          'Welcome, ${store.currentManagerName}',
                          style: const TextStyle(color: textFrost, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Admin Department',
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
                    _buildMetricCard(
                      title: 'Pending Mix',
                      count: store.pendingCount.toString().padLeft(2, '0'),
                      icon: Icons.hourglass_empty_rounded,
                      iconColor: Colors.amber,
                      bg: darkCharcoal, gold: champagneGold, frost: textFrost, muted: textMuted,
                      onTap: () => onFilterRequested(1),
                    ),
                    _buildMetricCard(
                      title: 'Approved Today',
                      count: store.approvedCount.toString().padLeft(2, '0'),
                      icon: Icons.check_circle_outline_rounded,
                      iconColor: Colors.greenAccent,
                      bg: darkCharcoal, gold: champagneGold, frost: textFrost, muted: textMuted,
                      onTap: () => onFilterRequested(1),
                    ),
                    _buildMetricCard(
                      title: 'Rejected Today',
                      count: store.rejectedCount.toString().padLeft(2, '0'),
                      icon: Icons.cancel_outlined,
                      iconColor: Colors.red.shade400,
                      bg: darkCharcoal, gold: champagneGold, frost: textFrost, muted: textMuted,
                      onTap: () => onFilterRequested(1),
                    ),
                    _buildMetricCard(
                      title: 'Total Employees',
                      count: '128',
                      icon: Icons.people_outline_rounded,
                      iconColor: Colors.blue.shade400,
                      bg: darkCharcoal, gold: champagneGold, frost: textFrost, muted: textMuted,
                      onTap: () {},
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Budget Burn Rate Tracker', style: TextStyle(color: textFrost, fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: darkCharcoal,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: champagneGold.withValues(alpha: 0.1)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Allocated Limit Used: ${(burnRate * 100).toStringAsFixed(1)}%',
                              style: const TextStyle(color: textFrost, fontSize: 13, fontWeight: FontWeight.w600)),
                          Text('₹${monthlySpend.toStringAsFixed(0)} / ₹${allocatedBudget.toStringAsFixed(0)}',
                              style: const TextStyle(color: champagneGold, fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: burnRate,
                          minHeight: 8,
                          backgroundColor: obsidianBlack,
                          valueColor: const AlwaysStoppedAnimation<Color>(champagneGold),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text('"Needs Attention" Urgent Items', style: TextStyle(color: textFrost, fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (urgentItem == null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: darkCharcoal,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: champagneGold.withValues(alpha: 0.1)),
                    ),
                    child: const Text('No pending items right now.', style: TextStyle(color: textMuted, fontSize: 13)),
                  )
                else
                  GestureDetector(
                    onTap: openUrgentItemDetails,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: darkCharcoal,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: champagneGold.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: champagneGold.withValues(alpha: 0.1),
                            child: Text(urgentItem.name.substring(0, 1), style: const TextStyle(color: champagneGold, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${urgentItem.name} • ${urgentItem.type}',
                                    style: const TextStyle(color: textFrost, fontWeight: FontWeight.bold, fontSize: 14)),
                                const SizedBox(height: 2),
                                Text('Awaiting review • ${urgentItem.amountFormatted}',
                                    style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: openUrgentItemDetails,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: champagneGold.withValues(alpha: 0.12),
                              foregroundColor: champagneGold,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(color: champagneGold.withValues(alpha: 0.4)),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Review Request', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                SizedBox(width: 4),
                                Icon(Icons.arrow_forward_rounded, size: 14),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Requests Overview', style: TextStyle(color: textFrost, fontSize: 15, fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.ios_share_rounded, size: 14, color: champagneGold),
                          label: const Text('Export MTD', style: TextStyle(color: champagneGold, fontSize: 12, fontWeight: FontWeight.bold)),
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          children: [
                            Text('This Month', style: TextStyle(color: textMuted.withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 2),
                            Icon(Icons.arrow_drop_down_rounded, color: textMuted.withValues(alpha: 0.8), size: 18),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                  decoration: BoxDecoration(
                    color: darkCharcoal,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: champagneGold.withValues(alpha: 0.1)),
                  ),
                  child: SizedBox(
                    height: 160,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _buildChartBar('Jan', 0.55, champagneGold, textMuted),
                        _buildChartBar('Feb', 0.85, champagneGold, textMuted),
                        _buildChartBar('Apr', 0.70, champagneGold, textMuted),
                        _buildChartBar('May', 0.50, champagneGold, textMuted),
                        _buildChartBar('Jun', 0.38, champagneGold, textMuted),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String count,
    required IconData icon,
    required Color iconColor,
    Color? numberColorOverride,
    required Color bg,
    required Color gold,
    required Color frost,
    required Color muted,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: gold.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: TextStyle(color: muted, fontSize: 13, fontWeight: FontWeight.w600)),
                Icon(icon, color: iconColor, size: 18),
              ],
            ),
            Text(
              count,
              style: TextStyle(color: numberColorOverride ?? frost, fontSize: 34, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartBar(String label, double fillPercentage, Color barColor, Color labelColor) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: Container(
            width: 32,
            alignment: Alignment.bottomCenter,
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D11),
              borderRadius: BorderRadius.circular(6),
            ),
            child: FractionallySizedBox(
              heightFactor: fillPercentage,
              child: Container(
                decoration: BoxDecoration(
                  color: barColor.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(label, style: TextStyle(color: labelColor, fontSize: 11, fontWeight: FontWeight.w500)),
      ],
    );
  }
}