import 'package:flutter/material.dart';

import '../core/formatting.dart';
import '../data/analytics_controller.dart';
import '../data/analytics_repository.dart';
import '../ui/charts.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'expense_store.dart';

/// Executive dashboard: outcome-level numbers, the shape of the review
/// queue (age and decision mix) and where the money is going.
class DirectorDashboard extends StatefulWidget {
  const DirectorDashboard({super.key, this.onReviewRequests});

  final VoidCallback? onReviewRequests;

  @override
  State<DirectorDashboard> createState() => _DirectorDashboardState();
}

class _DirectorDashboardState extends State<DirectorDashboard> {
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
                  title: 'Executive overview',
                  subtitle: data == null
                      ? 'Organization-wide spend and decisions'
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
                  _buildDecisionChart(data),
                  const SizedBox(height: 14),
                  _buildQueueAndSpenders(data, palette),
                  const SizedBox(height: 14),
                  _buildReimbursements(data, palette),
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
          subtitle: summary == null
              ? null
              : '${formatCount(summary.approvedCount + summary.reimbursedCount)} '
                  'approved or paid',
          trend: summary?.spendChangePct,
          trendLabel: 'vs prev',
          increaseIsGood: false,
        ),
        MetricCard(
          label: 'Budget utilisation',
          value: summary == null
              ? '—'
              : formatFractionPercent(summary.budgetUtilisation),
          icon: Icons.donut_large_rounded,
          accent: palette.success,
          subtitle: summary == null
              ? null
              : '${formatMoney(summary.budgetRemaining, compact: true)} left of '
                  '${formatMoney(summary.budgetAllocated, compact: true)}',
        ),
        MetricCard(
          label: 'Open approvals',
          value: summary == null ? '—' : formatCount(summary.openCount),
          icon: Icons.pending_actions_rounded,
          accent: palette.warning,
          subtitle: summary == null
              ? null
              : '${formatMoney(summary.openAmount, compact: true)} undecided',
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
              : '${formatCount(summary.rejectedCount)} rejected · '
                  '${formatCount(summary.pendingCount)} pending',
        ),
      ],
    );
  }

  Widget _buildDecisionChart(AnalyticsOverview? data) {
    final List<MonthlyPoint> monthly = data?.monthly ?? const <MonthlyPoint>[];
    return ChartCard(
      title: 'Decision mix over time',
      subtitle: 'Approved, pending and rejected value per month',
      height: 224,
      legend: const <ChartLegendItem>[
        ChartLegendItem('Approved', AppTokens.success),
        ChartLegendItem('Pending', AppTokens.warning),
        ChartLegendItem('Rejected', AppTokens.danger),
      ],
      child: GroupedBarChart(
        labels: monthly.map((MonthlyPoint p) => p.label).toList(growable: false),
        series: <ChartSeries>[
          ChartSeries(
            label: 'Approved',
            color: AppTokens.success,
            values: monthly
                .map((MonthlyPoint p) => p.approvedAmount)
                .toList(growable: false),
          ),
          ChartSeries(
            label: 'Pending',
            color: AppTokens.warning,
            values: monthly
                .map((MonthlyPoint p) => p.pendingAmount)
                .toList(growable: false),
          ),
          ChartSeries(
            label: 'Rejected',
            color: AppTokens.danger,
            values: monthly
                .map((MonthlyPoint p) => p.rejectedAmount)
                .toList(growable: false),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueAndSpenders(
    AnalyticsOverview? data,
    AppPalette palette,
  ) {
    final List<AgingBucket> aging = data?.aging ?? const <AgingBucket>[];
    final List<TopSpender> spenders =
        data?.topSpenders ?? const <TopSpender>[];

    final Widget agingCard = ChartCard(
      title: 'Review queue age',
      subtitle: 'How long pending claims have waited',
      height: 250,
      child: GroupedBarChart(
        labels: aging.map((AgingBucket b) => b.label).toList(growable: false),
        formatValue: (double value) => formatCount(value.round()),
        series: <ChartSeries>[
          ChartSeries(
            label: 'Claims',
            color: palette.gold,
            values: aging
                .map((AgingBucket b) => b.count.toDouble())
                .toList(growable: false),
          ),
        ],
      ),
    );

    final Widget spenderCard = ChartCard(
      title: 'Top spenders',
      subtitle: 'Approved or reimbursed, by employee',
      height: 250,
      child: HorizontalBarChart(
        bars: spenders
            .take(4)
            .map(
              (TopSpender s) => HorizontalBar(
                label: s.name,
                value: s.amount,
                caption: '${formatCount(s.count)} claims',
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
              agingCard,
              const SizedBox(height: 14),
              spenderCard,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: agingCard),
            const SizedBox(width: 14),
            Expanded(child: spenderCard),
          ],
        );
      },
    );
  }

  Widget _buildReimbursements(AnalyticsOverview? data, AppPalette palette) {
    final ReimbursementStats stats =
        data?.reimbursements ?? const ReimbursementStats();
    final double total = stats.paidAmount + stats.openAmount + stats.failedAmount;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: 'Reimbursement health',
            subtitle: stats.avgPaymentDays == null
                ? 'Payment lifecycle across the window'
                : 'Average ${stats.avgPaymentDays!.toStringAsFixed(1)} days '
                    'from approval to payment',
            trailing: widget.onReviewRequests == null
                ? null
                : TextButton(
                    onPressed: widget.onReviewRequests,
                    child: const Text('Open queue'),
                  ),
            padding: const EdgeInsets.only(bottom: 14),
          ),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool narrow = constraints.maxWidth < 560;
              final List<Widget> tiles = <Widget>[
                _MiniStat(
                  label: 'Paid out',
                  value: formatMoney(stats.paidAmount, compact: true),
                  detail: '${formatCount(stats.paidCount)} payments',
                  color: palette.success,
                ),
                _MiniStat(
                  label: 'In flight',
                  value: formatMoney(stats.openAmount, compact: true),
                  detail: '${formatCount(stats.openCount)} open',
                  color: palette.warning,
                ),
                _MiniStat(
                  label: 'Failed',
                  value: formatMoney(stats.failedAmount, compact: true),
                  detail: '${formatCount(stats.failedCount)} need retry',
                  color: palette.danger,
                ),
              ];
              if (narrow) {
                return Column(
                  children: <Widget>[
                    for (final Widget tile in tiles)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: tile,
                      ),
                  ],
                );
              }
              return Row(
                children: <Widget>[
                  for (int i = 0; i < tiles.length; i++) ...<Widget>[
                    Expanded(child: tiles[i]),
                    if (i != tiles.length - 1) const SizedBox(width: 12),
                  ],
                ],
              );
            },
          ),
          if (total > 0) ...<Widget>[
            const SizedBox(height: 16),
            AppProgressBar(
              value: stats.paidAmount / total,
              color: palette.success,
              height: 9,
            ),
            const SizedBox(height: 6),
            Text(
              '${formatFractionPercent(stats.paidAmount / total)} of all '
              'reimbursement value has been paid',
              style: TextStyle(color: palette.muted, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
  });

  final String label;
  final String value;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: palette.text,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(detail, style: TextStyle(color: palette.muted, fontSize: 11)),
        ],
      ),
    );
  }
}
