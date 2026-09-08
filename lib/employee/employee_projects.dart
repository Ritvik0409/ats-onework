import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/management/download_web.dart';

class EmployeeProjectsScreen extends StatefulWidget {
  const EmployeeProjectsScreen({super.key});

  @override
  State<EmployeeProjectsScreen> createState() => _EmployeeProjectsScreenState();
}

class _EmployeeProjectsScreenState extends State<EmployeeProjectsScreen> {
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
        
        final List<BoxShadow> cardShadows = store.isDarkMode
            ? <BoxShadow>[]
            : [
                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 4)),
                BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 12), spreadRadius: -4),
                BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 2, offset: const Offset(0, -1)),
              ];

        final projects = store.myProjects;

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: darkCharcoal,
            title: Text('My Projects', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold)),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(color: champagneGold.withValues(alpha: 0.15), height: 1),
            ),
          ),
          body: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 800),
              child: projects.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.business_center_outlined, size: 64, color: textMuted.withValues(alpha: 0.5)),
                          const SizedBox(height: 16),
                          Text('No Active Projects', style: TextStyle(color: textFrost, fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text('You have not been assigned to any project budgets.', style: TextStyle(color: textMuted)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(24),
                      itemCount: projects.length,
                      itemBuilder: (context, index) {
                        final project = projects[index];
                        final burnAmount = store.getProjectBurnAmount(project.name);
                        final double pct = (burnAmount / project.budget).clamp(0.0, 1.0);

                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => EmployeeProjectDetailsScreen(project: project)),
                            );
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: darkCharcoal,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: store.isDarkMode ? champagneGold.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.2)),
                              boxShadow: cardShadows,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(child: Text(project.name, style: TextStyle(color: textFrost, fontSize: 18, fontWeight: FontWeight.bold))),
                                    Icon(Icons.info_outline_rounded, color: champagneGold),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Allocated Used: ${(pct * 100).toStringAsFixed(1)}%', style: TextStyle(color: textFrost, fontSize: 13, fontWeight: FontWeight.bold)),
                                    Text('₹${burnAmount.toStringAsFixed(0)} / ₹${project.budget.toStringAsFixed(0)}', style: TextStyle(color: champagneGold, fontSize: 13, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(
                                    value: pct,
                                    backgroundColor: store.isDarkMode ? obsidianBlack : Colors.grey.shade200,
                                    valueColor: AlwaysStoppedAnimation<Color>(champagneGold),
                                    minHeight: 8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        );
      },
    );
  }
}

class EmployeeProjectDetailsScreen extends StatelessWidget {
  final ProjectRecord project;

  const EmployeeProjectDetailsScreen({super.key, required this.project});

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
        
        final List<BoxShadow> cardShadows = store.isDarkMode
            ? <BoxShadow>[]
            : [
                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 4)),
                BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 12), spreadRadius: -4),
                BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 2, offset: const Offset(0, -1)),
              ];

        final projectExpenses = store.myExpenses.where((e) => e.projectName == project.name).toList();
        final burnAmount = store.getProjectBurnAmount(project.name);
        final double pct = (burnAmount / project.budget).clamp(0.0, 1.0);

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: darkCharcoal,
            foregroundColor: textFrost,
            title: Text(project.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(color: champagneGold.withValues(alpha: 0.15), height: 1),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Project Burn Rate Tracker', style: TextStyle(color: textFrost, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: darkCharcoal,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: store.isDarkMode ? champagneGold.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.2)),
                        boxShadow: cardShadows,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Allocated Limit Used: ${(pct * 100).toStringAsFixed(1)}%', style: TextStyle(color: textFrost, fontSize: 14, fontWeight: FontWeight.bold)),
                              Text('₹${burnAmount.toStringAsFixed(0)} / ₹${project.budget.toStringAsFixed(0)}', style: TextStyle(color: champagneGold, fontSize: 14, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: pct,
                              backgroundColor: store.isDarkMode ? obsidianBlack : Colors.grey.shade200,
                              valueColor: AlwaysStoppedAnimation<Color>(champagneGold),
                              minHeight: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('My Project Expenses', style: TextStyle(color: textFrost, fontSize: 16, fontWeight: FontWeight.bold)),
                        OutlinedButton.icon(
                          onPressed: () {
                            if (projectExpenses.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No expenses to download.'), backgroundColor: Colors.redAccent));
                              return;
                            }
                            String csvContent = "Expense ID,Type,Amount,Date,Status\n";
                            for (var exp in projectExpenses) {
                              csvContent += "${exp.id},${exp.type},${exp.amount},${exp.date},${exp.status}\n";
                            }
                            final bytes = utf8.encode(csvContent);
                            final timestamp = DateTime.now().millisecondsSinceEpoch;
                            downloadFile(bytes, '${project.name.replaceAll(' ', '_')}_Report_$timestamp.csv');
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Download started!'), backgroundColor: champagneGold));
                          },
                          icon: Icon(Icons.download_rounded, size: 16, color: champagneGold),
                          label: Text('Export CSV', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: champagneGold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: champagneGold,
                            side: BorderSide(color: champagneGold.withValues(alpha: 0.5)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (projectExpenses.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(color: darkCharcoal, borderRadius: BorderRadius.circular(16), border: Border.all(color: store.isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.2)), boxShadow: cardShadows),
                        child: Column(
                          children: [
                            Icon(Icons.receipt_long_rounded, size: 48, color: textMuted),
                            const SizedBox(height: 16),
                            Text('No expenses tagged to this project yet.', style: TextStyle(color: textMuted)),
                          ],
                        ),
                      )
                    else
                      ...projectExpenses.map((expense) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(color: darkCharcoal, borderRadius: BorderRadius.circular(12), border: Border.all(color: store.isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.2)), boxShadow: cardShadows),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            title: Text(expense.type, style: TextStyle(color: textFrost, fontWeight: FontWeight.bold)),
                            subtitle: Text(expense.date, style: TextStyle(color: textMuted, fontSize: 12)),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(expense.amountFormatted, style: TextStyle(color: champagneGold, fontWeight: FontWeight.bold, fontSize: 15)),
                                const SizedBox(height: 4),
                                Text(expense.status, style: TextStyle(color: _getStatusColor(expense.status), fontSize: 11, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    if (status == 'Approved' || status == 'Paid') return Colors.greenAccent;
    if (status == 'Rejected') return Colors.redAccent;
    return Colors.orangeAccent;
  }
}