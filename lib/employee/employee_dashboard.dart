import 'package:flutter/material.dart';

import '../core/formatting.dart';
import '../core/status.dart';
import '../data/analytics_controller.dart';
import '../data/analytics_repository.dart';
import '../management/expense_store.dart';
import '../ui/charts.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// Personal dashboard: the employee's own claim activity, answered by the
/// server-scoped `/analytics/me` endpoint instead of summing the first
/// page of expenses the device happens to hold.
class EmployeeDashboardScreen extends StatefulWidget {
  const EmployeeDashboardScreen({
    super.key,
    required this.onAddExpense,
    required this.onViewRequests,
    this.onViewProjects,
  });

  final VoidCallback onAddExpense;
  final VoidCallback onViewRequests;
  final VoidCallback? onViewProjects;

  @override
  State<EmployeeDashboardScreen> createState() =>
      _EmployeeDashboardScreenState();
}

class _EmployeeDashboardScreenState extends State<EmployeeDashboardScreen> {
  final ExpenseStore _store = ExpenseStore.instance;
  late final AnalyticsController _analytics;

  @override
  void initState() {
    super.initState();
    _analytics = AnalyticsController(personal: true);
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
        final PersonalAnalytics? data = _analytics.personalData;
        final bool firstLoad = !_analytics.loaded && _analytics.loading;

        return Scaffold(
          backgroundColor: palette.bg,
          body: AppPage(
            busy: _analytics.loading && _analytics.loaded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                PageHeader(
                  title: 'Hi, ${_firstName(_store.currentEmployeeName)}',
                  subtitle: data == null
                      ? 'Your expense activity'
                      : '${formatDateRange(data.fromDate, data.toDate)} · '
                            '${formatCount(data.summary.totalClaims)} claims',
                  initials: _store.getInitials(_store.currentEmployeeName),
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
                  _buildCharts(data, palette),
                  const SizedBox(height: 20),
                  _buildActions(),
                  const SizedBox(height: 22),
                  _buildRecent(palette),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _firstName(String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return 'there';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  Widget _buildMetrics(PersonalAnalytics? data, AppPalette palette) {
    final AnalyticsTotals? totals = data?.summary;
    return AppGrid(
      minItemWidth: 190,
      children: <Widget>[
        MetricCard(
          label: 'Total claims',
          value: totals == null ? '—' : formatCount(totals.totalClaims),
          icon: Icons.receipt_long_rounded,
          accent: palette.gold,
          subtitle: totals == null
              ? null
              : '${formatMoney(totals.totalSpend, compact: true)} '
                    'approved + paid',
        ),
        MetricCard(
          label: 'Awaiting decision',
          value: totals == null ? '—' : formatCount(totals.openCount),
          icon: Icons.hourglass_top_rounded,
          accent: palette.warning,
          subtitle: totals == null
              ? null
              : formatMoney(totals.openAmount, compact: true),
        ),
        MetricCard(
          label: 'Approved value',
          value: totals == null
              ? '—'
              : formatMoney(totals.approvedAmount, compact: true),
          icon: Icons.check_circle_outline_rounded,
          accent: palette.success,
          subtitle: totals == null
              ? null
              : '${formatCount(totals.approvedCount)} approved',
        ),
        MetricCard(
          label: 'Reimbursed',
          value: totals == null
              ? '—'
              : formatMoney(totals.reimbursedAmount, compact: true),
          icon: Icons.payments_rounded,
          accent: palette.info,
          subtitle: totals == null
              ? null
              : '${formatCount(totals.reimbursedCount)} paid out',
        ),
      ],
    );
  }

  Widget _buildCharts(PersonalAnalytics? data, AppPalette palette) {
    final List<MonthlyPoint> monthly = data?.monthly ?? const <MonthlyPoint>[];
    final List<StatusSlice> statuses =
        data?.statusBreakdown ?? const <StatusSlice>[];

    final Widget trend = ChartCard(
      title: 'Spend trend',
      subtitle: 'Approved and paid claims',
      height: 208,
      child: SpendTrendChart(
        spend: monthly
            .map((MonthlyPoint p) => ChartPoint(p.label, p.spend))
            .toList(growable: false),
      ),
    );

    final List<ChartSlice> slices = statuses
        .where((StatusSlice s) => s.count > 0)
        .map(
          (StatusSlice s) => ChartSlice(
            statusLabel(s.status),
            s.count.toDouble(),
            color: statusColor(s.status, palette),
          ),
        )
        .toList(growable: false);

    final Widget mix = ChartCard(
      title: 'Claim mix',
      subtitle: 'By current status',
      height: 208,
      legend: statuses
          .where((StatusSlice s) => s.count > 0)
          .map(
            (StatusSlice s) => ChartLegendItem(
              statusLabel(s.status),
              statusColor(s.status, palette),
              value: formatCount(s.count),
            ),
          )
          .toList(growable: false),
      child: DonutChart(
        slices: slices,
        centerValue: data == null
            ? null
            : formatCount(data.summary.totalClaims),
        centerLabel: 'claims',
      ),
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            children: <Widget>[trend, const SizedBox(height: 14), mix],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(flex: 3, child: trend),
            const SizedBox(width: 14),
            Expanded(flex: 2, child: mix),
          ],
        );
      },
    );
  }

  Widget _buildActions() {
    final AppPalette palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(
          title: 'Quick actions',
          subtitle: 'Everything you need in two taps',
          padding: EdgeInsets.only(bottom: 10),
        ),
        AppGrid(
          minItemWidth: 190,
          maxColumns: 3,
          children: <Widget>[
            ActionTile(
              icon: Icons.add_rounded,
              label: 'Submit an expense',
              onTap: widget.onAddExpense,
            ),
            ActionTile(
              icon: Icons.receipt_long_rounded,
              label: 'My claims',
              accent: palette.info,
              onTap: widget.onViewRequests,
            ),
            if (widget.onViewProjects != null)
              ActionTile(
                icon: Icons.workspaces_rounded,
                label: 'My projects',
                accent: palette.success,
                onTap: widget.onViewProjects!,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecent(AppPalette palette) {
    final List<ExpenseRecord> mine = _store.myExpenses.toList()
      ..sort((ExpenseRecord a, ExpenseRecord b) {
        final DateTime? left = parseLooseDate(a.date);
        final DateTime? right = parseLooseDate(b.date);
        if (left == null && right == null) return b.id.compareTo(a.id);
        if (left == null) return 1;
        if (right == null) return -1;
        return right.compareTo(left);
      });
    final List<ExpenseRecord> recent = mine.take(4).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: 'Recent requests',
          subtitle: 'Your latest submissions',
          trailing: TextButton(
            onPressed: widget.onViewRequests,
            child: const Text('View all'),
          ),
        ),
        if (_store.expensesError != null)
          // A failed load is not "no expenses yet" — surface why, the
          // same way the analytics sections above do.
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: InlineError(
              title: 'Could not load your claims',
              message: _store.expensesError!,
              onRetry: () => _store.fetchExpensesFromBackend(),
            ),
          )
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: recent.isEmpty
                ? EmptyState(
                    icon: Icons.upload_file_rounded,
                    title: 'No expenses submitted yet',
                    message: 'Submit your first claim to see it here.',
                    action: FilledButton.icon(
                      onPressed: widget.onAddExpense,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Submit expense'),
                    ),
                    compact: true,
                  )
                : Column(
                    children: <Widget>[
                      for (int i = 0; i < recent.length; i++) ...<Widget>[
                        _RecentRow(
                          expense: recent[i],
                          onTap: widget.onViewRequests,
                        ),
                        if (i != recent.length - 1)
                          Divider(height: 1, color: palette.border),
                      ],
                    ],
                  ),
          ),
      ],
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.expense, required this.onTap});

  final ExpenseRecord expense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final Color color = statusColor(expense.status, palette);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              ),
              child: Icon(statusIcon(expense.status), color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    expense.type,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    expense.date.isEmpty
                        ? statusLabel(expense.status)
                        : '${expense.date} · ${statusLabel(expense.status)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.muted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              formatMoney(expense.amount),
              style: TextStyle(
                color: palette.text,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
