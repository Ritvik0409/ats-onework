import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/management/expense_details.dart';

class ManagerDashboardScreen extends StatefulWidget {
  const ManagerDashboardScreen({super.key});

  @override
  State<ManagerDashboardScreen> createState() => _ManagerDashboardScreenState();
}

class _ManagerDashboardScreenState extends State<ManagerDashboardScreen> {
  String _selectedTimeframe = 'This Month';

  // Professional, subdued color palette (removed the loud pinks and purples)
  final List<Color> _categoryColors = [
    Colors.blueAccent,
    Colors.tealAccent,
    Colors.amber,
    Colors.indigoAccent,
    Colors.deepOrangeAccent,
    Colors.cyan,
  ];

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final obsidianBlack = store.bg;
        final darkCharcoal = store.card;
        final champagneGold = store.accentGold;
        final textFrost = store.textFrost;
        final textMuted = store.textMuted;

        final burnPercentStr = (store.currentMonthBurnPercentage * 100).toStringAsFixed(1);
        final urgentReqs = store.urgentRequests;
        final chartData = store.getChartData(_selectedTimeframe);
        
        final categorySpend = store.categorySpend;

        final List<BoxShadow> cardShadows = store.isDarkMode
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ];

        return Scaffold(
          backgroundColor: obsidianBlack,
          body: SafeArea(
            child: SingleChildScrollView(
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
                              child: Text(store.getInitials(store.currentManagerName), style: TextStyle(color: champagneGold, fontSize: 18, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Welcome, ${store.currentManagerName}', style: TextStyle(color: textFrost, fontSize: 22, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text('${store.currentUserRole.toUpperCase()} Department', style: TextStyle(color: textMuted, fontSize: 13)),
                            ],
                          )
                        ],
                      ),
                      const SizedBox(height: 32),

                      Row(
                        children: [
                          Expanded(child: _buildKpiCard('MTD Pending', store.pendingCount.toString().padLeft(2, '0'), Icons.hourglass_empty, champagneGold, darkCharcoal, textMuted, textFrost, cardShadows, store.isDarkMode)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildKpiCard('MTD Approved', store.approvedCount.toString().padLeft(2, '0'), Icons.check_circle_outline, Colors.greenAccent.shade700, darkCharcoal, textMuted, textFrost, cardShadows, store.isDarkMode)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _buildKpiCard('MTD Rejected', store.rejectedCount.toString().padLeft(2, '0'), Icons.cancel_outlined, Colors.redAccent, darkCharcoal, textMuted, textFrost, cardShadows, store.isDarkMode)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildKpiCard('Total Employees', store.allEmployees.length.toString().padLeft(2, '0'), Icons.people_outline, Colors.blueAccent, darkCharcoal, textMuted, textFrost, cardShadows, store.isDarkMode)),
                        ],
                      ),
                      const SizedBox(height: 32),

                      Text('Budget Burn Rate Tracker', style: TextStyle(color: textFrost, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: darkCharcoal,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: store.isDarkMode ? champagneGold.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.2)),
                          boxShadow: cardShadows,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Allocated Limit Used: $burnPercentStr%', style: TextStyle(color: textFrost, fontSize: 14, fontWeight: FontWeight.bold)),
                                Text('₹${store.currentMonthBurnAmount.toStringAsFixed(0)} / ₹${store.currentMonthBudget.toStringAsFixed(0)}', style: TextStyle(color: champagneGold, fontSize: 14, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            
                            // Segmented Progress Bar
                            Container(
                              height: 12,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: store.isDarkMode ? obsidianBlack : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Row(
                                  children: [
                                    ...categorySpend.entries.toList().asMap().entries.map((entry) {
                                      final index = entry.key;
                                      final amount = entry.value.value;
                                      final flex = amount.toInt();
                                      if (flex <= 0) return const SizedBox.shrink();
                                      
                                      return Expanded(
                                        flex: flex,
                                        child: Container(color: _categoryColors[index % _categoryColors.length]),
                                      );
                                    }),
                                    
                                    if (store.currentMonthBudget > store.currentMonthBurnAmount)
                                      Expanded(
                                        flex: (store.currentMonthBudget - store.currentMonthBurnAmount).toInt(),
                                        child: Container(color: Colors.transparent),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            
                            // Category Breakdown List
                            if (categorySpend.isNotEmpty) ...[
                              const SizedBox(height: 24),
                              ...categorySpend.entries.toList().asMap().entries.map((entry) {
                                final index = entry.key;
                                final categoryName = entry.value.key;
                                final amount = entry.value.value;
                                final dotColor = _categoryColors[index % _categoryColors.length];

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 14.0),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: dotColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(categoryName, style: TextStyle(color: textFrost, fontSize: 15)),
                                      const Spacer(),
                                      // Calculates the exact percentage relative to TOTAL SPENT (always sums to 100%)
                                      Text(
                                        store.currentMonthBurnAmount > 0 
                                            ? '${((amount / store.currentMonthBurnAmount) * 100).toStringAsFixed(1)}%' 
                                            : '0.0%', 
                                        style: TextStyle(color: textFrost, fontSize: 14, fontWeight: FontWeight.bold)
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ]
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      Text('"Needs Attention" Urgent Items', style: TextStyle(color: textFrost, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      if (urgentReqs.isNotEmpty)
                        ...urgentReqs.map((urgentItem) {
                          final req = urgentItem['expense'] as ExpenseRecord;
                          final reason = urgentItem['reason'] as String;
                          final isSla = urgentItem['isSla'] as bool;
                          
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: darkCharcoal,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: isSla ? Colors.redAccent.withValues(alpha: 0.3) : (store.isDarkMode ? champagneGold.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.2))),
                              boxShadow: cardShadows,
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: isSla ? Colors.redAccent.withValues(alpha: 0.1) : champagneGold.withValues(alpha: 0.1),
                                  child: Text(store.getInitials(req.name), style: TextStyle(color: isSla ? Colors.redAccent : champagneGold, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${req.name} • ${req.type}', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isSla ? Colors.redAccent.withValues(alpha: 0.1) : Colors.orangeAccent.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(reason, style: TextStyle(color: isSla ? Colors.redAccent : Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(req.amountFormatted, style: TextStyle(color: textMuted, fontSize: 12)),
                                        ],
                                      )
                                    ],
                                  ),
                                ),
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: champagneGold.withValues(alpha: 0.3)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => ExpenseDetailsScreen(expenseId: req.id)),
                                    );
                                  },
                                  child: Text('Review', style: TextStyle(color: champagneGold, fontSize: 12)),
                                )
                              ],
                            ),
                          );
                        })
                      else
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: darkCharcoal,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: store.isDarkMode ? champagneGold.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.2)),
                            boxShadow: cardShadows,
                          ),
                          child: Center(
                            child: Text('All caught up! No urgent pending requests.', style: TextStyle(color: textMuted, fontWeight: FontWeight.w500)),
                          ),
                        ),
                      const SizedBox(height: 32),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Requests Overview', style: TextStyle(color: textFrost, fontSize: 16, fontWeight: FontWeight.bold)),
                          DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              dropdownColor: darkCharcoal,
                              value: _selectedTimeframe,
                              icon: Icon(Icons.arrow_drop_down, color: textMuted.withValues(alpha: 0.8)),
                              style: TextStyle(color: textMuted.withValues(alpha: 0.8), fontSize: 12),
                              onChanged: (String? newValue) {
                                if (newValue != null) {
                                  setState(() {
                                    _selectedTimeframe = newValue;
                                  });
                                }
                              },
                              items: <String>['This Month', 'Last 3 Months', 'Last 6 Months', 'Year to Date']
                                  .map<DropdownMenuItem<String>>((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      
                      Container(
                        height: 200,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: darkCharcoal,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: store.isDarkMode ? champagneGold.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.2)),
                          boxShadow: cardShadows,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: chartData.map((data) {
                            return _buildBar(data['label'], data['percentage'], store.isDarkMode ? obsidianBlack : Colors.grey.shade100, champagneGold, textMuted);
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color iconColor, Color cardBg, Color mutedColor, Color frostColor, List<BoxShadow> shadows, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.amber.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.2)),
        boxShadow: shadows,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(color: mutedColor, fontSize: 13, fontWeight: FontWeight.w500)),
              Icon(icon, color: iconColor, size: 18),
            ],
          ),
          const SizedBox(height: 16),
          Text(value, style: TextStyle(color: frostColor, fontSize: 28, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _buildBar(String label, double fillPercentage, Color trackBg, Color barColor, Color textColor) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 32,
          height: 120,
          decoration: BoxDecoration(
            color: trackBg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: 32,
              height: 120 * fillPercentage,
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(label, style: TextStyle(color: textColor, fontSize: 12)),
      ],
    );
  }
}