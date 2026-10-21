import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ats_onework/core/formatting.dart';
import 'package:ats_onework/core/status.dart';
import 'package:ats_onework/ui/tokens.dart';
import 'package:ats_onework/ui/widgets.dart';

void main() {
  group('formatMoney', () {
    test('uses Indian digit grouping', () {
      expect(formatMoney(124500), '₹1,24,500');
      expect(formatMoney(1000), '₹1,000');
    });

    test('keeps paise when the amount is not whole', () {
      expect(formatMoney(499.5), '₹499.50');
    });

    test('compacts to lakhs and crores', () {
      expect(formatMoney(150000, compact: true), '₹1.5L');
      expect(formatMoney(25000000, compact: true), '₹2.5Cr');
      expect(formatMoney(2500, compact: true), '₹2.5K');
    });
  });

  group('percent helpers', () {
    test('formatFractionPercent turns a fraction into points', () {
      expect(formatFractionPercent(0.425), '43%');
      expect(formatFractionPercent(0.425, decimals: 1), '42.5%');
    });

    test('guards non-finite input', () {
      expect(formatFractionPercent(double.nan), '0%');
      expect(formatFractionPercent(double.infinity), '0%');
    });

    test('formatSignedPercent keeps the sign', () {
      expect(formatSignedPercent(12.34), '+12.3%');
      expect(formatSignedPercent(-5), '-5.0%');
      expect(formatSignedPercent(null), '—');
    });
  });

  group('parseLooseDate', () {
    test('parses ISO dates and datetimes', () {
      expect(parseLooseDate('2026-10-20'), DateTime(2026, 10, 20));
      // The old store parser produced day "20T09:15:00" and dropped the row.
      expect(parseLooseDate('2026-10-20T09:15:00'), DateTime(2026, 10, 20));
    });

    test('parses the legacy display format', () {
      expect(parseLooseDate('20 Oct 2026'), DateTime(2026, 10, 20));
      expect(parseLooseDate('5 jan 2026'), DateTime(2026, 1, 5));
    });

    test('parses day-first and month-first slash dates', () {
      expect(parseLooseDate('20/10/2026'), DateTime(2026, 10, 20));
      expect(parseLooseDate('10/20/2026'), DateTime(2026, 10, 20));
    });

    test('returns null for junk instead of throwing', () {
      expect(parseLooseDate(''), isNull);
      expect(parseLooseDate('not a date'), isNull);
    });
  });

  group('status vocabulary', () {
    test('maps backend and display strings to the same tone', () {
      expect(statusTone('pending'), StatusTone.pending);
      expect(statusTone('Pending Verification'), StatusTone.pending);
      expect(statusTone('reimbursed'), StatusTone.paid);
      expect(statusTone('Paid'), StatusTone.paid);
      expect(statusTone('Info Requested'), StatusTone.info);
    });

    test('labels are human readable', () {
      expect(statusLabel('pending'), 'Pending Verification');
      expect(statusLabel('Pending review'), 'Pending Verification');
      expect(statusLabel('info_requested'), 'Info Requested');
      expect(statusLabel('reimbursed'), 'Paid');
      expect(statusLabel('custom_state'), 'custom_state');
    });

    test('colours resolve from the active palette', () {
      expect(statusColor('approved', AppPalette.dark), AppTokens.successBright);
      expect(statusColor('approved', AppPalette.light), AppTokens.success);
      expect(statusColor('rejected', AppPalette.light), AppTokens.danger);
    });
  });

  group('AnalyticsRange', () {
    final DateTime now = DateTime(2026, 10, 20);

    test('this month starts on the first', () {
      final DateTimeRange range = AnalyticsRange.thisMonth.resolve(now);
      expect(range.start, DateTime(2026, 10, 1));
      expect(range.end, DateTime(2026, 10, 20));
    });

    test('three and six month windows are inclusive of the current month', () {
      expect(
        AnalyticsRange.last3Months.resolve(now).start,
        DateTime(2026, 8, 1),
      );
      expect(
        AnalyticsRange.last6Months.resolve(now).start,
        DateTime(2026, 5, 1),
      );
    });

    test('year to date starts in January', () {
      expect(
        AnalyticsRange.yearToDate.resolve(now).start,
        DateTime(2026, 1, 1),
      );
    });
  });

  test('safeFraction never yields NaN or out-of-range values', () {
    expect(safeFraction(double.nan), 0);
    expect(safeFraction(double.infinity), 0);
    expect(safeFraction(-1), 0);
    expect(safeFraction(2), 1);
    expect(safeFraction(0.4), 0.4);
  });

  test('isoDate pads single-digit months and days', () {
    expect(isoDate(DateTime(2026, 1, 5)), '2026-01-05');
  });
}
