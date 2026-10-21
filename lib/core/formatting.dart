import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Presentation helpers shared by every dashboard.
///
/// Keeping these here removed the three private copies of date parsing
/// and the four different money formats the screens had grown.

final NumberFormat _money = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);

final NumberFormat _compact = NumberFormat('0.#', 'en_IN');

final DateFormat _dayMonth = DateFormat('d MMM');
final DateFormat _fullDate = DateFormat('d MMM yyyy');
final DateFormat _monthDay = DateFormat('MMM d');

/// `₹1,24,500` (Indian grouping). Values below ₹1,000 keep no decimals
/// only when they are whole numbers, so a ₹499.50 expense still reads
/// honestly.
String formatMoney(num value, {bool compact = false, int? decimals}) {
  final double amount = value.toDouble();
  if (compact) return _compactMoney(amount);
  if (decimals != null) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: decimals,
    ).format(amount);
  }
  if (amount == amount.roundToDouble()) return _money.format(amount);
  return NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  ).format(amount);
}

String _compactMoney(double amount) {
  final double abs = amount.abs();
  final String sign = amount < 0 ? '-' : '';
  if (abs >= 10000000) return '$sign₹${_compact.format(abs / 10000000)}Cr';
  if (abs >= 100000) return '$sign₹${_compact.format(abs / 100000)}L';
  if (abs >= 1000) return '$sign₹${_compact.format(abs / 1000)}K';
  return '$sign₹${_compact.format(abs)}';
}

/// A percentage from a fraction (`0.42` → `42%`).
String formatFractionPercent(double fraction, {int decimals = 0}) {
  final double pct = (fraction.isFinite ? fraction : 0) * 100;
  return '${pct.toStringAsFixed(decimals)}%';
}

/// A percentage that is already in points (`42` → `42%`).
String formatPercentPoints(double points, {int decimals = 0}) {
  final double value = points.isFinite ? points : 0;
  return '${value.toStringAsFixed(decimals)}%';
}

String formatSignedPercent(double? points) {
  if (points == null) return '—';
  final String sign = points > 0 ? '+' : '';
  return '$sign${points.toStringAsFixed(1)}%';
}

String formatCount(int value) =>
    NumberFormat.decimalPattern('en_IN').format(value);

String formatDate(DateTime date) => _fullDate.format(date);

String formatDayMonth(DateTime date) => _dayMonth.format(date);

String formatShortDay(DateTime date) => _monthDay.format(date);

String formatMonthLabel(DateTime date) => DateFormat('MMM yyyy').format(date);

/// The same month written out — "August 2026". The report screens
/// search on this, so typing the full month name finds the row.
String formatMonthLabelLong(DateTime date) =>
    DateFormat('MMMM yyyy').format(date);

String formatDateRange(DateTime from, DateTime to) {
  if (from.year == to.year && from.month == to.month) {
    return '${_dayMonth.format(from)} – ${_fullDate.format(to)}';
  }
  if (from.year == to.year) {
    return '${_dayMonth.format(from)} – ${_fullDate.format(to)}';
  }
  return '${_fullDate.format(from)} – ${_fullDate.format(to)}';
}

/// Tolerant date parse for values the API and legacy local data contain:
/// ISO dates (`2026-10-20`), ISO datetimes (`2026-10-20T09:15:00`), and
/// the old display format (`20 Oct 2026`).
DateTime? parseLooseDate(String raw) {
  final String value = raw.trim();
  if (value.isEmpty) return null;
  final DateTime? iso = DateTime.tryParse(value);
  if (iso != null) return DateTime(iso.year, iso.month, iso.day);

  final List<String> parts = value.split(RegExp(r'[\s/-]+'));
  if (parts.length < 3) return null;
  const List<String> months = <String>[
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];
  final int? first = int.tryParse(parts[0]);
  final int? second = int.tryParse(parts[1]);
  final int? third = int.tryParse(parts[2]);
  if (first == null || second == null || third == null) {
    if (first != null && third != null) {
      final int month = months.indexOf(parts[1].toLowerCase()) + 1;
      if (month > 0) return DateTime(third, month, first);
    }
    return null;
  }
  if (parts[0].length == 4) return DateTime(first, second, third);
  if (parts[2].length == 4) {
    int month = first;
    int day = second;
    if (month > 12) {
      month = second;
      day = first;
    }
    return DateTime(third, month, day);
  }
  return null;
}

/// Relative time for notification feeds.
String relativeTime(DateTime when, {DateTime? now}) {
  final DateTime reference = now ?? DateTime.now();
  final Duration diff = reference.difference(when);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return formatDate(when);
}

/// The date windows the dashboards offer.
enum AnalyticsRange {
  thisMonth('This month'),
  last3Months('3 months'),
  last6Months('6 months'),
  yearToDate('Year to date');

  const AnalyticsRange(this.label);

  final String label;

  DateTimeRange resolve(DateTime now) {
    final DateTime today = DateTime(now.year, now.month, now.day);
    switch (this) {
      case AnalyticsRange.thisMonth:
        return DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: today,
        );
      case AnalyticsRange.last3Months:
        return DateTimeRange(
          start: DateTime(now.year, now.month - 2, 1),
          end: today,
        );
      case AnalyticsRange.last6Months:
        return DateTimeRange(
          start: DateTime(now.year, now.month - 5, 1),
          end: today,
        );
      case AnalyticsRange.yearToDate:
        return DateTimeRange(start: DateTime(now.year, 1, 1), end: today);
    }
  }
}

String isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
