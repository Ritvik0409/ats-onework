import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_store.dart';

class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key});

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  static const Color obsidianBlack = Color(0xFF0D0D11);
  static const Color darkCharcoal = Color(0xFF16161F);
  static const Color champagneGold = Color(0xFFE2B93B);
  static const Color textFrost = Color(0xFFF3F4F6);
  static const Color textMuted = Color(0xFF9CA3AF);

  String _selectedFilter = 'All';
  final ExpenseStore _store = ExpenseStore.instance;

  Color _statusColor(String status) {
    if (status == 'Approved') return Colors.greenAccent.shade400;
    if (status == 'Rejected') return Colors.redAccent.shade400;
    return champagneGold;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final all = _store.myExpenses;
        final filtered = all.where((e) {
          if (_selectedFilter == 'All') return true;
          if (_selectedFilter == 'Pending') return e.status == 'Pending Verification';
          return e.status == _selectedFilter;
        }).toList();

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: darkCharcoal,
            elevation: 0,
            title: const Text('My Expenses', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold, fontSize: 20)),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(color: champagneGold.withValues(alpha: 0.15), height: 1),
            ),
          ),
          body: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600),
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                            labelStyle: TextStyle(color: isSelected ? obsidianBlack : textFrost, fontWeight: FontWeight.bold, fontSize: 13),
                            selectedColor: champagneGold,
                            backgroundColor: darkCharcoal,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(color: isSelected ? champagneGold : champagneGold.withValues(alpha: 0.15)),
                            ),
                            showCheckmark: false,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('No expenses in this category.', style: TextStyle(color: textMuted)))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final e = filtered[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 14),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: darkCharcoal,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: champagneGold.withValues(alpha: 0.1)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(color: champagneGold.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                                      child: const Icon(Icons.receipt_long_rounded, color: champagneGold, size: 20),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('${e.type} Expense', style: const TextStyle(color: textFrost, fontWeight: FontWeight.bold, fontSize: 14)),
                                          const SizedBox(height: 3),
                                          Text('${e.date} • ${e.id}', style: const TextStyle(color: textMuted, fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(e.amountFormatted, style: const TextStyle(color: textFrost, fontWeight: FontWeight.w900, fontSize: 14)),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: _statusColor(e.status).withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: _statusColor(e.status).withValues(alpha: 0.3)),
                                          ),
                                          child: Text(e.status, style: TextStyle(color: _statusColor(e.status), fontSize: 10, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                  ],
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