import 'package:flutter/material.dart';

import '../core/formatting.dart';
import '../core/status.dart';
import '../data/analytics_controller.dart';
import '../data/analytics_repository.dart';
import '../shared/app_snack.dart';
import '../ui/charts.dart';
import '../ui/mark_paid_dialog.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'expense_details.dart';
import 'expense_store.dart';

/// Finance dashboard: the payout pipeline, the queue of approved claims
/// waiting to be paid, and the controls to complete a payment.
class FinanceDashboard extends StatefulWidget {
  const FinanceDashboard({super.key});

  @override
  State<FinanceDashboard> createState() => _FinanceDashboardState();
}

class _FinanceDashboardState extends State<FinanceDashboard> {
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
                  title: 'Finance & payouts',
                  subtitle: data == null
                      ? 'Move approved claims to paid'
                      : '${formatDateRange(data.fromDate, data.toDate)} · '
                            '${formatCount(data.summary.approvedCount)} approved '
                            'in period',
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
                  _buildPipelineAndStatus(data, palette),
                  const SizedBox(height: 14),
                  _buildTrend(data),
                  const SizedBox(height: 22),
                  _buildToPay(palette),
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
    final ReimbursementStats stats =
        data?.reimbursements ?? const ReimbursementStats();

    return AppGrid(
      minItemWidth: 200,
      children: <Widget>[
        MetricCard(
          label: 'Awaiting payment',
          value: summary == null
              ? '—'
              : formatMoney(summary.approvedAmount, compact: true),
          icon: Icons.pending_actions_rounded,
          accent: palette.warning,
          subtitle: summary == null
              ? null
              : '${formatCount(summary.approvedCount)} approved claims',
        ),
        MetricCard(
          label: 'Paid out',
          value: summary == null
              ? '—'
              : formatMoney(summary.reimbursedAmount, compact: true),
          icon: Icons.verified_rounded,
          accent: palette.success,
          subtitle: summary == null
              ? null
              : '${formatCount(summary.reimbursedCount)} reimbursements',
        ),
        MetricCard(
          label: 'In flight',
          value: formatMoney(stats.openAmount, compact: true),
          icon: Icons.sync_rounded,
          accent: palette.info,
          subtitle: '${formatCount(stats.openCount)} payments processing',
        ),
        MetricCard(
          label: 'Avg payment time',
          value: stats.avgPaymentDays == null
              ? '—'
              : '${stats.avgPaymentDays!.toStringAsFixed(1)}d',
          icon: Icons.timer_outlined,
          accent: palette.gold,
          subtitle: stats.failedCount > 0
              ? '${formatCount(stats.failedCount)} failed — needs retry'
              : 'From approval to paid',
        ),
      ],
    );
  }

  Widget _buildPipelineAndStatus(AnalyticsOverview? data, AppPalette palette) {
    final ReimbursementStats stats =
        data?.reimbursements ?? const ReimbursementStats();
    final double maxPipeline =
        <double>[
          stats.pendingAmount,
          stats.processingAmount,
          stats.paidAmount,
          stats.failedAmount,
        ].fold<double>(
          0,
          (double best, double value) => value > best ? value : best,
        );

    final Widget pipeline = ChartCard(
      title: 'Payout pipeline',
      subtitle: 'Value at each stage of reimbursement',
      height: 250,
      child: HorizontalBarChart(
        bars: <HorizontalBar>[
          HorizontalBar(
            label: 'Pending',
            value: stats.pendingAmount,
            max: maxPipeline,
            color: palette.warning,
            caption: '${formatCount(stats.pendingCount)} payments',
          ),
          HorizontalBar(
            label: 'Processing',
            value: stats.processingAmount,
            max: maxPipeline,
            color: palette.info,
            caption: '${formatCount(stats.processingCount)} payments',
          ),
          HorizontalBar(
            label: 'Paid',
            value: stats.paidAmount,
            max: maxPipeline,
            color: palette.success,
            caption: '${formatCount(stats.paidCount)} payments',
          ),
          if (stats.failedCount > 0)
            HorizontalBar(
              label: 'Failed',
              value: stats.failedAmount,
              max: maxPipeline,
              color: palette.danger,
              caption: '${formatCount(stats.failedCount)} payments',
            ),
        ],
      ),
    );

    final List<StatusSlice> statuses =
        data?.statusBreakdown ?? const <StatusSlice>[];
    final List<StatusSlice> visible = statuses
        .where((StatusSlice s) => s.amount > 0)
        .toList(growable: false);

    final Widget statusCard = ChartCard(
      title: 'Claims by status',
      subtitle: 'Value, not just count',
      height: 250,
      legend: visible
          .map(
            (StatusSlice s) => ChartLegendItem(
              statusLabel(s.status),
              statusColor(s.status, palette),
              value: formatMoney(s.amount, compact: true),
            ),
          )
          .toList(growable: false),
      child: DonutChart(
        slices: visible
            .map(
              (StatusSlice s) => ChartSlice(
                statusLabel(s.status),
                s.amount,
                color: statusColor(s.status, palette),
              ),
            )
            .toList(growable: false),
        centerValue: data == null
            ? null
            : formatMoney(
                data.summary.approvedAmount + data.summary.reimbursedAmount,
                compact: true,
              ),
        centerLabel: 'approved+paid',
      ),
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            children: <Widget>[
              pipeline,
              const SizedBox(height: 14),
              statusCard,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: pipeline),
            const SizedBox(width: 14),
            Expanded(child: statusCard),
          ],
        );
      },
    );
  }

  Widget _buildTrend(AnalyticsOverview? data) {
    final List<MonthlyPoint> monthly = data?.monthly ?? const <MonthlyPoint>[];
    return ChartCard(
      title: 'Reimbursement trend',
      subtitle: 'Approved spend per month',
      height: 200,
      child: SpendTrendChart(
        spend: monthly
            .map((MonthlyPoint p) => ChartPoint(p.label, p.spend))
            .toList(growable: false),
        primaryColor: context.palette.success,
      ),
    );
  }

  Widget _buildToPay(AppPalette palette) {
    final List<ExpenseRecord> approved =
        _store.expenses
            .where((ExpenseRecord e) => e.status == 'Approved')
            .toList()
          ..sort((ExpenseRecord a, ExpenseRecord b) {
            // Oldest first: those have waited longest for payment.
            final DateTime? left = parseLooseDate(a.date);
            final DateTime? right = parseLooseDate(b.date);
            if (left == null && right == null) return 0;
            if (left == null) return 1;
            if (right == null) return -1;
            return left.compareTo(right);
          });
    final double total = approved.fold<double>(
      0,
      (double sum, ExpenseRecord e) => sum + e.amount,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: 'Ready to pay',
          subtitle: approved.isEmpty
              ? 'Nothing waiting for payment'
              : '${formatCount(approved.length)} claims · '
                    '${formatMoney(total)}',
        ),
        if (!_store.expensesLoaded)
          const AppCard(child: SkeletonBox(height: 70, radius: 12))
        else if (approved.isEmpty)
          AppCard(
            child: EmptyState(
              icon: Icons.task_alt_rounded,
              title: 'Inbox zero',
              message: 'Every approved claim has been paid.',
              compact: true,
            ),
          )
        else
          Column(
            children: approved
                .map((ExpenseRecord expense) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ExpenseDetailsScreen(expenseId: expense.id),
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: palette.warning.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(
                                AppTokens.radiusSm,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _store.getInitials(expense.name),
                              style: TextStyle(
                                color: palette.warning,
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
                                  expense.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: palette.text,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${expense.type} · ${expense.date}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: palette.muted,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: <Widget>[
                              Text(
                                formatMoney(expense.amount),
                                style: TextStyle(
                                  color: palette.text,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                height: 30,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    textStyle: const TextStyle(fontSize: 11.5),
                                  ),
                                  onPressed: () =>
                                      _showMarkPaidDialog(expense, palette),
                                  child: const Text('Mark paid'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                })
                .toList(growable: false),
          ),
      ],
    );
  }

  Future<void> _showMarkPaidDialog(
    ExpenseRecord expense,
    AppPalette palette,
  ) async {
    final BuildContext messengerContext = context;
    final MarkPaidOutcome outcome = await showMarkPaidDialog(
      messengerContext,
      expense,
      store: _store,
    );
    if (!mounted || !messengerContext.mounted) return;
    if (outcome == MarkPaidOutcome.paid) {
      AppSnack.success(messengerContext, 'Expense marked as paid.');
    }
  }
}
