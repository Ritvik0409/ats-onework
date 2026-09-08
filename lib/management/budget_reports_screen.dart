import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:intl/intl.dart';

import 'download_stub.dart' if (dart.library.html) 'download_web.dart' as downloader;

class BudgetReportsScreen extends StatefulWidget {
  const BudgetReportsScreen({super.key});

  @override
  State<BudgetReportsScreen> createState() => _BudgetReportsScreenState();
}

class _BudgetReportsScreenState extends State<BudgetReportsScreen> {
  final ExpenseStore _store = ExpenseStore.instance;
  String _searchQuery = '';
  DateTime? _selectedDate;

  static const List<String> _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  static const List<String> _fullMonthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];



  List<Map<String, dynamic>> _cachedBudgetReports = [];
  bool _isLoadingReports = true;

  @override
  void initState() {
    super.initState();
    _loadBudgetHistory();
  }

  Future<void> _loadBudgetHistory() async {
    setState(() => _isLoadingReports = true);
    final List<Map<String, dynamic>> reports = [];
    final now = DateTime.now();

    for (int i = 0; i < 12; i++) {
      final targetMonth = DateTime(now.year, now.month - i);
      final monthName = '${_fullMonthNames[targetMonth.month - 1]} ${targetMonth.year}';
      final shortMonth = _monthNames[targetMonth.month - 1]; 

      final double budget = await _store.getBudgetForMonth(targetMonth) ?? 0.0;

      double spent = 0.0;
      for (var e in _store.expenses) {
        if (e.status != 'Rejected') {
          if (e.date.contains(shortMonth) && e.date.contains('${targetMonth.year}')) {
            spent += e.amount;
          }
        }
      }

      final double variance = budget - spent;

      if (_searchQuery.isEmpty || monthName.toLowerCase().contains(_searchQuery.toLowerCase())) {
        bool matchesDate = true;
        if (_selectedDate != null) {
          matchesDate = targetMonth.year == _selectedDate!.year && targetMonth.month == _selectedDate!.month;
        }

        if (matchesDate) {
          reports.add({
            'month': monthName,
            'budget': budget,
            'spent': spent,
            'variance': variance,
          });
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _cachedBudgetReports = reports;
      _isLoadingReports = false;
    });
  }

  double get _totalAllocatedBudget => _cachedBudgetReports.fold(0.0, (sum, r) => sum + (r['budget'] as double));
  double get _totalSpentBudget => _cachedBudgetReports.fold(0.0, (sum, r) => sum + (r['spent'] as double));

  void _downloadCsv() {
    if (_cachedBudgetReports.isEmpty) {
      _showSnack('No budget records match this filter.', Colors.redAccent);
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('Fiscal Month,Allocated Budget (INR),Total Spent (INR),Remaining Variance (INR)');
    for (final r in _cachedBudgetReports) {
      buffer.writeln([
        '"${r['month']}"',
        (r['budget'] as double).toStringAsFixed(2),
        (r['spent'] as double).toStringAsFixed(2),
        (r['variance'] as double).toStringAsFixed(2),
      ].join(','));
    }

    final fileName = 'budget_allocation_report_${DateTime.now().millisecondsSinceEpoch}.csv';
    final bytes = utf8.encode(buffer.toString());

    if (kIsWeb) {
      downloader.downloadFile(bytes, fileName);
      _showSnack('Budget CSV Report downloaded', Colors.greenAccent.shade400);
    } else {
      _showSnack('CSV export is currently supported on the web build only.', _store.accentGold);
    }
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 600;
    final double bottomSafeArea = MediaQuery.of(context).padding.bottom; 
    final double extraBottomPadding = isMobile && bottomSafeArea > 0 ? bottomSafeArea + 16 : 0.0;

    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final obsidianBlack = _store.bg;
        final darkCharcoal = _store.card;
        final champagneGold = _store.accentGold;
        final textFrost = _store.textFrost;
        final textMuted = _store.textMuted;

        final List<BoxShadow> cardShadows = _store.isDarkMode
            ? <BoxShadow>[]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ];

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: darkCharcoal,
            elevation: 0,
            iconTheme: IconThemeData(color: textFrost),
            title: Text('Budget Allocation Reports', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold, fontSize: 18)),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(color: champagneGold.withValues(alpha: 0.15), height: 1),
            ),
          ),
          body: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 700),
              padding: EdgeInsets.fromLTRB(20.0, 20.0, 20.0, 20.0 + extraBottomPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    onChanged: (value) {
                      setState(() => _searchQuery = value);
                      _loadBudgetHistory();
                    },
                    style: TextStyle(color: textFrost, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search fiscal month (e.g. August 2026)...',
                      hintStyle: TextStyle(color: textMuted.withValues(alpha: 0.7)),
                      prefixIcon: Icon(Icons.search_rounded, color: champagneGold),
                      filled: true,
                      fillColor: darkCharcoal,
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: champagneGold.withValues(alpha: 0.15)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: champagneGold, width: 1.5),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () async {
                        final DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: _store.isDarkMode 
                                  ? ColorScheme.dark(
                                      primary: champagneGold,
                                      onPrimary: obsidianBlack,
                                      surface: darkCharcoal,
                                      onSurface: textFrost,
                                    )
                                  : ColorScheme.light(
                                      primary: champagneGold,
                                      onPrimary: Colors.white,
                                      surface: darkCharcoal,
                                      onSurface: textFrost,
                                    ), dialogTheme: DialogThemeData(backgroundColor: darkCharcoal),
                              ),
                              child: child!,
                            );
                          },
                        );

                        if (picked != null) {
                          setState(() => _selectedDate = picked);
                          _loadBudgetHistory();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: darkCharcoal,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: champagneGold.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.calendar_month_rounded, size: 16, color: champagneGold),
                            const SizedBox(width: 8),
                            Text(
                              _selectedDate == null
                                  ? 'All Time'
                                  : '${_fullMonthNames[_selectedDate!.month - 1]} ${_selectedDate!.year}',
                              style: TextStyle(color: textFrost, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 4),
                            if (_selectedDate == null)
                              Icon(Icons.arrow_drop_down_rounded, color: champagneGold)
                            else
                              GestureDetector(
                                onTap: () {
                                  setState(() => _selectedDate = null);
                                  _loadBudgetHistory();
                                },
                                child: Icon(Icons.close_rounded, size: 18, color: champagneGold),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: darkCharcoal,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _store.isDarkMode ? champagneGold.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)),
                      boxShadow: cardShadows,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total Allocated', style: TextStyle(color: textMuted, fontSize: 12)),
                            const SizedBox(height: 4),
                            Text(NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(_totalAllocatedBudget), 
                                 style: TextStyle(color: textFrost, fontSize: 18, fontWeight: FontWeight.w900)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('Total Spent', style: TextStyle(color: textMuted, fontSize: 12)),
                            const SizedBox(height: 4),
                            Text(NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(_totalSpentBudget), 
                                 style: TextStyle(color: champagneGold, fontSize: 18, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  Expanded(
                    child: _isLoadingReports
                        ? Center(child: CircularProgressIndicator(color: champagneGold))
                        : _cachedBudgetReports.isEmpty
                            ? Center(child: Text('No budget records match this filter.', style: TextStyle(color: textMuted)))
                            : ListView.builder(
                                itemCount: _cachedBudgetReports.length,
                                itemBuilder: (context, index) {
                                  final r = _cachedBudgetReports[index];
                                  final double budget = r['budget'];
                                  final double spent = r['spent'];
                                  final double variance = r['variance'];

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: darkCharcoal,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: _store.isDarkMode ? champagneGold.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.2)),
                                      boxShadow: cardShadows,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(r['month'], style: TextStyle(color: textFrost, fontWeight: FontWeight.bold, fontSize: 14)),
                                              const SizedBox(height: 4),
                                              Text('Spent: ₹${spent.toStringAsFixed(2)} • Remaining: ₹${variance.toStringAsFixed(2)}', 
                                                   style: TextStyle(color: variance < 0 ? Colors.redAccent : textMuted, fontSize: 11)),
                                            ],
                                          ),
                                        ),
                                        Text('₹${budget.toStringAsFixed(0)}', style: TextStyle(color: champagneGold, fontWeight: FontWeight.bold, fontSize: 14)),
                                      ],
                                    ),
                                  );
                                },
                              ),
                  ),

                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _downloadCsv,
                      icon: Icon(Icons.download_rounded, color: _store.isDarkMode ? obsidianBlack : Colors.white),
                      label: Text('Download CSV Report', style: TextStyle(fontWeight: FontWeight.bold, color: _store.isDarkMode ? obsidianBlack : Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: champagneGold,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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