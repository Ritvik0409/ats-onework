import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_details.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/management/manager_reports.dart';

class ManagerRequestsScreen extends StatefulWidget {
  const ManagerRequestsScreen({super.key});

  @override
  State<ManagerRequestsScreen> createState() => _ManagerRequestsScreenState();
}

class _ManagerRequestsScreenState extends State<ManagerRequestsScreen> {
  String _searchQuery = '';
  String _selectedFilter = 'All';
  final ExpenseStore _store = ExpenseStore.instance;

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 600;

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

        final filteredExpenses = _store.expenses.where((expense) {
          // STRICT ANTI-SELF APPROVAL
          final uploaderEmail = expense.email.trim().toLowerCase();
          final myEmployeeEmail = _store.currentEmployeeEmail.trim().toLowerCase();
          final myManagerEmail = _store.currentManagerEmail.trim().toLowerCase();
          
          if (uploaderEmail == myEmployeeEmail || uploaderEmail == myManagerEmail) {
            return false;
          }

          // FIX: Date filter completely removed. You will now see the full history 
          // of everything you have Approved, Rejected, or Paid, regardless of age.
          
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

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: darkCharcoal,
            elevation: 0,
            title: Text('All Requests', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold, fontSize: 20)),
            actions: [
              if (isMobile)
                Padding(
                  padding: const EdgeInsets.only(right: 16.0, top: 8.0, bottom: 8.0),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('Reports', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: champagneGold,
                      side: BorderSide(color: champagneGold.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const ManagerReportsScreen()));
                    },
                  ),
                ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(color: champagneGold.withValues(alpha: 0.15), height: 1),
            ),
          ),
          body: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1000),
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
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
                      ),
                      if (!isMobile) ...[
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.download_rounded, size: 16),
                          label: const Text('Reports', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: champagneGold,
                            side: BorderSide(color: champagneGold.withValues(alpha: 0.5)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const ManagerReportsScreen()));
                          },
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: filteredExpenses.isEmpty
                        ? Center(child: Text('No matching expense logs found.', style: TextStyle(color: textMuted)))
                        : ListView.builder(
                            itemCount: filteredExpenses.length,
                            itemBuilder: (context, index) {
                              final expense = filteredExpenses[index];

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