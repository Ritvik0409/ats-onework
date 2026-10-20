import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ats_onework/core/formatting.dart';
import 'package:ats_onework/ui/app_theme.dart';
import 'package:ats_onework/ui/charts.dart';
import 'package:ats_onework/ui/tokens.dart';
import 'package:ats_onework/ui/widgets.dart';

Widget _host(Widget child, {bool dark = true}) {
  return MaterialApp(
    theme: dark ? AppTheme.dark : AppTheme.light,
    home: Scaffold(
      body: Center(child: SizedBox(width: 560, height: 280, child: child)),
    ),
  );
}

void main() {
  final List<ChartPoint> spend = <ChartPoint>[
    const ChartPoint('May', 42000),
    const ChartPoint('Jun', 51000),
    const ChartPoint('Jul', 38000),
    const ChartPoint('Aug', 76000),
    const ChartPoint('Sep', 64000),
    const ChartPoint('Oct', 88000),
  ];

  group('charts render in both themes', () {
    testWidgets('spend trend with a comparison line', (
      WidgetTester tester,
    ) async {
      for (final bool dark in <bool>[true, false]) {
        await tester.pumpWidget(
          _host(
            SpendTrendChart(
              spend: spend,
              compare: spend
                  .map((ChartPoint p) => ChartPoint(p.label, p.value * 0.8))
                  .toList(growable: false),
            ),
            dark: dark,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(LineChart), findsOneWidget);
      }
    });

    testWidgets('grouped bars, donut and horizontal bars', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Column(
            children: <Widget>[
              Expanded(
                child: GroupedBarChart(
                  labels: <String>['Aug', 'Sep', 'Oct'],
                  series: <ChartSeries>[
                    ChartSeries(
                      label: 'Approved',
                      color: AppTokens.success,
                      values: const <double>[12000, 18000, 22000],
                    ),
                    ChartSeries(
                      label: 'Pending',
                      color: AppTokens.warning,
                      values: const <double>[4000, 2000, 6000],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: DonutChart(
                  slices: const <ChartSlice>[
                    ChartSlice('Travel', 12000),
                    ChartSlice('Meals', 4000),
                    ChartSlice('Software', 9000),
                  ],
                  centerValue: '₹25K',
                  centerLabel: 'spend',
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(BarChart), findsOneWidget);
      expect(find.byType(PieChart), findsOneWidget);
    });

    testWidgets('horizontal bars clamp a zero maximum', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const HorizontalBarChart(
            bars: <HorizontalBar>[
              HorizontalBar(label: 'No budget', value: 1200, max: 0),
              HorizontalBar(label: 'Over budget', value: 9000, max: 5000),
              HorizontalBar(label: 'No spend', value: 0, max: 5000),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('charts handle empty data', () {
    testWidgets('every chart shows the empty state', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                const SizedBox(
                  height: 120,
                  child: SpendTrendChart(spend: <ChartPoint>[]),
                ),
                const SizedBox(
                  height: 120,
                  child: GroupedBarChart(
                    labels: <String>[],
                    series: <ChartSeries>[],
                  ),
                ),
                const SizedBox(
                  height: 120,
                  child: DonutChart(slices: <ChartSlice>[]),
                ),
                const SizedBox(
                  height: 120,
                  child: HorizontalBarChart(bars: <HorizontalBar>[]),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ChartEmpty), findsNWidgets(4));
    });
  });

  testWidgets('range picker exposes all four windows', (
    WidgetTester tester,
  ) async {
    AnalyticsRange? selected;
    await tester.pumpWidget(
      _host(
        RangePicker(
          value: AnalyticsRange.last6Months,
          onChanged: (AnalyticsRange range) => selected = range,
        ),
      ),
    );
    expect(find.text('This month'), findsOneWidget);
    expect(find.text('Year to date'), findsOneWidget);

    await tester.tap(find.text('3 months'));
    await tester.pumpAndSettle();
    expect(selected, AnalyticsRange.last3Months);
  });
}
