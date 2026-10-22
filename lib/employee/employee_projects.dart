import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/formatting.dart';
import '../management/download_stub.dart'
    if (dart.library.html) '../management/download_web.dart';
import '../management/expense_store.dart';
import '../shared/app_snack.dart';
import '../ui/expense_row.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// The projects the signed-in employee belongs to, with the budget each
/// one has burned so far.
class EmployeeProjectsScreen extends StatelessWidget {
  const EmployeeProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ExpenseStore store = ExpenseStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (BuildContext context, Widget? _) {
        final AppPalette palette = context.palette;
        final List<ProjectRecord> projects = store.myProjects;

        return Scaffold(
          backgroundColor: palette.bg,
          appBar: AppBar(title: const Text('My projects')),
          body: !store.projectsLoaded
              ? const Center(child: CircularProgressIndicator())
              : store.projectsError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: EmptyState(
                      // A failed load is not "no assignments" — surface
                      // the store's reason with a retry.
                      icon: Icons.cloud_off_rounded,
                      title: "Couldn't load projects",
                      message: store.projectsError,
                      action: OutlinedButton(
                        onPressed: () => store.fetchProjectsFromBackend(),
                        child: const Text('Retry'),
                      ),
                    ),
                  ),
                )
              : projects.isEmpty
              ? Center(
                  child: EmptyState(
                    icon: Icons.workspaces_outlined,
                    title: 'No active projects',
                    message:
                        'You have not been assigned to any project budgets '
                        'yet.',
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
                  itemCount: projects.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (BuildContext context, int index) {
                    final ProjectRecord project = projects[index];
                    final double burn = store.getProjectBurnAmount(
                      project.name,
                    );
                    final double used = safeFraction(
                      project.budget > 0 ? burn / project.budget : 0,
                    );

                    return AppCard(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (BuildContext context) =>
                              EmployeeProjectDetailsScreen(project: project),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  project.name,
                                  style: TextStyle(
                                    color: palette.text,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: palette.muted,
                                size: 20,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                '${formatFractionPercent(used, decimals: 1)} used',
                                style: TextStyle(
                                  color: palette.text,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${formatMoney(burn, compact: true)} of '
                                '${formatMoney(project.budget, compact: true)}',
                                style: TextStyle(
                                  color: palette.gold,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          AppProgressBar(
                            value: used,
                            color: used >= 1 ? palette.danger : palette.gold,
                            height: 8,
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

/// One project in full: the burn rate and the claims tagged to it.
class EmployeeProjectDetailsScreen extends StatelessWidget {
  const EmployeeProjectDetailsScreen({super.key, required this.project});

  final ProjectRecord project;

  @override
  Widget build(BuildContext context) {
    final ExpenseStore store = ExpenseStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (BuildContext context, Widget? _) {
        final AppPalette palette = context.palette;
        final List<ExpenseRecord> projectExpenses = store.myExpenses
            .where((ExpenseRecord e) => e.projectName == project.name)
            .toList(growable: false);
        final double burn = store.getProjectBurnAmount(project.name);
        final double used = safeFraction(
          project.budget > 0 ? burn / project.budget : 0,
        );

        return Scaffold(
          backgroundColor: palette.bg,
          appBar: AppBar(title: Text(project.name)),
          body: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                Text(
                                  'Budget used',
                                  style: TextStyle(
                                    color: palette.text,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  formatFractionPercent(used, decimals: 1),
                                  style: TextStyle(
                                    color: palette.gold,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            AppProgressBar(
                              value: used,
                              color: used >= 1 ? palette.danger : palette.gold,
                              height: 10,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '${formatMoney(burn)} of '
                              '${formatMoney(project.budget)} allocated',
                              style: TextStyle(
                                color: palette.muted,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),

                      SectionHeader(
                        title: 'My project claims',
                        subtitle: projectExpenses.isEmpty
                            ? null
                            : '${projectExpenses.length} claim'
                                  '${projectExpenses.length == 1 ? '' : 's'}',
                        trailing: OutlinedButton.icon(
                          onPressed: () => _exportCsv(context, projectExpenses),
                          icon: const Icon(Icons.download_rounded, size: 16),
                          label: const Text('Export CSV'),
                        ),
                      ),
                      if (projectExpenses.isEmpty)
                        AppCard(
                          child: EmptyState(
                            icon: Icons.receipt_long_rounded,
                            title: 'No claims tagged to this project',
                            message:
                                'Claims you submit against this project will '
                                'show up here.',
                            compact: true,
                          ),
                        )
                      else
                        ...projectExpenses.map(
                          (ExpenseRecord expense) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: ExpenseRow(
                              expense: expense,
                              showOwner: false,
                              showId: true,
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
      },
    );
  }

  void _exportCsv(BuildContext context, List<ExpenseRecord> expenses) {
    if (expenses.isEmpty) {
      AppSnack.error(context, 'No claims to download.');
      return;
    }
    final StringBuffer csv = StringBuffer(
      'Expense ID,Type,Amount,Date,Status\n',
    );
    for (final ExpenseRecord expense in expenses) {
      csv.writeln(
        '${expense.id},${expense.type},${expense.amount},'
        '${expense.date},${expense.status}',
      );
    }
    final int timestamp = DateTime.now().millisecondsSinceEpoch;
    final bool downloaded = downloadFile(
      utf8.encode(csv.toString()),
      '${project.name.replaceAll(' ', '_')}_Report_$timestamp.csv',
    );
    AppSnack.info(
      context,
      downloaded
          ? 'Download started.'
          : 'CSV export is available in the web build.',
    );
  }
}
