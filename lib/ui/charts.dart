import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/formatting.dart';
import 'tokens.dart';
import 'widgets.dart';

/// Presentation-only chart primitives.
///
/// Screens pass already-aggregated values in; nothing here talks to the
/// network or reads the store. Every widget is theme-aware, guards
/// against empty/zero data, and formats money with the shared helpers so
/// axes and tooltips agree with the rest of the app.

/// One point on a trend line.
class ChartPoint {
  const ChartPoint(this.label, this.value);

  final String label;
  final double value;
}

/// One series in a grouped bar chart.
class ChartSeries {
  const ChartSeries({
    required this.label,
    required this.color,
    required this.values,
  });

  final String label;
  final Color color;
  final List<double> values;
}

/// One wedge of a donut.
class ChartSlice {
  const ChartSlice(this.label, this.value, {this.color});

  final String label;
  final double value;
  final Color? color;
}

/// One row of a horizontal bar chart.
class HorizontalBar {
  const HorizontalBar({
    required this.label,
    required this.value,
    this.max,
    this.color,
    this.caption,
  });

  final String label;
  final double value;
  final double? max;
  final Color? color;
  final String? caption;
}

/// Small shared empty state for chart cards.
class ChartEmpty extends StatelessWidget {
  const ChartEmpty({super.key, this.message = 'No data for this period.'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: EmptyState(
        icon: Icons.insights_rounded,
        title: message,
        compact: true,
      ),
    );
  }
}

double _maxOf(Iterable<double> values) {
  double max = 0;
  for (final double value in values) {
    if (value.isFinite && value > max) max = value;
  }
  return max;
}

double _niceCeiling(double value) {
  if (!value.isFinite || value <= 0) return 1;
  final double magnitude = math
      .pow(10, (math.log(value) / math.ln10).floor())
      .toDouble();
  for (final double step in <double>[1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 7.5, 10]) {
    final double candidate = step * magnitude;
    if (candidate >= value) return candidate;
  }
  return value * 1.2;
}

TextStyle _axisStyle(AppPalette palette) =>
    TextStyle(color: palette.muted, fontSize: 10, fontWeight: FontWeight.w600);

FlGridData _grid(AppPalette palette, double horizontalInterval) => FlGridData(
  show: true,
  drawVerticalLine: false,
  horizontalInterval: horizontalInterval,
  getDrawingHorizontalLine: (double value) => FlLine(
    color: palette.border,
    strokeWidth: 1,
    dashArray: const <int>[4, 4],
  ),
);

final FlBorderData _noBorder = FlBorderData(show: false);

/// Line chart for month-over-month spend. An optional second series
/// compares the previous period or the monthly budget.
class SpendTrendChart extends StatelessWidget {
  const SpendTrendChart({
    super.key,
    required this.spend,
    this.compare,
    this.compareLabel = 'Budget',
    this.primaryColor,
  });

  final List<ChartPoint> spend;
  final List<ChartPoint>? compare;
  final String compareLabel;
  final Color? primaryColor;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    if (spend.isEmpty) return const ChartEmpty();

    final Color primary = primaryColor ?? palette.gold;
    final Color secondary = palette.info;
    final List<ChartPoint>? comparison = compare != null && compare!.isNotEmpty
        ? compare
        : null;
    final int count = math.max(spend.length, comparison?.length ?? 0);

    final double maxY = _niceCeiling(
      math.max(
            _maxOf(spend.map((ChartPoint p) => p.value)),
            comparison == null
                ? 0
                : _maxOf(comparison.map((ChartPoint p) => p.value)),
          ) *
          1.15,
    );

    List<FlSpot> spotsFor(List<ChartPoint> points) => List<FlSpot>.generate(
      points.length,
      (int i) =>
          FlSpot(i.toDouble(), points[i].value.isFinite ? points[i].value : 0),
    );

    LineChartBarData line(
      List<ChartPoint> points,
      Color color, {
      bool area = false,
    }) {
      return LineChartBarData(
        spots: spotsFor(points),
        isCurved: points.length > 2,
        curveSmoothness: 0.25,
        preventCurveOverShooting: true,
        color: color,
        barWidth: 2.6,
        isStrokeCapRound: true,
        dotData: FlDotData(
          show: points.length <= 8,
          getDotPainter:
              (FlSpot spot, double percent, LineChartBarData bar, int index) =>
                  FlDotCirclePainter(
                    radius: 3,
                    color: palette.surface,
                    strokeWidth: 2,
                    strokeColor: color,
                  ),
        ),
        belowBarData: BarAreaData(
          show: area,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              color.withValues(alpha: 0.26),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      );
    }

    final int labelStep = math.max(1, (count / 6).ceil());

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: math.max(1, count - 1).toDouble(),
        minY: 0,
        maxY: maxY,
        clipData: const FlClipData.all(),
        borderData: _noBorder,
        gridData: _grid(palette, maxY / 4),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 46,
              interval: maxY / 2,
              getTitlesWidget: (double value, TitleMeta meta) {
                if (value < 0) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  space: 6,
                  child: Text(
                    formatMoney(value, compact: true),
                    style: _axisStyle(palette),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: (double value, TitleMeta meta) {
                final int index = value.round();
                if (index < 0 ||
                    index >= spend.length ||
                    index % labelStep != 0) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  space: 8,
                  child: Text(spend[index].label, style: _axisStyle(palette)),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBorderRadius: BorderRadius.circular(10),
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            getTooltipColor: (LineBarSpot spot) =>
                palette.isDark ? palette.surfaceAlt : AppTokens.lightText,
            getTooltipItems: (List<LineBarSpot> touched) {
              return touched.map((LineBarSpot spot) {
                final String label = spot.barIndex == 0
                    ? (spot.spotIndex < spend.length
                          ? spend[spot.spotIndex].label
                          : '')
                    : compareLabel;
                return LineTooltipItem(
                  '$label\n${formatMoney(spot.y)}',
                  TextStyle(
                    color: palette.isDark ? palette.text : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    height: 1.4,
                  ),
                );
              }).toList();
            },
          ),
          getTouchedSpotIndicator: (LineChartBarData bar, List<int> indexes) {
            return indexes
                .map(
                  (_) => TouchedSpotIndicatorData(
                    FlLine(color: bar.color ?? primary, strokeWidth: 1),
                    FlDotData(
                      getDotPainter: (spot, percent, barData, index) =>
                          FlDotCirclePainter(
                            radius: 4,
                            color: barData.color ?? primary,
                            strokeWidth: 2,
                            strokeColor: palette.surface,
                          ),
                    ),
                  ),
                )
                .toList();
          },
        ),
        lineBarsData: <LineChartBarData>[
          line(spend, primary, area: true),
          if (comparison != null)
            LineChartBarData(
              spots: spotsFor(comparison),
              isCurved: comparison.length > 2,
              color: secondary.withValues(alpha: 0.85),
              barWidth: 1.8,
              dashArray: const <int>[6, 4],
              dotData: const FlDotData(show: false),
            ),
        ],
      ),
    );
  }
}

/// Grouped column chart — one group per month, one rod per series.
class GroupedBarChart extends StatelessWidget {
  const GroupedBarChart({
    super.key,
    required this.labels,
    required this.series,
    this.formatValue,
  });

  final List<String> labels;
  final List<ChartSeries> series;

  /// Formats axis ticks and tooltips. Defaults to compact money; pass
  /// [formatCount] for charts that plot claim counts.
  final String Function(double value)? formatValue;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    if (labels.isEmpty || series.isEmpty) return const ChartEmpty();

    final double maxValue = _niceCeiling(
      _maxOf(series.expand((ChartSeries s) => s.values)) * 1.18,
    );
    final int labelStep = math.max(1, (labels.length / 7).ceil());
    final double rodWidth = series.length > 1 ? 9 : 18;
    final String Function(double) label =
        formatValue ?? (double v) => formatMoney(v, compact: true);

    return BarChart(
      BarChartData(
        maxY: maxValue,
        minY: 0,
        alignment: BarChartAlignment.spaceAround,
        borderData: _noBorder,
        gridData: _grid(palette, maxValue / 4),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            tooltipBorderRadius: BorderRadius.circular(10),
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            getTooltipColor: (BarChartGroupData group) =>
                palette.isDark ? palette.surfaceAlt : AppTokens.lightText,
            getTooltipItem:
                (
                  BarChartGroupData group,
                  int groupIndex,
                  BarChartRodData rod,
                  int rodIndex,
                ) {
                  final String name = rodIndex < series.length
                      ? series[rodIndex].label
                      : '';
                  return BarTooltipItem(
                    '$name\n${label(rod.toY)}',
                    TextStyle(
                      color: palette.isDark ? palette.text : Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  );
                },
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 46,
              interval: maxValue / 2,
              getTitlesWidget: (double value, TitleMeta meta) {
                if (value < 0) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  space: 6,
                  child: Text(label(value), style: _axisStyle(palette)),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: (double value, TitleMeta meta) {
                final int index = value.round();
                if (index < 0 ||
                    index >= labels.length ||
                    index % labelStep != 0) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  space: 8,
                  child: Text(labels[index], style: _axisStyle(palette)),
                );
              },
            ),
          ),
        ),
        barGroups: List<BarChartGroupData>.generate(
          labels.length,
          (int groupIndex) => BarChartGroupData(
            x: groupIndex,
            barsSpace: 4,
            barRods: series.map((ChartSeries s) {
              final double value = groupIndex < s.values.length
                  ? s.values[groupIndex]
                  : 0;
              return BarChartRodData(
                toY: value.isFinite ? value : 0,
                width: rodWidth,
                color: s.color,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: maxValue,
                  color: palette.surfaceAlt.withValues(alpha: 0.55),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

/// Donut with a centred total.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.slices,
    this.centerLabel,
    this.centerValue,
    this.radius = 26,
  });

  final List<ChartSlice> slices;
  final String? centerLabel;
  final String? centerValue;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final List<ChartSlice> visible = slices
        .where((ChartSlice s) => s.value.isFinite && s.value > 0)
        .toList(growable: false);
    if (visible.isEmpty) return const ChartEmpty();

    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        PieChart(
          PieChartData(
            sectionsSpace: 3,
            centerSpaceRadius: 58,
            startDegreeOffset: -90,
            borderData: FlBorderData(show: false),
            sections: List<PieChartSectionData>.generate(visible.length, (
              int index,
            ) {
              final ChartSlice slice = visible[index];
              return PieChartSectionData(
                value: slice.value,
                color: slice.color ?? palette.chartColor(index),
                radius: radius,
                showTitle: false,
              );
            }),
          ),
        ),
        if (centerValue != null)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                centerValue!,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              if (centerLabel != null)
                Text(
                  centerLabel!,
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// Horizontal bars used for project and category rankings. Values are
/// clamped defensively so a zero budget can never produce NaN.
class HorizontalBarChart extends StatelessWidget {
  const HorizontalBarChart({
    super.key,
    required this.bars,
    this.showCaption = true,
  });

  final List<HorizontalBar> bars;
  final bool showCaption;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    if (bars.isEmpty) return const ChartEmpty();

    final double maxValue = _maxOf(
      bars.map((HorizontalBar bar) => bar.max ?? bar.value),
    );

    return ListView.separated(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: bars.length,
      separatorBuilder: (BuildContext context, int index) =>
          const SizedBox(height: 14),
      itemBuilder: (BuildContext context, int index) {
        final HorizontalBar bar = bars[index];
        final Color color = bar.color ?? palette.chartColor(index);
        final double reference = bar.max ?? maxValue;
        final double fraction = reference > 0 ? bar.value / reference : 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    bar.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatMoney(bar.value, compact: true),
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            AppProgressBar(value: fraction, color: color, height: 7),
            if (showCaption && bar.caption != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                bar.caption!,
                style: TextStyle(color: palette.muted, fontSize: 10.5),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Tiny trend sparkline for KPI tiles.
class SparkLine extends StatelessWidget {
  const SparkLine({
    super.key,
    required this.values,
    this.color,
    this.height = 36,
  });

  final List<double> values;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    if (values.length < 2) return SizedBox(height: height);
    final Color lineColor = color ?? palette.gold;
    final double maxValue = _maxOf(values);

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (values.length - 1).toDouble(),
          minY: 0,
          maxY: maxValue <= 0 ? 1 : maxValue * 1.15,
          borderData: _noBorder,
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: <LineChartBarData>[
            LineChartBarData(
              spots: List<FlSpot>.generate(
                values.length,
                (int i) =>
                    FlSpot(i.toDouble(), values[i].isFinite ? values[i] : 0),
              ),
              isCurved: true,
              curveSmoothness: 0.3,
              preventCurveOverShooting: true,
              color: lineColor,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    lineColor.withValues(alpha: 0.22),
                    lineColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
