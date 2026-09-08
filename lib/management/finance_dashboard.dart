import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/management/expense_details.dart';

class FinanceDashboard extends StatefulWidget {
  const FinanceDashboard({super.key});

  @override
  State<FinanceDashboard> createState() => _FinanceDashboardState();
}

class _FinanceDashboardState extends State<FinanceDashboard> {
  String _graphTimeframe = 'This Month';

  Color _getStatusColor(String status) {
    if (status == 'Paid') return Colors.greenAccent;
    if (status == 'Approved') return Colors.orangeAccent;
    if (status == 'Rejected') return Colors.redAccent;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;

    return Scaffold(
      backgroundColor: store.bg,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: store,
          builder: (context, _) {
            final darkCharcoal = store.card;
            final champagneGold = store.accentGold;
            final textFrost = store.textFrost;
            final textMuted = store.textMuted;
            
            final List<BoxShadow> cardShadows = store.isDarkMode
                ? <BoxShadow>[]
                : [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 16, offset: const Offset(0, 6)),
                    BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 1)),
                  ];

            final approvedExpenses = store.expenses.where((e) => e.status == 'Approved').toList();
            final paidExpenses = store.expenses.where((e) => e.status == 'Paid').toList();

            final totalPendingAmount = approvedExpenses.fold(0.0, (sum, item) => sum + item.amount);
            final totalPaidAmount = paidExpenses.fold(0.0, (sum, item) => sum + item.amount);
            final chartData = store.getChartData(_graphTimeframe);

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: darkCharcoal,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: champagneGold.withValues(alpha: 0.3), width: 1.5),
                                boxShadow: cardShadows,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                store.getInitials(store.currentManagerName), 
                                style: TextStyle(color: champagneGold, fontSize: 18, fontWeight: FontWeight.bold)
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Welcome, ${store.currentManagerName}', 
                                style: TextStyle(color: textFrost, fontSize: 22, fontWeight: FontWeight.bold)
                              ),
                              const SizedBox(height: 4),
                              Text('FINANCE & PAYOUTS', style: TextStyle(color: champagneGold, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                            ],
                          )
                        ],
                      ),
                      const SizedBox(height: 32),

                      Row(
                        children: [
                          Expanded(
                            child: _buildWideKpiCard(
                              title: 'Pending Payments',
                              count: approvedExpenses.length.toString(),
                              amount: '₹${totalPendingAmount.toStringAsFixed(0)}',
                              icon: Icons.hourglass_top_rounded,
                              iconColor: Colors.orangeAccent,
                              store: store,
                              cardShadows: cardShadows,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildWideKpiCard(
                              title: 'Total Disbursed',
                              count: paidExpenses.length.toString(),
                              amount: '₹${totalPaidAmount.toStringAsFixed(0)}',
                              icon: Icons.verified_rounded,
                              iconColor: Colors.greenAccent,
                              store: store,
                              cardShadows: cardShadows,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('To Pay / Approved Requests', style: TextStyle(color: textFrost, fontSize: 18, fontWeight: FontWeight.bold)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orangeAccent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('${approvedExpenses.length} Items', style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      if (approvedExpenses.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: darkCharcoal,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: store.isDarkMode ? champagneGold.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)),
                            boxShadow: cardShadows,
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.check_circle_outline_rounded, size: 48, color: textMuted),
                              const SizedBox(height: 16),
                              Text('Inbox Zero!', style: TextStyle(color: textFrost, fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text('All approved requests have been paid.', style: TextStyle(color: textMuted)),
                            ],
                          ),
                        )
                      else
                        ...approvedExpenses.map((expense) {
                          final statusColor = _getStatusColor(expense.status);
                          
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: darkCharcoal,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: store.isDarkMode ? champagneGold.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2), width: 1),
                              boxShadow: cardShadows,
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              leading: CircleAvatar(
                                radius: 24,
                                backgroundColor: statusColor.withValues(alpha: 0.1),
                                child: Text(
                                  expense.name.substring(0, 1),
                                  style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 18),
                                ),
                              ),
                              title: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(expense.name, style: TextStyle(color: textFrost, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 8),
                                  Text('(${expense.id})', style: TextStyle(color: textMuted)),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6.0),
                                child: Text('${expense.type} Expense • ${expense.date}', style: TextStyle(color: textMuted, fontSize: 13)),
                              ),
                              trailing: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(expense.amountFormatted, style: TextStyle(color: textFrost, fontWeight: FontWeight.w900, fontSize: 15)),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 1),
                                    ),
                                    child: Text(expense.status, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => ExpenseDetailsScreen(expenseId: expense.id)),
                                );
                              },
                            ),
                          );
                        }),
                      const SizedBox(height: 40),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Budget Burn Overview', style: TextStyle(color: textFrost, fontSize: 16, fontWeight: FontWeight.bold)),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: () {
                                  // Add routing if needed for PaidReportsScreen
                                },
                                icon: Icon(Icons.file_upload_outlined, color: champagneGold, size: 18),
                                label: Text('Export MTD', style: TextStyle(color: champagneGold, fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: darkCharcoal, 
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: store.isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.3)),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    dropdownColor: darkCharcoal,
                                    value: _graphTimeframe,
                                    icon: Padding(
                                      padding: const EdgeInsets.only(left: 8.0),
                                      child: Icon(Icons.keyboard_arrow_down_rounded, color: textMuted, size: 16),
                                    ),
                                    items: <String>['This Month', 'Last 3 Months', 'Last 6 Months', 'Year to Date'].map((String value) {
                                      return DropdownMenuItem<String>(
                                        value: value,
                                        child: Text(value, style: TextStyle(color: textMuted, fontSize: 12)),
                                      );
                                    }).toList(),
                                    onChanged: (newValue) {
                                      if (newValue != null) {
                                        setState(() => _graphTimeframe = newValue);
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ],
                          )
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        height: 240,
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                        decoration: BoxDecoration(
                          color: darkCharcoal,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: store.isDarkMode ? champagneGold.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)),
                          boxShadow: cardShadows,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: chartData.map((data) {
                            final label = data['label'] as String;
                            final pct = data['percentage'] as double;
                            return _buildBar(label, pct, store);
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBar(String month, double pct, ExpenseStore store) {
    double fillHeight = 140.0 * pct;
    if (pct > 0 && fillHeight < 6.0) fillHeight = 6.0;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Tooltip(
          message: '${(pct * 100).toStringAsFixed(1)}% of Budget',
          child: Container(
            width: 34,
            height: 140, 
            decoration: BoxDecoration(
              color: store.isDarkMode ? const Color(0xFF1E1E26) : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              width: 34,
              height: fillHeight,
              decoration: BoxDecoration(
                color: store.accentGold,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(month, style: TextStyle(color: store.textMuted, fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildWideKpiCard({
    required String title,
    required String count,
    required String amount,
    required IconData icon,
    required Color iconColor,
    required ExpenseStore store,
    required List<BoxShadow> cardShadows,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: store.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: store.isDarkMode ? store.accentGold.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)),
        boxShadow: cardShadows,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(color: store.textMuted, fontSize: 13, fontWeight: FontWeight.w500)),
              Icon(icon, color: iconColor, size: 20),
            ],
          ),
          const SizedBox(height: 16),
          Text(amount, style: TextStyle(color: store.textFrost, fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('$count Records', style: TextStyle(color: store.textMuted, fontSize: 12)),
        ],
      ),
    );
  }
}