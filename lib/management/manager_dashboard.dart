import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_details.dart';
import 'package:ats_onework/management/expense_store.dart';

class ManagerDashboardScreen extends StatefulWidget {
  const ManagerDashboardScreen({super.key});

  @override
  State<ManagerDashboardScreen> createState() => _ManagerDashboardScreenState();
}

class _ManagerDashboardScreenState extends State<ManagerDashboardScreen> {
  String _searchQuery = '';
  String _selectedFilter = 'All';

  static const Color obsidianBlack = Color(0xFF0D0D11);
  static const Color darkCharcoal = Color(0xFF16161F);
  static const Color champagneGold = Color(0xFFE2B93B);
  static const Color textFrost = Color(0xFFF3F4F6);
  static const Color textMuted = Color(0xFF9CA3AF);

  final ExpenseStore _store = ExpenseStore.instance;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final filteredExpenses = _store.expenses.where((expense) {
          final matchesSearch = expense.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              expense.id.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              expense.type.toLowerCase().contains(_searchQuery.toLowerCase());

          if (_selectedFilter == 'All') return matchesSearch;
          if (_selectedFilter == 'Pending') return matchesSearch && expense.status == 'Pending Verification';
          if (_selectedFilter == 'Approved') return matchesSearch && expense.status == 'Approved';
          if (_selectedFilter == 'Rejected') return matchesSearch && expense.status == 'Rejected';
          return matchesSearch;
        }).toList();

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: darkCharcoal,
            elevation: 0,
            title: const Text('All Requests', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold, fontSize: 20)),
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
                    style: const TextStyle(color: textFrost),
                    decoration: InputDecoration(
                      hintText: 'Search by employee name, ID or type...',
                      hintStyle: const TextStyle(color: textMuted, fontSize: 14),
                      prefixIcon: const Icon(Icons.search_rounded, color: champagneGold, size: 22),
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
                        borderSide: const BorderSide(color: champagneGold, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ['All', 'Pending', 'Approved', 'Rejected'].map((category) {
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
                              color: isSelected ? obsidianBlack : textFrost,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            selectedColor: champagneGold,
                            backgroundColor: darkCharcoal,
                            disabledColor: darkCharcoal,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: isSelected ? champagneGold : champagneGold.withValues(alpha: 0.15),
                              ),
                            ),
                            showCheckmark: false,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: filteredExpenses.isEmpty
                        ? const Center(child: Text('No matching expense logs found.', style: TextStyle(color: textMuted)))
                        : ListView.builder(
                            itemCount: filteredExpenses.length,
                            itemBuilder: (context, index) {
                              final expense = filteredExpenses[index];

                              Color statusColor = champagneGold;
                              if (expense.status == 'Approved') statusColor = Colors.greenAccent.shade400;
                              if (expense.status == 'Rejected') statusColor = Colors.redAccent.shade400;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 14),
                                decoration: BoxDecoration(
                                  color: darkCharcoal,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: champagneGold.withValues(alpha: 0.1), width: 1),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  leading: CircleAvatar(
                                    radius: 24,
                                    backgroundColor: champagneGold.withValues(alpha: 0.1),
                                    child: Text(
                                      expense.name.substring(0, 1),
                                      style: const TextStyle(color: champagneGold, fontWeight: FontWeight.bold, fontSize: 18),
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Text(expense.name, style: const TextStyle(color: textFrost, fontWeight: FontWeight.bold, fontSize: 16)),
                                      const SizedBox(width: 8),
                                      Text('(${expense.id})', style: const TextStyle(color: textMuted, fontSize: 12, fontFamily: 'monospace')),
                                    ],
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 6.0),
                                    child: Text(
                                      '${expense.type} Expense • ${expense.date}',
                                      style: const TextStyle(color: textMuted, fontSize: 13),
                                    ),
                                  ),
                                  trailing: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(expense.amountFormatted, style: const TextStyle(color: textFrost, fontWeight: FontWeight.w900, fontSize: 15)),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 1),
                                        ),
                                        child: Text(
                                          expense.status,
                                          style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ExpenseDetailsScreen(expenseId: expense.id),
                                      ),
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