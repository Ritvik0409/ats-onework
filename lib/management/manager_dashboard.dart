import 'package:flutter/material.dart';

import '../core/formatting.dart';
import '../data/analytics_controller.dart';
import '../data/analytics_repository.dart';
import '../ui/charts.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'budget_allocation_screen.dart';
import 'employee_management_screen.dart';
import 'expense_details.dart';
import 'expense_store.dart';

/// Team manager dashboard: whole-organization aggregates from the
/// analytics endpoint, a review queue that only contains claims the
/// manager may actually decide, and two charts that answer different
/// questions (trend over time, composition by category).
class ManagerDashboardScreen extends StatefulWidget {
  const ManagerDashboardScreen({
    super.key,
    this.onReviewRequests,
    this.onAddExpense,
  });

  final VoidCallback? onReviewRequests;
  final VoidCallback? onAddExpense;

  @override
  State<ManagerDashboardScreen> createState() => _ManagerDashboardScreenState();
}

class _ManagerDashboardScreenState extends State<ManagerDashboardScreen> {
  final ExpenseStore _store = ExpenseStore.instance;
  late final AnalyticsController _analytics;

  @override
  void initState() {
    super.initState();
    _analytics = AnalyticsController(personal: false);
    _analytics.load();
  }

  @override
  void dispose() {
    _analytics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_store, _analytics]),
      builder: (BuildContext context, Widget? _) {
        final AppPalette palette = context.palette;
        final AnalyticsOverview? data = _analytics.overview;
        final bool firstLoad = !_analytics.loaded && _analytics.loading;

        return Scaffold(
          backgroundColor: palette.bg,
          body: AppPage(
            busy: _analytics.loading && _analytics.loaded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                PageHeader(
                  title: 'Welcome, ${_store.currentUserName}',
                  subtitle: data == null
                      ? 'Team spend and approvals'
                      : '${formatDateRange(data.fromDate, data.toDate)} · '
                          '${formatCount(data.summary.totalClaims)} claims',
                  initials: _store.getInitials(_store.currentUserName),
                  trailing: RangePicker(
                    value: _analytics.range,
                    onChanged: _analytics.selectRange,
                  ),
                ),
                const SizedBox(height: 22),
                if (firstLoad)
                  const DashboardSkeleton()
                else ...<Widget>[
                  if (_analytics.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: InlineError(
                        message: _analytics.error!,
                        onRetry: _analytics.load,
                      ),
                    ),
                  _buildMetrics(data, palette),
                  const SizedBox(height: 20),
                  _buildTrend(data),
                  const SizedBox(height: 14),
                  _buildBreakdowns(data, palette),
                  const SizedBox(height: 20),
                  _buildQuickActions(palette),
                  const SizedBox(height: 22),
                  _buildUrgentQueue(palette),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetrics(AnalyticsOverview? data, AppPalette palette) {
    final AnalyticsSummary? summary = data?.summary;
    return AppGrid(
      minItemWidth: 200,
      children: <Widget>[
        MetricCard(
          label: 'Approved spend',
          value: summary == null
              ? '—'
              : formatMoney(summary.totalSpend, compact: true),
          icon: Icons.account_balance_wallet_rounded,
          accent: palette.gold,
          subtitle: 'Approved + reimbursed',
          trend: summary?.spendChangePct,
          trendLabel: 'vs prev',
          increaseIsGood: false,
        ),
        MetricCard(
          label: 'Open approvals',
          value: summary == null ? '—' : formatCount(summary.openCount),
          icon: Icons.hourglass_top_rounded,
          accent: palette.warning,
          subtitle: summary == null
              ? null
              : '${formatMoney(summary.openAmount, compact: true)} waiting',
        ),
        MetricCard(
          label: 'Budget remaining',
          value: summary == null
              ? '—'
              : formatMoney(summary.budgetRemaining, compact: true),
          icon: Icons.savings_rounded,
          accent: palette.success,
          subtitle: summary == null
              ? null
              : '${formatFractionPercent(summary.budgetUtilisation)} of '
                  '${formatMoney(summary.budgetAllocated, compact: true)}',
        ),
        MetricCard(
          label: 'Avg decision time',
          value: summary?.avgApprovalDays == null
              ? '—'
              : '${summary!.avgApprovalDays!.toStringAsFixed(1)}d',
          icon: Icons.timer_outlined,
          accent: palette.info,
          subtitle: summary == null
              ? null
              : '${formatCount(summary.approvedCount)} approved · '
                  '${formatCount(summary.rejectedCount)} rejected',
        ),
      ],
    );
  }

  Widget _buildTrend(AnalyticsOverview? data) {
    final List<MonthlyPoint> monthly = data?.monthly ?? const <MonthlyPoint>[];
    return ChartCard(
      title: 'Spend trend',
      subtitle: 'Monthly approved spend against the monthly budget',
      height: 220,
      legend: const <ChartLegendItem>[
        ChartLegendItem('Spend', AppTokens.gold),
        ChartLegendItem('Budget', AppTokens.info),
      ],
      child: SpendTrendChart(
        spend: monthly
            .map((MonthlyPoint p) => ChartPoint(p.label, p.spend))
            .toList(growable: false),
        compare: monthly
            .map((MonthlyPoint p) => ChartPoint(p.label, p.budget))
            .toList(growable: false),
        compareLabel: 'Budget',
      ),
    );
  }

  Widget _buildBreakdowns(AnalyticsOverview? data, AppPalette palette) {
    final List<CategorySlice> categories =
        data?.categories ?? const <CategorySlice>[];
    final List<ProjectSlice> projects =
        data?.projects ?? const <ProjectSlice>[];

    final List<CategorySlice> topCategories = _topCategories(categories);

    final Widget categoryCard = ChartCard(
      title: 'Where the money goes',
      subtitle: 'Approved spend by category',
      height: 250,
      legend: <ChartLegendItem>[
        for (int i = 0; i < topCategories.length; i++)
          ChartLegendItem(
            topCategories[i].name,
            palette.chartColor(i),
            value: formatMoney(topCategories[i].amount, compact: true),
          ),
      ],
      child: DonutChart(
        slices: <ChartSlice>[
          for (int i = 0; i < topCategories.length; i++)
            ChartSlice(
              topCategories[i].name,
              topCategories[i].amount,
              color: palette.chartColor(i),
            ),
        ],
        centerValue: data == null
            ? null
            : formatMoney(data.summary.totalSpend, compact: true),
        centerLabel: 'approved',
      ),
    );

    final List<ProjectSlice> topProjects = projects.toList()
      ..sort((ProjectSlice a, ProjectSlice b) => b.amount.compareTo(a.amount));
    final List<ProjectSlice> shown =
        topProjects.take(4).toList(growable: false);

    final Widget projectCard = ChartCard(
      title: 'Project burn',
      subtitle: 'Largest projects by approved spend',
      height: 250,
      child: HorizontalBarChart(
        bars: shown
            .map(
              (ProjectSlice p) => HorizontalBar(
                label: p.name,
                value: p.amount,
                max: p.budget > 0 ? p.budget : null,
                caption: p.budget > 0
                    ? '${formatFractionPercent(p.utilisation)} of '
                        '${formatMoney(p.budget, compact: true)} budget'
                    : '${formatCount(p.count)} claims · no budget set',
              ),
            )
            .toList(growable: false),
      ),
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            children: <Widget>[
              categoryCard,
              const SizedBox(height: 14),
              projectCard,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: categoryCard),
            const SizedBox(width: 14),
            Expanded(child: projectCard),
          ],
        );
      },
    );
  }

  /// Keeps the donut readable: five named categories plus an aggregate.
  List<CategorySlice> _topCategories(List<CategorySlice> categories) {
    if (categories.length <= 5) return categories;
    final List<CategorySlice> sorted = categories.toList()
      ..sort((CategorySlice a, CategorySlice b) => b.amount.compareTo(a.amount));
    final List<CategorySlice> top = sorted.take(4).toList();
    final double restAmount = sorted
        .skip(4)
        .fold<double>(0, (double sum, CategorySlice c) => sum + c.amount);
    final int restCount =
        sorted.skip(4).fold<int>(0, (int sum, CategorySlice c) => sum + c.count);
    if (restAmount > 0) {
      top.add(CategorySlice(name: 'Other', amount: restAmount, count: restCount));
    }
    return top;
  }

  Widget _buildQuickActions(AppPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(
          title: 'Quick actions',
          padding: EdgeInsets.only(bottom: 10),
        ),
        AppGrid(
          minItemWidth: 190,
          maxColumns: 4,
          children: <Widget>[
            if (widget.onReviewRequests != null)
              ActionTile(
                icon: Icons.fact_check_rounded,
                label: 'Review queue',
                onTap: widget.onReviewRequests!,
              ),
            if (widget.onAddExpense != null)
              ActionTile(
                icon: Icons.add_rounded,
                label: 'Submit an expense',
                accent: palette.info,
                onTap: widget.onAddExpense!,
              ),
            if (_store.can('budget.manage'))
              ActionTile(
                icon: Icons.account_balance_wallet_rounded,
                label: 'Budget allocation',
                accent: palette.success,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const BudgetAllocationScreen(),
                  ),
                ),
              ),
            if (_store.canManagePeople)
              ActionTile(
                icon: Icons.people_alt_rounded,
                label: 'Employee management',
                accent: palette.warning,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const EmployeeManagementScreen(),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildUrgentQueue(AppPalette palette) {
    final List<Map<String, dynamic>> urgent = _store.urgentRequests;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: 'Needs attention',
          subtitle: 'Stale or high-value claims in the queue',
          trailing: widget.onReviewRequests == null
              ? null
              : TextButton(
                  onPressed: widget.onReviewRequests,
                  child: const Text('Open queue'),
                ),
        ),
        if (!_store.expensesLoaded)
          const AppCard(child: SkeletonBox(height: 64, radius: 12))
        else if (urgent.isEmpty)
          AppCard(
            child: EmptyState(
              icon: Icons.task_alt_rounded,
              title: 'All caught up',
              message: 'No pending claim is older than two days.',
              compact: true,
            ),
          )
        else
          Column(
            children: urgent.map((Map<String, dynamic> item) {
              final ExpenseRecord request = item['expense'] as ExpenseRecord;
              final String reason = item['reason'] as String;
              final bool isSla = item['isSla'] as bool;
              final Color accent = isSla ? palette.danger : palette.warning;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  borderColor: accent.withValues(alpha: 0.35),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ExpenseDetailsScreen(expenseId: request.id),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusSm),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _store.getInitials(request.name),
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '${request.name} · ${request.type}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.text,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: <Widget>[
                                StatusBadge(
                                  status: reason,
                                  color: accent,
                                  icon: isSla
                                      ? Icons.schedule_rounded
                                      : Icons.priority_high_rounded,
                                ),
                                Text(
                                  formatMoney(request.amount),
                                  style: TextStyle(
                                    color: palette.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right_rounded,
                          color: palette.muted, size: 20),
                    ],
                  ),
                ),
              );
            }).toList(growable: false),
          ),
      ],
    );
  }
}
