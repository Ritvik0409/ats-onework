import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/management/expense_details.dart';

class DirectorDashboard extends StatefulWidget {
  const DirectorDashboard({super.key});

  @override
  State<DirectorDashboard> createState() => _DirectorDashboardState();
}

class _DirectorDashboardState extends State<DirectorDashboard> {
  String _selectedTimeframe = 'This Month';
  
  // NEW: State variables for the integrated feed
  String _searchQuery = '';
  String _selectedFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;

    return Scaffold(
      backgroundColor: store.bg,
      body: SafeArea(
        child: AnimatedBuilder(
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

            final burnPercentStr = (store.currentMonthBurnPercentage * 100).toStringAsFixed(1);
            final urgentReqs = store.urgentRequests;
            final chartData = store.getChartData(_selectedTimeframe);
            
            // STRICT IDENTITY LOCK: Hides the Director's own uploads from the "Recently Paid" widget
            final myEmployeeEmail = store.currentEmployeeEmail.trim().toLowerCase();
            final myManagerEmail = store.currentManagerEmail.trim().toLowerCase();
            
            final paidExpenses = store.expenses.where((e) {
              final uploaderEmail = e.email.trim().toLowerCase();
              if (uploaderEmail == myEmployeeEmail || uploaderEmail == myManagerEmail) return false;
              return e.status == 'Paid';
            }).toList();

            final displayName = store.currentManagerName == 'Manager' ? 'Director' : store.currentManagerName;

            // NEW: Integrated Feed Logic (No date limits, hides own uploads)
            final filteredFeedExpenses = store.expenses.where((expense) {
              final uploaderEmail = expense.email.trim().toLowerCase();
              if (uploaderEmail == myEmployeeEmail || uploaderEmail == myManagerEmail) {
                return false;
              }

              final matchesSearch = expense.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                  expense.id.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                  expense.type.toLowerCase().contains(_searchQuery.toLowerCase());

              if (_selectedFilter == 'All') return matchesSearch;
              if (_selectedFilter == 'Pending') return matchesSearch && expense.status == 'Pending Verification';
              if (_selectedFilter == 'Approved') return matchesSearch && expense.status == 'Approved';
              if (_selectedFilter == 'Paid') return matchesSearch && expense.status == 'Paid';
              if (_selectedFilter == 'Rejected') return matchesSearch && expense.status == 'Rejected';
              return matchesSearch;
            }).toList();

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- DASHBOARD SECTION ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                    store.getInitials(displayName), 
                                    style: TextStyle(color: champagneGold, fontSize: 18, fontWeight: FontWeight.bold)
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Welcome, $displayName', 
                                    style: TextStyle(color: textFrost, fontSize: 22, fontWeight: FontWeight.bold)
                                  ),
                                  const SizedBox(height: 4),
                                  Text('EXECUTIVE DIRECTOR', style: TextStyle(color: champagneGold, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                                ],
                              )
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      Row(
                        children: [
                          Expanded(child: _buildKpiCard('MTD Pending', store.pendingCount.toString().padLeft(2, '0'), Icons.hourglass_empty, champagneGold, store, cardShadows)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildKpiCard('MTD Approved', store.approvedCount.toString().padLeft(2, '0'), Icons.check_circle_outline, Colors.greenAccent, store, cardShadows)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _buildKpiCard('MTD Rejected', store.rejectedCount.toString().padLeft(2, '0'), Icons.cancel_outlined, Colors.redAccent, store, cardShadows)),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildKpiCard(
                              'Total Employees', 
                              store.allEmployees.length.toString().padLeft(2, '0'), 
                              Icons.manage_accounts_outlined, 
                              Colors.blueAccent,
                              store,
                              cardShadows,
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Navigating to Employee Management...'), backgroundColor: champagneGold));
                              }
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Recently Paid Reimbursements', style: TextStyle(color: textFrost, fontSize: 16, fontWeight: FontWeight.bold)),
                          Text('${paidExpenses.length} Records', style: TextStyle(color: textMuted, fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 130,
                        child: paidExpenses.isEmpty
                          ? Container(
                              width: double.infinity,
                              decoration: BoxDecoration(color: darkCharcoal, borderRadius: BorderRadius.circular(16), border: Border.all(color: store.isDarkMode ? champagneGold.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)), boxShadow: cardShadows),
                              child: Center(child: Text('No paid reimbursements yet.', style: TextStyle(color: textMuted))),
                            )
                          : ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: paidExpenses.length,
                              itemBuilder: (context, index) {
                                final expense = paidExpenses[index];
                                return Container(
                                  width: 260,
                                  margin: const EdgeInsets.only(right: 16, bottom: 8),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: darkCharcoal,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.2)),
                                    boxShadow: cardShadows,
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(child: Text(expense.name, style: TextStyle(color: textFrost, fontWeight: FontWeight.bold, fontSize: 15), overflow: TextOverflow.ellipsis)),
                                          const Icon(Icons.verified_rounded, color: Colors.greenAccent, size: 18),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text('${expense.type} • ${expense.date}', style: TextStyle(color: textMuted, fontSize: 12)),
                                      const Spacer(),
                                      Text(expense.amountFormatted, style: TextStyle(color: textFrost, fontSize: 18, fontWeight: FontWeight.w900)),
                                    ],
                                  ),
                                );
                              },
                            ),
                      ),
                      const SizedBox(height: 32),

                      Text('Budget Burn Rate Tracker', style: TextStyle(color: textFrost, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: darkCharcoal,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: store.isDarkMode ? champagneGold.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)),
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
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                value: store.currentMonthBurnPercentage,
                                minHeight: 8,
                                backgroundColor: store.isDarkMode ? obsidianBlack : Colors.grey.shade200,
                                valueColor: AlwaysStoppedAnimation<Color>(champagneGold),
                              ),
                            ),
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
                          final isHighValue = req.amount > 30000;
                          
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: darkCharcoal,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isHighValue 
                                  ? Colors.redAccent.shade700.withValues(alpha: 0.6) 
                                  : (isSla ? Colors.redAccent.withValues(alpha: 0.3) : (store.isDarkMode ? champagneGold.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2))),
                                width: isHighValue ? 1.5 : 1
                              ),
                              boxShadow: isHighValue ? [BoxShadow(color: Colors.redAccent.withValues(alpha: 0.05), blurRadius: 10, spreadRadius: 1), ...cardShadows] : cardShadows,
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: (isSla || isHighValue) ? Colors.redAccent.withValues(alpha: 0.1) : champagneGold.withValues(alpha: 0.1),
                                  child: Text(store.getInitials(req.name), style: TextStyle(color: (isSla || isHighValue) ? Colors.redAccent : champagneGold, fontWeight: FontWeight.bold)),
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
                                              color: (isSla || isHighValue) ? Colors.redAccent.withValues(alpha: 0.1) : Colors.orangeAccent.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(reason, style: TextStyle(color: (isSla || isHighValue) ? Colors.redAccent : Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
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
                            border: Border.all(color: store.isDarkMode ? champagneGold.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)),
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
                          Row(
                            children: [
                              InkWell(
                                onTap: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text('Exporting report...', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), 
                                      backgroundColor: champagneGold,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                                child: Row(
                                  children: [
                                    Icon(Icons.ios_share, color: champagneGold, size: 16),
                                    const SizedBox(width: 6),
                                    Text('Export MTD', style: TextStyle(color: champagneGold, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
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
                          )
                        ],
                      ),
                      const SizedBox(height: 12),
                      
                      Container(
                        height: 200,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: darkCharcoal,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: store.isDarkMode ? champagneGold.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)),
                          boxShadow: cardShadows,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: chartData.map((data) {
                            return _buildBar(data['label'], data['percentage'], store);
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 40),
                      Divider(color: champagneGold.withValues(alpha: 0.2), thickness: 1),
                      const SizedBox(height: 32),

                      // --- NEW: INTEGRATED REQUEST FEED ---
                      Text('Approval Feed', style: TextStyle(color: textFrost, fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      TextField(
                        onChanged: (value) => setState(() => _searchQuery = value),
                        style: TextStyle(color: textFrost),
                        decoration: InputDecoration(
                          hintText: 'Search by employee name, ID or type...',
                          hintStyle: TextStyle(color: textMuted, fontSize: 14),
                          prefixIcon: Icon(Icons.search_rounded, color: champagneGold, size: 22),
                          filled: true,
                          fillColor: darkCharcoal,
                          contentPadding: const EdgeInsets.symmetric(vertical: 16),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: champagneGold.withValues(alpha: 0.1)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: champagneGold, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
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
                                  // FIX: Changed _store to store to resolve the undefined variable error
                                  color: isSelected ? (store.isDarkMode ? obsidianBlack : Colors.white) : textFrost,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                selectedColor: champagneGold,
                                backgroundColor: darkCharcoal,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  side: BorderSide(color: isSelected ? champagneGold : champagneGold.withValues(alpha: 0.15)),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      filteredFeedExpenses.isEmpty
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(40),
                            decoration: BoxDecoration(
                              color: darkCharcoal,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: store.isDarkMode ? champagneGold.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)),
                            ),
                            child: Center(child: Text('No matching expense logs found.', style: TextStyle(color: textMuted))),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: filteredFeedExpenses.length,
                            itemBuilder: (context, index) {
                              final expense = filteredFeedExpenses[index];

                              Color statusColor = champagneGold;
                              if (expense.status == 'Approved') statusColor = Colors.orangeAccent;
                              if (expense.status == 'Paid') statusColor = Colors.greenAccent.shade400;
                              if (expense.status == 'Rejected') statusColor = Colors.redAccent.shade400;

                              final isHighValue = expense.amount > 30000;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 14),
                                decoration: BoxDecoration(
                                  color: darkCharcoal,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isHighValue ? Colors.redAccent.shade700.withValues(alpha: 0.6) : champagneGold.withValues(alpha: 0.1), 
                                    width: isHighValue ? 1.5 : 1
                                  ),
                                  boxShadow: isHighValue 
                                    ? [BoxShadow(color: Colors.redAccent.withValues(alpha: 0.05), blurRadius: 10, spreadRadius: 1), ...cardShadows]
                                    : cardShadows,
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  leading: CircleAvatar(
                                    radius: 24,
                                    backgroundColor: isHighValue ? Colors.redAccent.withValues(alpha: 0.1) : champagneGold.withValues(alpha: 0.1),
                                    child: Text(
                                      expense.name.substring(0, 1),
                                      style: TextStyle(
                                        color: isHighValue ? Colors.redAccent : champagneGold, 
                                        fontWeight: FontWeight.bold, 
                                        fontSize: 18
                                      ),
                                    ),
                                  ),
                                  title: Wrap(
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Text(expense.name, style: TextStyle(color: textFrost, fontWeight: FontWeight.bold)),
                                      const SizedBox(width: 8),
                                      Text('(${expense.id})', style: TextStyle(color: textMuted)),
                                      
                                      if (expense.projectName != null && expense.projectName!.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: champagneGold.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: champagneGold.withValues(alpha: 0.5)),
                                          ),
                                          child: Text(
                                            expense.projectName!,
                                            style: TextStyle(color: champagneGold, fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ]
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
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (isHighValue) 
                                            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 16),
                                          if (isHighValue) 
                                            const SizedBox(width: 4),
                                          Text(
                                            expense.amountFormatted, 
                                            style: TextStyle(
                                              color: isHighValue ? Colors.redAccent.shade100 : textFrost, 
                                              fontWeight: FontWeight.w900, 
                                              fontSize: 15
                                            )
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(alpha: 0.08),
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
                            },
                          ),
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

  Widget _buildKpiCard(String title, String value, IconData icon, Color iconColor, ExpenseStore store, List<BoxShadow> cardShadows, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
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
                Icon(icon, color: iconColor, size: 18),
              ],
            ),
            const SizedBox(height: 16),
            Text(value, style: TextStyle(color: store.textFrost, fontSize: 28, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }

  Widget _buildBar(String label, double fillPercentage, ExpenseStore store) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 32,
          height: 120,
          decoration: BoxDecoration(
            color: store.isDarkMode ? store.bg : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: 32,
              height: 120 * fillPercentage,
              decoration: BoxDecoration(
                color: store.accentGold,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(label, style: TextStyle(color: store.textMuted, fontSize: 12)),
      ],
    );
  }
}