import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/management/download_stub.dart'
    if (dart.library.html) 'package:ats_onework/management/download_web.dart';
import 'package:ats_onework/management/expense_details.dart';
import 'package:ats_onework/core/status.dart';
import 'package:ats_onework/shared/app_snack.dart';
import 'package:ats_onework/ui/tokens.dart';
import 'package:ats_onework/ui/widgets.dart';

class ManagementProjectsScreen extends StatefulWidget {
  const ManagementProjectsScreen({super.key});

  @override
  State<ManagementProjectsScreen> createState() =>
      _ManagementProjectsScreenState();
}

class _ManagementProjectsScreenState extends State<ManagementProjectsScreen> {
  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final AppPalette palette = context.palette;
        final obsidianBlack = palette.bg;
        final darkCharcoal = palette.surface;
        final champagneGold = palette.gold;
        final textFrost = palette.text;
        final textMuted = palette.muted;

        final projects = store.projects;

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: darkCharcoal,
            title: Text(
              'Company Projects',
              style: TextStyle(color: textFrost, fontWeight: FontWeight.bold),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(
                color: champagneGold.withValues(alpha: 0.15),
                height: 1,
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CreateProjectScreen(),
                      ),
                    );
                  },
                  icon: Icon(Icons.add_rounded, color: champagneGold, size: 18),
                  label: Text(
                    'New Project',
                    style: TextStyle(
                      color: champagneGold,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor: champagneGold.withValues(alpha: 0.1),
                  ),
                ),
              ),
            ],
          ),
          body: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 800),
              child: !store.projectsLoaded
                  ? const Center(child: CircularProgressIndicator())
                  : projects.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.business_center_outlined,
                            size: 64,
                            color: textMuted.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No Active Projects',
                            style: TextStyle(
                              color: textFrost,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Create a project to start tracking specific budgets.',
                            style: TextStyle(color: textMuted),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
                      itemCount: projects.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final project = projects[index];
                        final burnAmount = store.getProjectBurnAmount(
                          project.name,
                        );
                        final double pct = safeFraction(
                          project.budget > 0 ? burnAmount / project.budget : 0,
                        );

                        return AppCard(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    ManagementProjectDetailsScreen(
                                      project: project,
                                    ),
                              ),
                            );
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      project.name,
                                      style: TextStyle(
                                        color: textFrost,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  if (!project.isActive) ...[
                                    AppTag(
                                      label: 'Deactivated',
                                      color: textMuted,
                                      dense: true,
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  AppTag(
                                    label: '${project.memberCount} members',
                                    icon: Icons.people_alt_rounded,
                                    dense: true,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${(pct * 100).toStringAsFixed(1)}% used',
                                    style: TextStyle(
                                      color: textFrost,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '₹${burnAmount.toStringAsFixed(0)} / ₹${project.budget.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      color: champagneGold,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              AppProgressBar(
                                value: pct,
                                color: pct >= 1 ? textMuted : champagneGold,
                                height: 8,
                              ),
                            ],
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

  void _showUpdateBudgetDialog(
    BuildContext context,
    ProjectRecord currentProj,
    ExpenseStore store,
  ) {
    final budgetCtrl = TextEditingController(
      text: currentProj.budget.toStringAsFixed(0),
    );

    showDialog(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          return AlertDialog(
            title: Text(
              'Update Project Budget',
              style: TextStyle(
                color: context.palette.text,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Modify allocated budget for ${currentProj.name}.',
                  style: TextStyle(
                    color: context.palette.muted,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: budgetCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: TextStyle(color: context.palette.text),
                  decoration: const InputDecoration(
                    labelText: 'New Budget (₹)',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: context.palette.muted),
                ),
              ),
              FilledButton(
                onPressed: () async {
                  final newBudget = double.tryParse(budgetCtrl.text.trim());
                  if (newBudget != null && newBudget >= 0) {
                    if (currentProj.budgetId == null) {
                      if (!context.mounted) return;
                      Navigator.pop(dialogContext);
                      AppSnack.error(
                        context,
                        'This project has no budget row to edit yet — create one on the Budgets screen.',
                      );
                      return;
                    }
                    final ok = await store.updateProjectBudget(
                      currentProj.id,
                      newBudget,
                    );
                    if (!dialogContext.mounted) return;
                    Navigator.pop(dialogContext);
                    if (!context.mounted) return;
                    if (ok) {
                      AppSnack.success(context, 'Project budget updated!');
                    } else {
                      AppSnack.error(
                        context,
                        "Couldn't update the budget — check your connection and try again.",
                      );
                    }
                  } else {
                    if (!context.mounted) return;
                    AppSnack.error(context, 'Please enter a valid amount.');
                  }
                },
                child: const Text(
                  'Save Budget',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmToggleProjectStatus(
    BuildContext context,
    ProjectRecord currentProj,
    ExpenseStore store,
  ) {
    final bool willBeActive = !currentProj.isActive;
    showDialog(
      context: context,
      builder: (dialogContext) {
        final AppPalette palette = dialogContext.palette;
        return AlertDialog(
        title: Text(
          willBeActive ? 'Resume Project?' : 'Deactivate Project?',
          style: TextStyle(
            color: palette.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          willBeActive
              ? 'Are you sure you want to resume ${currentProj.name}? This will re-enable budget modifications, member additions, and expense submissions.'
              : 'Are you sure you want to close ${currentProj.name}? This will mark the project as deactivated.',
          style: TextStyle(color: palette.muted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancel', style: TextStyle(color: palette.muted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: willBeActive ? palette.gold : palette.danger,
              foregroundColor: palette.isDark
                  ? AppTokens.darkBg
                  : Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              Navigator.pop(context);
              final ok = await store.toggleProjectActiveStatus(
                currentProj.id,
                willBeActive,
              );
              if (!context.mounted) return;
              if (ok) {
                AppSnack.success(
                  context,
                  willBeActive ? 'Project resumed!' : 'Project deactivated.',
                );
              } else {
                AppSnack.error(context, 'Could not update the project status.');
              }
            },
            child: Text(
              willBeActive ? 'Resume' : 'Deactivate',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final AppPalette palette = context.palette;
        final obsidianBlack = palette.bg;
        final darkCharcoal = palette.surface;
        final champagneGold = palette.gold;
        final textFrost = palette.text;
        final textMuted = palette.muted;

        final List<BoxShadow> cardShadows = palette.shadow;

        final currentProject = store.projects.firstWhere(
          (p) => p.id == project.id,
          orElse: () => project,
        );
        final projectExpenses = store.expenses
            .where((e) => e.projectName == currentProject.name)
            .toList();
        final burnAmount = store.getProjectBurnAmount(currentProject.name);
        final double pct = safeFraction(
          currentProject.budget > 0 ? burnAmount / currentProject.budget : 0,
        );

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: darkCharcoal,
            foregroundColor: textFrost,
            title: Text(
              currentProject.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(
                color: champagneGold.withValues(alpha: 0.15),
                height: 1,
              ),
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
                        Text(
                          'Project Burn Rate Tracker',
                          style: TextStyle(
                            color: textFrost,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.end,
                          children: [
                            OutlinedButton.icon(
                              onPressed: currentProject.isActive
                                  ? () => _showUpdateBudgetDialog(
                                      context,
                                      currentProject,
                                      store,
                                    )
                                  : null,
                              icon: Icon(
                                Icons.account_balance_wallet_rounded,
                                color: currentProject.isActive
                                    ? champagneGold
                                    : textMuted,
                                size: 16,
                              ),
                              label: Text(
                                'Budget',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: currentProject.isActive
                                      ? champagneGold
                                      : textMuted,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: champagneGold,
                                side: BorderSide(
                                  color: currentProject.isActive
                                      ? champagneGold.withValues(alpha: 0.5)
                                      : textMuted.withValues(alpha: 0.2),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ProjectMembersScreen(
                                      projectId: currentProject.id,
                                    ),
                                  ),
                                );
                              },
                              icon: Icon(
                                Icons.people_alt_rounded,
                                color: champagneGold,
                                size: 16,
                              ),
                              label: const Text(
                                'Members',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: champagneGold,
                                side: BorderSide(
                                  color: champagneGold.withValues(alpha: 0.5),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _confirmToggleProjectStatus(
                                context,
                                currentProject,
                                store,
                              ),
                              icon: Icon(
                                currentProject.isActive
                                    ? Icons.lock_outline_rounded
                                    : Icons.lock_open_rounded,
                                color: currentProject.isActive
                                    ? palette.danger
                                    : champagneGold,
                                size: 16,
                              ),
                              label: Text(
                                currentProject.isActive ? 'Close' : 'Resume',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: currentProject.isActive
                                      ? palette.danger
                                      : champagneGold,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: currentProject.isActive
                                    ? palette.danger
                                    : champagneGold,
                                side: BorderSide(
                                  color:
                                      (currentProject.isActive
                                              ? palette.danger
                                              : champagneGold)
                                          .withValues(alpha: 0.5),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
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
                        border: Border.all(color: textMuted.withValues(alpha: 0.25)),
                        boxShadow: cardShadows,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Allocated Limit Used: ${(pct * 100).toStringAsFixed(1)}%',
                                style: TextStyle(
                                  color: textFrost,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '₹${burnAmount.toStringAsFixed(0)} / ₹${currentProject.budget.toStringAsFixed(0)}',
                                style: TextStyle(
                                  color: champagneGold,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: pct,
                              backgroundColor: palette.surfaceAlt,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                champagneGold,
                              ),
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
                        Text(
                          'Project Ledger',
                          style: TextStyle(
                            color: textFrost,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            if (projectExpenses.isEmpty) {
                              AppSnack.info(context, 'No expenses to download.');
                              return;
                            }
                            String csvContent =
                                "Employee,Expense ID,Type,Amount,Date,Status\n";
                            for (var exp in projectExpenses) {
                              csvContent +=
                                  "${exp.name.replaceAll(',', '')},${exp.id},${exp.type},${exp.amount},${exp.date},${exp.status}\n";
                            }
                            final bytes = utf8.encode(csvContent);
                            final timestamp =
                                DateTime.now().millisecondsSinceEpoch;
                            final downloaded = downloadFile(
                              bytes,
                              '${currentProject.name.replaceAll(' ', '_')}_Report_$timestamp.csv',
                            );
                            downloaded
                                ? AppSnack.success(context, 'Download started!')
                                : AppSnack.info(
                                    context,
                                    'CSV export is available in the web build.',
                                  );
                          },
                          icon: Icon(
                            Icons.download_rounded,
                            color: champagneGold,
                            size: 16,
                          ),
                          label: const Text(
                            'Export CSV',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: champagneGold,
                            side: BorderSide(
                              color: champagneGold.withValues(alpha: 0.5),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (projectExpenses.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: darkCharcoal,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: textMuted.withValues(alpha: 0.25),
                          ),
                          boxShadow: cardShadows,
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.receipt_long_rounded,
                              size: 48,
                              color: textMuted,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No expenses tagged to this project yet.',
                              style: TextStyle(color: textMuted),
                            ),
                          ],
                        ),
                      )
                    else
                      ...projectExpenses.map((expense) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: darkCharcoal,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: textMuted.withValues(alpha: 0.25),
                            ),
                            boxShadow: cardShadows,
                          ),
                          child: Material(
                            color: darkCharcoal,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ExpenseDetailsScreen(
                                      expenseId: expense.id,
                                    ),
                                  ),
                                );
                              },
                              title: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    expense.name,
                                    style: TextStyle(
                                      color: textFrost,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '(${expense.id})',
                                    style: TextStyle(
                                      color: textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(
                                  '${expense.type} Expense • ${expense.date}',
                                  style: TextStyle(
                                    color: textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    expense.amountFormatted,
                                    style: TextStyle(
                                      color: champagneGold,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    expense.status == 'Approved'
                                        ? 'Payment Pending'
                                        : expense.status,
                                    style: TextStyle(
                                      color: _getStatusColor(
                                        context,
                                        expense.status,
                                      ),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
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

  Color _getStatusColor(BuildContext context, String status) =>
      statusColor(status, context.palette);
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
  final Set<String> _selectedEmployeeIds = {};
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
      AppSnack.error(context, 'Please fill all fields');
      return;
    }

    final budget = double.tryParse(budgetText);
    if (budget == null || budget <= 0) {
      AppSnack.error(context, 'Please enter a valid budget amount.');
      return;
    }

    setState(() => _isSubmitting = true);

    final finalIds = _selectedEmployeeIds.toList();

    final error = await ExpenseStore.instance.createProject(
      name,
      budget,
      finalIds,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (error != null) {
      AppSnack.error(context, error);
      return;
    }
    AppSnack.success(context, 'Project created!');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final AppPalette palette = context.palette;
        final obsidianBlack = palette.bg;
        final darkCharcoal = palette.surface;
        final champagneGold = palette.gold;
        final textFrost = palette.text;
        final textMuted = palette.muted;

        final List<BoxShadow> cardShadows = palette.shadow;

        final allEmployees = store.allEmployees;
        final filteredEmployees = allEmployees.where((emp) {
          final q = _searchQuery.toLowerCase();
          return emp['name']!.toLowerCase().contains(q) ||
              emp['id']!.toLowerCase().contains(q);
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
            title: Text(
              'Create Project',
              style: TextStyle(
                color: textFrost,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
          body: Align(
            alignment: Alignment.topCenter,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600),
              padding: const EdgeInsets.all(24.0),
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Text(
                    'Project Name',
                    style: TextStyle(
                      color: textFrost,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameCtrl,
                    style: TextStyle(color: textFrost),
                    decoration: InputDecoration(
                      hintText: 'e.g. Project Alpha',
                      hintStyle: TextStyle(
                        color: textMuted.withValues(alpha: 0.5),
                      ),
                      filled: true,
                      fillColor: darkCharcoal,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: champagneGold,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    'Allocated Budget (₹)',
                    style: TextStyle(
                      color: textFrost,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _budgetCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: TextStyle(color: textFrost),
                    decoration: InputDecoration(
                      hintText: '0.00',
                      hintStyle: TextStyle(
                        color: textMuted.withValues(alpha: 0.5),
                      ),
                      filled: true,
                      fillColor: darkCharcoal,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: champagneGold,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Text(
                    'Assign Employees',
                    style: TextStyle(
                      color: textFrost,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (_selectedEmployeeIds.isNotEmpty) ...[
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: _selectedEmployeeIds.map((empId) {
                        final empData = allEmployees.firstWhere(
                          (e) => e['id'] == empId,
                          orElse: () => {'name': empId, 'id': empId},
                        );
                        return Chip(
                          backgroundColor: champagneGold,
                          labelStyle: TextStyle(
                            color: palette.isDark
                                ? AppTokens.darkBg
                                : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          label: Text(
                            '${empData['name']} (${empData['id']})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onDeleted: () {
                            setState(() => _selectedEmployeeIds.remove(empId));
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],

                  TextField(
                    controller: _searchCtrl,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: TextStyle(color: textFrost),
                    decoration: InputDecoration(
                      hintText: 'Search by name or Employee ID...',
                      hintStyle: TextStyle(
                        color: textMuted.withValues(alpha: 0.5),
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: champagneGold,
                      ),
                      filled: true,
                      fillColor: darkCharcoal,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    height: 220,
                    child: Container(
                      decoration: BoxDecoration(
                        color: darkCharcoal,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: textMuted.withValues(alpha: 0.25),
                        ),
                        boxShadow: cardShadows,
                      ),
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: filteredEmployees.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    store.usersError != null
                                        ? store.usersError!
                                        : _searchQuery.isEmpty
                                        ? 'Loading the member directory…'
                                        : 'No employees match "$_searchQuery".',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: textMuted,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.separated(
                          shrinkWrap: false,
                          itemCount: filteredEmployees.length,
                          separatorBuilder: (context, index) => Divider(
                            color: palette.border,
                            height: 1,
                          ),
                          itemBuilder: (context, index) {
                            final emp = filteredEmployees[index];
                            final empId = emp['id']!;
                            final isChecked = _selectedEmployeeIds.contains(
                              empId,
                            );

                            return CheckboxListTile(
                              value: isChecked,
                              activeColor: champagneGold,
                              checkColor: Theme.of(
                                context,
                              ).colorScheme.onPrimary,
                              side: BorderSide(
                                color: textMuted.withValues(alpha: 0.5),
                              ),
                              title: Text(
                                emp['name'] ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: textFrost,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                'ID: $empId • ${emp['email'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: textMuted,
                                  fontSize: 12,
                                ),
                              ),
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedEmployeeIds.add(empId);
                                  } else {
                                    _selectedEmployeeIds.remove(empId);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _isSubmitting ? null : _submit,
                      icon: _isSubmitting
                          ? SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                color: palette.isDark
                                    ? AppTokens.darkBg
                                    : Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.add_rounded, size: 18),
                      label: const Text(
                        'Create Project',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
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
}

class ProjectMembersScreen extends StatefulWidget {
  final String projectId;
  const ProjectMembersScreen({super.key, required this.projectId});

  @override
  State<ProjectMembersScreen> createState() => _ProjectMembersScreenState();
}

class _ProjectMembersScreenState extends State<ProjectMembersScreen> {
  @override
  void initState() {
    super.initState();
    // Real roster: GET /projects/{id}/members (§49 24a).
    ExpenseStore.instance.fetchProjectMembersFromBackend(widget.projectId);
  }

  void _showAddMemberDialog(
    BuildContext context,
    ProjectRecord project,
    ExpenseStore store,
  ) {
    if (!project.isActive) {
      AppSnack.error(context, 'Cannot add members to a deactivated project.');
      return;
    }

    final memberIds =
        (store.projectMembersByProject[widget.projectId] ?? const [])
            .map((m) => m.employeeId)
            .toSet();
    final available = store.allEmployees
        .where((e) => !memberIds.contains(e['id']))
        .toList();
    final selectedIds = <String>{};
    bool adding = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final AppPalette palette = context.palette;
            return AlertDialog(
              title: const Text('Add Members'),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 480,
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: available.isEmpty
                    ? Center(
                        child: Text(
                          'No new employees available.',
                          style: TextStyle(color: palette.muted),
                        ),
                      )
                    : Scrollbar(
                        thumbVisibility: true,
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: available.length,
                          separatorBuilder: (_, _) =>
                              Divider(color: palette.border, height: 1),
                          itemBuilder: (context, index) {
                            final emp = available[index];
                            final empId = emp['id']!;
                            final isChecked = selectedIds.contains(empId);

                            return CheckboxListTile(
                              activeColor: palette.gold,
                              checkColor: Theme.of(
                                context,
                              ).colorScheme.onPrimary,
                              side: BorderSide(
                                color: palette.muted.withValues(alpha: 0.5),
                              ),
                              title: Text(
                                emp['name'] ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.text,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                'ID: $empId • ${emp['email']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.muted,
                                  fontSize: 12,
                                ),
                              ),
                              value: isChecked,
                              onChanged: (val) {
                                setDialogState(() {
                                  if (val == true) {
                                    selectedIds.add(empId);
                                  } else {
                                    selectedIds.remove(empId);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: adding ? null : () => Navigator.pop(dialogContext),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: palette.muted),
                  ),
                ),
                FilledButton(
                  onPressed: adding || selectedIds.isEmpty
                      ? null
                      : () async {
                          setDialogState(() => adding = true);
                          final ok = await store.addMembersToProject(
                            project.id,
                            selectedIds.toList(),
                          );
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);

                          if (ok) {
                            await store.fetchProjectMembersFromBackend(
                              project.id,
                            );
                          }
                          // Guard directly before use — the fetch above is
                          // another async gap after the pop.
                          if (!context.mounted) return;
                          if (ok) {
                            AppSnack.success(context, 'Members added!');
                          } else {
                            AppSnack.error(
                              context,
                              'Some members could not be added. Please try again.',
                            );
                          }
                        },
                  child: adding
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Add Selected',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmRemoveMember(
    BuildContext context,
    ProjectRecord project,
    ExpenseStore store,
    String empId,
    String empName,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final AppPalette palette = dialogContext.palette;
        return AlertDialog(
          title: Text(
            'Remove Member?',
            style: TextStyle(
              color: palette.text,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Are you sure you want to remove $empName from this project?',
            style: TextStyle(color: palette.muted, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Cancel', style: TextStyle(color: palette.muted)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: palette.danger,
                foregroundColor: palette.isDark
                    ? AppTokens.darkBg
                    : Colors.white,
              ),
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  final ok = await store.removeMemberFromProject(
                    project.id,
                    empId,
                  );
                  if (ok) {
                    await store.fetchProjectMembersFromBackend(project.id);
                  }
                  if (!context.mounted) return;
                  if (ok) {
                    AppSnack.success(context, '$empName removed from project.');
                  } else {
                    AppSnack.error(
                      context,
                      'Could not remove $empName. Please try again.',
                    );
                  }
                },
                child: const Text(
                  'Remove',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
        );
      },
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
          orElse: () => ProjectRecord(
            id: widget.projectId,
            name: 'Unknown',
            budget: 0,
            assignedEmails: [],
            isActive: false,
          ),
        );

        final roster =
            store.projectMembersByProject[widget.projectId] ??
            const <ProjectMemberRecord>[];
        final membersLoading = store.projectMembersLoading && roster.isEmpty;

        final AppPalette palette = context.palette;
        final obsidianBlack = palette.bg;
        final darkCharcoal = palette.surface;
        final champagneGold = palette.gold;
        final textFrost = palette.text;
        final textMuted = palette.muted;
        final List<BoxShadow> cardShadows = palette.shadow;

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: darkCharcoal,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: textFrost),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              '${project.name} Members',
              style: TextStyle(
                color: textFrost,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(
                color: champagneGold.withValues(alpha: 0.15),
                height: 1,
              ),
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
                      Text(
                        '${(store.projectMembersByProject[widget.projectId] ?? const <ProjectMemberRecord>[]).length} Team Members',
                        style: TextStyle(
                          color: textFrost,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (project.isActive)
                        TextButton.icon(
                          onPressed: () =>
                              _showAddMemberDialog(context, project, store),
                          icon: Icon(
                            Icons.person_add_alt_1_rounded,
                            size: 16,
                            color: champagneGold,
                          ),
                          label: Text(
                            'Add Members',
                            style: TextStyle(
                              color: champagneGold,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            backgroundColor: champagneGold.withValues(
                              alpha: 0.1,
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: palette.danger.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Project Deactivated',
                            style: TextStyle(
                              color: palette.danger,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: darkCharcoal,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: textMuted.withValues(alpha: 0.25),
                        ),
                        boxShadow: cardShadows,
                      ),
                      child: membersLoading
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(
                                    color: champagneGold,
                                    strokeWidth: 2.5,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Loading members…',
                                    style: TextStyle(
                                      color: textMuted,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              // Real roster from GET /projects/{id}/members —
                              // assignedEmails is never populated by the backend.
                              itemCount: roster.length,
                              separatorBuilder: (_, _) =>
                              Divider(color: palette.border, height: 1),
                              itemBuilder: (context, index) {
                                final member = roster[index];
                                final empId = member.employeeId;
                                final isSelf = empId == store.currentUserId;

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: champagneGold.withValues(
                                      alpha: 0.2,
                                    ),
                                    child: Text(
                                      store.getInitials(
                                        member.name.isNotEmpty
                                            ? member.name
                                            : 'U',
                                      ),
                                      style: TextStyle(
                                        color: champagneGold,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    member.name.isNotEmpty
                                        ? member.name
                                        : empId,
                                    style: TextStyle(
                                      color: textFrost,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    member.roleName.isNotEmpty
                                        ? 'ID: $empId • ${member.email} • ${member.roleName}'
                                        : 'ID: $empId • ${member.email}',
                                    style: TextStyle(
                                      color: textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  trailing: (!project.isActive || isSelf)
                                      ? const SizedBox.shrink()
                                      : IconButton(
                                          tooltip: 'Remove from project',
                                          icon: Icon(
                                            Icons.person_remove_rounded,
                                            color: palette.danger,
                                            size: 20,
                                          ),
                                          onPressed: () => _confirmRemoveMember(
                                            context,
                                            project,
                                            store,
                                            empId,
                                            member.name,
                                          ),
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
