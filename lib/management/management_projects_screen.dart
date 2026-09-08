import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/management/download_web.dart';
import 'package:ats_onework/management/expense_details.dart'; 

class ManagementProjectsScreen extends StatefulWidget {
  const ManagementProjectsScreen({super.key});

  @override
  State<ManagementProjectsScreen> createState() => _ManagementProjectsScreenState();
}

class _ManagementProjectsScreenState extends State<ManagementProjectsScreen> {
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

        final projects = store.projects;

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: darkCharcoal,
            title: Text('Company Projects', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold)),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(color: champagneGold.withValues(alpha: 0.15), height: 1),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateProjectScreen()));
                  },
                  icon: Icon(Icons.add_rounded, color: champagneGold, size: 18),
                  label: Text('New Project', style: TextStyle(color: champagneGold, fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(backgroundColor: champagneGold.withValues(alpha: 0.1)),
                ),
              )
            ],
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
                          Text('Create a project to start tracking specific budgets.', style: TextStyle(color: textMuted)),
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
                              MaterialPageRoute(builder: (context) => ManagementProjectDetailsScreen(project: project)),
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
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: champagneGold.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text('${project.assignedEmails.length} Members', style: TextStyle(color: champagneGold, fontSize: 11, fontWeight: FontWeight.bold)),
                                    ),
                                    const SizedBox(width: 8),
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

class ManagementProjectDetailsScreen extends StatelessWidget {
  final ProjectRecord project;

  const ManagementProjectDetailsScreen({super.key, required this.project});

  void _showUpdateBudgetDialog(BuildContext context, ProjectRecord currentProj, ExpenseStore store) {
    final budgetCtrl = TextEditingController(text: currentProj.budget.toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          return AlertDialog(
            backgroundColor: store.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: store.accentGold.withValues(alpha: 0.2))),
            title: Text('Update Project Budget', style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Modify allocated budget for ${currentProj.name}.', style: TextStyle(color: store.textMuted, fontSize: 13)),
                const SizedBox(height: 16),
                TextField(
                  controller: budgetCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: store.textFrost),
                  decoration: InputDecoration(
                    labelText: 'New Budget (₹)',
                    labelStyle: TextStyle(color: store.textMuted),
                    filled: true,
                    fillColor: store.isDarkMode ? store.bg : Colors.grey.shade100,
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: store.accentGold.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(8)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: store.accentGold, width: 1.5), borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('Cancel', style: TextStyle(color: store.textMuted))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: store.accentGold, foregroundColor: store.isDarkMode ? store.bg : Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                onPressed: () async {
                  final newBudget = double.tryParse(budgetCtrl.text.trim());
                  if (newBudget != null && newBudget >= 0) {
                    await store.updateProjectBudget(currentProj.id, newBudget);
                    if (!dialogContext.mounted) return;
                    Navigator.pop(dialogContext);
                
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Project budget updated successfully!'), backgroundColor: store.accentGold));
                  } else {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid amount.'), backgroundColor: Colors.redAccent));
                  }
                },
                child: const Text('Save Budget', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  } 

  void _confirmCloseProject(BuildContext context, ProjectRecord currentProj, ExpenseStore store) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: store.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3))),
        title: Text('Close & Remove Project?', style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to close ${currentProj.name}? This will remove the project permanently.', style: TextStyle(color: store.textMuted, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('Cancel', style: TextStyle(color: store.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () async {
              Navigator.pop(dialogContext); 
              Navigator.pop(context); 
              await store.closeProject(currentProj.id);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Project closed and removed successfully.'), backgroundColor: Colors.redAccent));
            },
            child: const Text('Close Project', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
  
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

        final currentProject = store.projects.firstWhere((p) => p.id == project.id, orElse: () => project);
        final projectExpenses = store.expenses.where((e) => e.projectName == currentProject.name).toList();
        final burnAmount = store.getProjectBurnAmount(currentProject.name);
        final double pct = (burnAmount / currentProject.budget).clamp(0.0, 1.0);

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: darkCharcoal,
            foregroundColor: textFrost,
            title: Text(currentProject.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Project Burn Rate Tracker', style: TextStyle(color: textFrost, fontSize: 16, fontWeight: FontWeight.bold)),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.end,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _showUpdateBudgetDialog(context, currentProject, store),
                              icon: Icon(Icons.account_balance_wallet_rounded, color: champagneGold, size: 16),
                              label: const Text('Budget', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: champagneGold,
                                side: BorderSide(color: champagneGold.withValues(alpha: 0.5)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => ProjectMembersScreen(projectId: currentProject.id)));
                              },
                              icon: Icon(Icons.people_alt_rounded, color: champagneGold, size: 16),
                              label: const Text('Members', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: champagneGold,
                                side: BorderSide(color: champagneGold.withValues(alpha: 0.5)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _confirmCloseProject(context, currentProject, store),
                              icon: const Icon(Icons.lock_outline_rounded, color: Colors.redAccent, size: 16),
                              label: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.redAccent)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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
                              Text('₹${burnAmount.toStringAsFixed(0)} / ₹${currentProject.budget.toStringAsFixed(0)}', style: TextStyle(color: champagneGold, fontSize: 14, fontWeight: FontWeight.bold)),
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
                        Text('Project Ledger', style: TextStyle(color: textFrost, fontSize: 16, fontWeight: FontWeight.bold)),
                        OutlinedButton.icon(
                          onPressed: () {
                            if (projectExpenses.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No expenses to download.'), backgroundColor: Colors.redAccent));
                              return;
                            }
                            String csvContent = "Employee,Expense ID,Type,Amount,Date,Status\n";
                            for (var exp in projectExpenses) {
                              csvContent += "${exp.name.replaceAll(',', '')},${exp.id},${exp.type},${exp.amount},${exp.date},${exp.status}\n";
                            }
                            final bytes = utf8.encode(csvContent);
                            final timestamp = DateTime.now().millisecondsSinceEpoch;
                            downloadFile(bytes, '${currentProject.name.replaceAll(' ', '_')}_Report_$timestamp.csv');
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Download started!'), backgroundColor: champagneGold));
                          },
                          icon: Icon(Icons.download_rounded, color: champagneGold, size: 16),
                          label: const Text('Export CSV', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => ExpenseDetailsScreen(expenseId: expense.id)),
                              );
                            },
                            title: Wrap(
                               crossAxisAlignment: WrapCrossAlignment.center,
                               children: [
                                  Text(expense.name, style: TextStyle(color: textFrost, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 8),
                                  Text('(${expense.id})', style: TextStyle(color: textMuted, fontSize: 12)),
                               ],
                            ),
                            subtitle: Padding(
                               padding: const EdgeInsets.only(top: 4.0),
                               child: Text('${expense.type} Expense • ${expense.date}', style: TextStyle(color: textMuted, fontSize: 12)),
                            ),
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

class CreateProjectScreen extends StatefulWidget {
  const CreateProjectScreen({super.key});

  @override
  State<CreateProjectScreen> createState() => _CreateProjectScreenState();
}

class _CreateProjectScreenState extends State<CreateProjectScreen> {
  final _nameCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  
  String _searchQuery = '';
  final Set<String> _selectedEmails = {};
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _budgetCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _submit() async {
    final name = _nameCtrl.text.trim();
    final budgetText = _budgetCtrl.text.trim();
    
    if (name.isEmpty || budgetText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields'), backgroundColor: Colors.redAccent));
      return;
    }

    final budget = double.tryParse(budgetText);
    if (budget == null || budget <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid budget amount'), backgroundColor: Colors.redAccent));
      return;
    }

    setState(() => _isSubmitting = true);

    final finalEmails = _selectedEmails.toList();

    await ExpenseStore.instance.createProject(name, budget, finalEmails);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Project created successfully!'), backgroundColor: ExpenseStore.instance.accentGold));
      Navigator.pop(context);
    }
  }

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

        final allEmployees = store.allEmployees;
        final filteredEmployees = allEmployees.where((emp) {
          final q = _searchQuery.toLowerCase();
          return emp['name']!.toLowerCase().contains(q) || emp['email']!.toLowerCase().contains(q);
        }).toList();

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: obsidianBlack,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: textFrost),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text('Create Project Budget', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold, fontSize: 20)),
          ),
          body: Align(
            alignment: Alignment.topCenter,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Project Name', style: TextStyle(color: textFrost, fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameCtrl,
                      style: TextStyle(color: textFrost),
                      decoration: InputDecoration(
                        hintText: 'e.g. Project Alpha',
                        hintStyle: TextStyle(color: textMuted.withValues(alpha: 0.5)),
                        filled: true,
                        fillColor: darkCharcoal,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: champagneGold, width: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    Text('Allocated Budget (₹)', style: TextStyle(color: textFrost, fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _budgetCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(color: textFrost),
                      decoration: InputDecoration(
                        hintText: '0.00',
                        hintStyle: TextStyle(color: textMuted.withValues(alpha: 0.5)),
                        filled: true,
                        fillColor: darkCharcoal,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: champagneGold, width: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    Text('Assign Employees', style: TextStyle(color: textFrost, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),

                    if (_selectedEmails.isNotEmpty) ...[
                      Wrap(
                        spacing: 8.0,
                        runSpacing: 8.0,
                        children: _selectedEmails.map((email) {
                          final empData = allEmployees.firstWhere((e) => e['email'] == email, orElse: () => {'name': email});
                          return Chip(
                            backgroundColor: champagneGold,
                            deleteIconColor: Colors.black,
                            labelStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                            label: Text(empData['name'] ?? email),
                            onDeleted: () {
                              setState(() => _selectedEmails.remove(email));
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    TextField(
                      controller: _searchCtrl,
                      onChanged: (val) => setState(() => _searchQuery = val),
                      style: TextStyle(color: textFrost),
                      decoration: InputDecoration(
                        hintText: 'Search by name or email...',
                        hintStyle: TextStyle(color: textMuted.withValues(alpha: 0.5)),
                        prefixIcon: Icon(Icons.search_rounded, color: champagneGold),
                        filled: true,
                        fillColor: darkCharcoal,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Container(
                      decoration: BoxDecoration(
                        color: darkCharcoal,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: store.isDarkMode ? champagneGold.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)),
                        boxShadow: cardShadows,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredEmployees.length,
                        separatorBuilder: (context, index) => Divider(color: store.isDarkMode ? const Color(0xFF262633) : Colors.grey.shade200, height: 1),
                        itemBuilder: (context, index) {
                          final emp = filteredEmployees[index];
                          final isChecked = _selectedEmails.contains(emp['email']);
                          
                          return CheckboxListTile(
                            value: isChecked,
                            activeColor: champagneGold,
                            checkColor: store.isDarkMode ? Colors.black : Colors.white,
                            side: BorderSide(color: textMuted.withValues(alpha: 0.5)),
                            title: Text(emp['name'] ?? '', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold)),
                            subtitle: Text(emp['email'] ?? '', style: TextStyle(color: textMuted, fontSize: 12)),
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedEmails.add(emp['email']!);
                                } else {
                                  _selectedEmails.remove(emp['email']!);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: champagneGold,
                          foregroundColor: store.isDarkMode ? Colors.black : Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _isSubmitting 
                            ? SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: store.isDarkMode ? Colors.black : Colors.white, strokeWidth: 2))
                            : const Text('Create Project Budget', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class ProjectMembersScreen extends StatefulWidget {
  final String projectId;
  const ProjectMembersScreen({super.key, required this.projectId});

  @override
  State<ProjectMembersScreen> createState() => _ProjectMembersScreenState();
}

class _ProjectMembersScreenState extends State<ProjectMembersScreen> {
  void _showAddMemberDialog(BuildContext context, ProjectRecord project, ExpenseStore store) {
    final available = store.allEmployees.where((e) => !project.assignedEmails.contains(e['email'])).toList();
    final selectedEmails = <String>{};

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AnimatedBuilder(
              animation: store,
              builder: (context, _) {
                return AlertDialog(
                  backgroundColor: store.card,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: store.accentGold.withValues(alpha: 0.2))),
                  title: Text('Add Members', style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold)),
                  content: SizedBox(
                    width: double.maxFinite,
                    child: available.isEmpty
                        ? Padding(padding: const EdgeInsets.all(16), child: Text('No new employees available.', style: TextStyle(color: store.textMuted)))
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: available.length,
                            separatorBuilder: (_, _) => Divider(color: store.accentGold.withValues(alpha: 0.1), height: 1),
                            itemBuilder: (context, index) {
                              final emp = available[index];
                              final isChecked = selectedEmails.contains(emp['email']);
                              
                              return CheckboxListTile(
                                activeColor: store.accentGold,
                                checkColor: store.isDarkMode ? store.bg : Colors.white,
                                side: BorderSide(color: store.textMuted.withValues(alpha: 0.5)),
                                title: Text(emp['name'] ?? '', style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold)),
                                subtitle: Text('${emp['email']} • ${emp['id']}', style: TextStyle(color: store.textMuted, fontSize: 12)),
                                value: isChecked,
                                onChanged: (val) {
                                  setDialogState(() {
                                    if (val == true) {
                                      selectedEmails.add(emp['email']!);
                                    } else {
                                      selectedEmails.remove(emp['email']!);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('Cancel', style: TextStyle(color: store.textMuted))),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: store.accentGold, foregroundColor: store.isDarkMode ? store.bg : Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      onPressed: () async {
                        if (selectedEmails.isNotEmpty) {
                          await store.addMembersToProject(project.id, selectedEmails.toList());
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);
                          
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Members successfully added!'), backgroundColor: store.accentGold));
                        }
                      },
                      child: const Text('Add Selected', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _confirmRemoveMember(BuildContext context, ProjectRecord project, ExpenseStore store, String email, String empName) {
    showDialog(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          return AlertDialog(
            backgroundColor: store.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3))),
            title: Text('Remove Member?', style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold)),
            content: Text('Are you sure you want to remove $empName from this project?', style: TextStyle(color: store.textMuted, fontSize: 14)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('Cancel', style: TextStyle(color: store.textMuted))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await store.removeMemberFromProject(project.id, email);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$empName removed from project.'), backgroundColor: Colors.redAccent));
                },
                child: const Text('Remove', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ExpenseStore.instance,
      builder: (context, _) {
        final store = ExpenseStore.instance;
        final project = store.projects.firstWhere(
          (p) => p.id == widget.projectId,
          orElse: () => ProjectRecord(id: widget.projectId, name: 'Unknown', budget: 0, assignedEmails: [], isActive: false),
        );
        
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

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: darkCharcoal,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: textFrost),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text('${project.name} Members', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold, fontSize: 18)),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(color: champagneGold.withValues(alpha: 0.15), height: 1),
            ),
          ),
          body: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 800),
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${project.assignedEmails.length} Team Members', style: TextStyle(color: textFrost, fontSize: 16, fontWeight: FontWeight.bold)),
                      TextButton.icon(
                        onPressed: () => _showAddMemberDialog(context, project, store),
                        icon: Icon(Icons.person_add_alt_1_rounded, size: 16, color: champagneGold),
                        label: Text('Add Members', style: TextStyle(color: champagneGold, fontWeight: FontWeight.bold)),
                        style: TextButton.styleFrom(backgroundColor: champagneGold.withValues(alpha: 0.1)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: darkCharcoal,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: store.isDarkMode ? champagneGold.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.2)),
                        boxShadow: cardShadows,
                      ),
                      child: ListView.separated(
                        itemCount: project.assignedEmails.length,
                        separatorBuilder: (_, _) => Divider(color: store.isDarkMode ? champagneGold.withValues(alpha: 0.1) : Colors.grey.shade200, height: 1),
                        itemBuilder: (context, index) {
                          final email = project.assignedEmails[index];
                          
                          final empData = store.allEmployees.firstWhere(
                            (e) => e['email'] == email, 
                            orElse: () => {'name': email, 'email': email, 'id': 'EMP-UNKNOWN'}
                          );
                          
                          final isSelf = email == store.currentManagerEmail;

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            leading: CircleAvatar(
                              backgroundColor: champagneGold.withValues(alpha: 0.2),
                              child: Text(store.getInitials(empData['name'] ?? 'U'), style: TextStyle(color: champagneGold, fontWeight: FontWeight.bold)),
                            ),
                            title: Text(empData['name'] ?? email, style: TextStyle(color: textFrost, fontWeight: FontWeight.bold)),
                            subtitle: Text('${empData['email']} • ${empData['id']}', style: TextStyle(color: textMuted, fontSize: 12)),
                            trailing: isSelf ? const SizedBox.shrink() : IconButton(
                              icon: const Icon(Icons.person_remove_rounded, color: Colors.redAccent, size: 20),
                              onPressed: () => _confirmRemoveMember(context, project, store, email, empData['name'] ?? email),
                            ),
                          );
                        },
                      ),
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