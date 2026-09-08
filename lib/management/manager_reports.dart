import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:intl/intl.dart';

import 'download_stub.dart' if (dart.library.html) 'download_web.dart' as downloader;

class ManagerReportsScreen extends StatefulWidget {
  const ManagerReportsScreen({super.key});

  @override
  State<ManagerReportsScreen> createState() => _ManagerReportsScreenState();
}

class _ManagerReportsScreenState extends State<ManagerReportsScreen> {
  final ExpenseStore _store = ExpenseStore.instance;
  final String _selectedEmployee = 'All Employees';
  final String _selectedPeriod = 'Till Date';
  String _searchQuery = '';
  String _selectedStatus = 'All';
  DateTime? _selectedDate;

  String _getMonthYear(String dateStr) {
    final parts = dateStr.split(' ');
    if (parts.length >= 3) {
      return '${parts[1]} ${parts[2]}'; 
    }
    return dateStr;
  }

  static const List<String> _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  List<ExpenseRecord> get _filteredExpenses {
    final query = _searchQuery.toLowerCase();

    return _store.expenses.where((e) {
      final matchesStatus = _selectedStatus == 'All' || e.status == _selectedStatus;

      final matchesSearch = query.isEmpty ||
          e.name.toLowerCase().contains(query) ||
          e.id.toLowerCase().contains(query) ||
          e.type.toLowerCase().contains(query);
          
      bool matchesDate = true;
      if (_selectedDate != null) {
        final pickedMonthStr = '${_monthNames[_selectedDate!.month - 1]} ${_selectedDate!.year}';
        matchesDate = _getMonthYear(e.date) == pickedMonthStr;
      }

      return matchesStatus && matchesSearch && matchesDate;
    }).toList();
  }

  double get _totalAmount => _filteredExpenses.fold(0.0, (sum, e) => sum + e.amount);

  String _escapeCsv(String field) {
    if (field.contains(',') || field.contains('"') || field.contains('\n')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }

  void _downloadCsv() {
    final rows = _filteredExpenses;
    if (rows.isEmpty) {
      _showSnack('No approved reimbursements match this filter.', Colors.redAccent);
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('Tracking ID,Employee Name,Email,Expense Type,Amount,Date,Status');
    for (final e in rows) {
      buffer.writeln([
        _escapeCsv(e.id),
        _escapeCsv(e.name),
        _escapeCsv(e.email),
        _escapeCsv(e.type),
        e.amount.toStringAsFixed(2),
        _escapeCsv(e.date),
        _escapeCsv(e.status),
      ].join(','));
    }

    final fileName = 'reimbursement_report_${_selectedEmployee.replaceAll(' ', '_')}_${_selectedPeriod.replaceAll(' ', '_')}.csv';
    final bytes = utf8.encode(buffer.toString());

    if (kIsWeb) {
      downloader.downloadFile(bytes, fileName);
      _showSnack('Report downloaded', Colors.greenAccent.shade400);
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

  // --- FIX: Dynamic Colors for Badges ---
  Color _getStatusColor(String status, Color defaultGold) {
    if (status == 'Paid') return Colors.greenAccent.shade400;
    if (status == 'Approved') return Colors.orangeAccent;
    if (status == 'Rejected') return Colors.redAccent.shade400;
    return defaultGold;
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
        final rows = _filteredExpenses;
        final obsidianBlack = _store.bg;
        final darkCharcoal = _store.card;
        final champagneGold = _store.accentGold;
        final textFrost = _store.textFrost;
        final textMuted = _store.textMuted;
        
        final List<BoxShadow> cardShadows = _store.isDarkMode
            ? <BoxShadow>[]
            : [
                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 4)),
                BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 12), spreadRadius: -4),
                BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 2, offset: const Offset(0, -1)),
              ];

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: darkCharcoal,
            elevation: 0,
            iconTheme: IconThemeData(color: textFrost),
            title: Text('Reimbursement Reports', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold, fontSize: 18)),
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
                    onChanged: (value) => setState(() => _searchQuery = value),
                    style: TextStyle(color: textFrost, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search by employee name, ID or type...',
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
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    // --- FIX: Added "Paid" to filter choices ---
                    child: Row(
                      children: ['All', 'Pending', 'Approved', 'Paid', 'Rejected'].map((status) {
                        final isSelected = _selectedStatus == status;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ChoiceChip(
                            label: Text(status),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) setState(() => _selectedStatus = status);
                            },
                            labelStyle: TextStyle(
                              color: isSelected ? (_store.isDarkMode ? obsidianBlack : Colors.white) : textFrost,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            selectedColor: champagneGold,
                            backgroundColor: darkCharcoal,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: isSelected ? champagneGold : champagneGold.withValues(alpha: 0.15),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
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
                                  ? ColorScheme.dark(primary: champagneGold, onPrimary: obsidianBlack, surface: darkCharcoal, onSurface: textFrost)
                                  : ColorScheme.light(primary: champagneGold, onPrimary: Colors.white, surface: darkCharcoal, onSurface: textFrost), dialogTheme: DialogThemeData(backgroundColor: darkCharcoal),
                              ),
                              child: child!,
                            );
                          },
                        );

                        if (picked != null) {
                          setState(() => _selectedDate = picked);
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
                                  : '${_monthNames[_selectedDate!.month - 1]} ${_selectedDate!.year}',
                              style: TextStyle(color: textFrost, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 4),
                            if (_selectedDate == null)
                              Icon(Icons.arrow_drop_down_rounded, color: champagneGold)
                            else
                              GestureDetector(
                                onTap: () => setState(() => _selectedDate = null), 
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
                            Text('Total reimbursed', style: TextStyle(color: textMuted, fontSize: 12)),
                            const SizedBox(height: 4),
                            Text(NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(_totalAmount), style: TextStyle(color: textFrost, fontSize: 20, fontWeight: FontWeight.w900)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('Records', style: TextStyle(color: textMuted, fontSize: 12)),
                            const SizedBox(height: 4),
                            Text('${rows.length}', style: TextStyle(color: champagneGold, fontSize: 20, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: rows.isEmpty
                        ? Center(child: Text('No matching reimbursements found.', style: TextStyle(color: textMuted)))
                        : ListView.builder(
                            itemCount: rows.length,
                            itemBuilder: (context, index) {
                              final e = rows[index];
                              final statusColor = _getStatusColor(e.status, champagneGold); // --- FIX: Fetch correct color ---
                              
                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
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
                                          Text(e.name, style: TextStyle(color: textFrost, fontWeight: FontWeight.bold, fontSize: 13)),
                                          const SizedBox(height: 2),
                                          Text('${e.type} • ${e.date}', style: TextStyle(color: textMuted, fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                    // --- FIX: Dynamic Badges Added to UI ---
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(e.amountFormatted, style: TextStyle(color: textFrost, fontWeight: FontWeight.w900, fontSize: 14)),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: statusColor.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 1),
                                          ),
                                          child: Text(e.status, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
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